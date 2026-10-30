package com.karandeep.sathi;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.graphics.pdf.PdfDocument;
import android.net.Uri;
import android.os.*;
import android.view.*;
import android.widget.*;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.app.AppCompatDelegate;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.color.DynamicColors;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.firebase.auth.FirebaseAuth;
import java.io.*;
import java.util.*;
import org.json.*;

/** Native pen/stylus canvas, preserving all shared JSON fields and original PencilKit data. */
public class NotebookPageActivity extends AppCompatActivity {
  Store store;
  JSONObject page, metadata;
  NotebookSurface surface;
  LinearLayout root, proTools;
  boolean dirty, pro, syncPending;
  float zoom = 1;
  String account, pageID;
  Handler handler = new Handler(Looper.getMainLooper());
  Runnable pending;
  TextView state;
  int foreground, background;

  public void onCreate(Bundle saved) {
    String mode = getSharedPreferences("appearance", 0).getString("mode", "system");
    AppCompatDelegate.setDefaultNightMode(
        mode.equals("dark")
            ? AppCompatDelegate.MODE_NIGHT_YES
            : mode.equals("light")
                ? AppCompatDelegate.MODE_NIGHT_NO
                : AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM);
    setTheme(R.style.SathiTheme);
    super.onCreate(saved);
    if (getSharedPreferences("appearance", 0).getBoolean("systemAccent", true))
      DynamicColors.applyToActivityIfAvailable(this);
    try {
      if (FirebaseAuth.getInstance().getCurrentUser() == null) {
        finish();
        return;
      }
      account = FirebaseAuth.getInstance().getCurrentUser().getUid();
      store = Store.get(this);
      store.activate();
      pageID = getIntent().getStringExtra("pageID");
      page = store.asset(pageID);
      metadata = store.assetIndex().getJSONObject(pageID);
      build();
      getOnBackPressedDispatcher()
          .addCallback(
              this,
              new androidx.activity.OnBackPressedCallback(true) {
                public void handleOnBackPressed() {
                  saveNow();
                  finish();
                }
              });
    } catch (Exception e) {
      new MaterialAlertDialogBuilder(this)
          .setTitle("Page unavailable")
          .setMessage(e.getMessage())
          .setPositiveButton("Back", (d, w) -> finish())
          .show();
    }
  }

  int dp(int v) {
    return Math.round(v * getResources().getDisplayMetrics().density);
  }

  Button button(String title, Runnable action) {
    MaterialButton b =
        new MaterialButton(
            this, null, com.google.android.material.R.attr.materialButtonOutlinedStyle);
    b.setText(title);
    b.setAllCaps(false);
    b.setMinHeight(dp(48));
    b.setOnClickListener(v -> action.run());
    return b;
  }

  LinearLayout row() {
    LinearLayout r = new LinearLayout(this);
    r.setGravity(Gravity.CENTER_VERTICAL);
    return r;
  }

  void tools(LinearLayout target, String title, Runnable action) {
    target.addView(button(title, action), new LinearLayout.LayoutParams(-2, dp(52)));
  }

  void build() throws Exception {
    boolean dark =
        (getResources().getConfiguration().uiMode
                & android.content.res.Configuration.UI_MODE_NIGHT_MASK)
            == android.content.res.Configuration.UI_MODE_NIGHT_YES;
    foreground = dark ? 0xFFF1F3F8 : 0xFF182333;
    background = dark ? 0xFF10151D : 0xFFF3F6FA;
    root = new LinearLayout(this);
    root.setOrientation(LinearLayout.VERTICAL);
    root.setFitsSystemWindows(true);
    root.setBackgroundColor(background);
    setContentView(root);
    LinearLayout top = row();
    tools(
        top,
        "Back",
        () -> {
          saveNow();
          finish();
        });
    TextView title = new TextView(this);
    title.setText(metadata.optString("title", "Notebook"));
    title.setTextColor(foreground);
    title.setTextSize(18);
    top.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
    tools(top, "Sync", this::sync);
    root.addView(top);
    state = new TextView(this);
    state.setTextColor(foreground);
    state.setTextSize(12);
    state.setPadding(dp(16), 0, dp(16), 0);
    state.setText("Saved locally · pen, typing and portable image layers");
    root.addView(state);
    surface = new NotebookSurface(this, page);
    surface.changed =
        () -> {
          dirty = true;
          if (pending != null) handler.removeCallbacks(pending);
          pending = () -> saveNow();
          handler.postDelayed(pending, 500);
        };
    surface.zoomChanged = factor -> setZoom(zoom * factor);
    HorizontalScrollView toolScroll = new HorizontalScrollView(this);
    toolScroll.setHorizontalScrollBarEnabled(false);
    LinearLayout bar = row();
    toolScroll.addView(bar);
    tools(
        bar,
        "Pen",
        () -> {
          surface.mode = NotebookSurface.PEN;
          state.setText("Pen · two fingers to zoom; Pan to scroll");
        });
    tools(
        bar,
        "Eraser",
        () -> {
          surface.mode = NotebookSurface.ERASER;
          state.setText("Eraser · removes Android ink");
        });
    tools(bar, "Pan", () -> surface.mode = NotebookSurface.PAN);
    tools(bar, "Undo", surface::undo);
    tools(bar, "Type", () -> editText(null));
    tools(bar, "Ink", this::inkSettings);
    tools(
        bar,
        "Pro",
        () -> {
          pro = !pro;
          proTools.setVisibility(pro ? View.VISIBLE : View.GONE);
          surface.mode = pro ? NotebookSurface.SELECT : NotebookSurface.PEN;
        });
    tools(bar, "−", () -> setZoom(zoom / 1.25f));
    tools(bar, "+", () -> setZoom(zoom * 1.25f));
    tools(bar, "PDF", this::exportCurrent);
    root.addView(toolScroll);
    proTools = new LinearLayout(this);
    proTools.setOrientation(LinearLayout.VERTICAL);
    HorizontalScrollView extra = new HorizontalScrollView(this);
    LinearLayout advanced = row();
    extra.addView(advanced);
    tools(advanced, "Select", () -> surface.mode = NotebookSurface.SELECT);
    tools(
        advanced,
        "Shape",
        () ->
            new MaterialAlertDialogBuilder(this)
                .setTitle("Add shape")
                .setItems(
                    new String[] {"Rectangle", "Ellipse", "Line", "Arrow"},
                    (d, i) -> {
                      try {
                        surface.add(
                            NotebookDocuments.element(
                                new String[] {"rectangle", "ellipse", "line", "arrow"}[i], 60, 100),
                            false);
                        surface.mode = NotebookSurface.SELECT;
                      } catch (Exception e) {
                        showError(e);
                      }
                    })
                .show());
    tools(
        advanced,
        "Image",
        () ->
            startActivityForResult(
                new Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("image/*"),
                7));
    tools(advanced, "Properties", this::properties);
    tools(advanced, "Layers", this::layers);
    tools(advanced, "Copy", this::copy);
    tools(advanced, "Paste", this::paste);
    proTools.addView(extra);
    proTools.setVisibility(View.GONE);
    root.addView(proTools);
    if (!page.optString("drawing").isEmpty() && page.optString("previewPNG").isEmpty()) {
      TextView warning = new TextView(this);
      warning.setText(
          "Original Apple PencilKit ink is preserved. Edit that ink on Apple; Android ink and other"
              + " layers remain editable here.");
      warning.setTextColor(foreground);
      warning.setTextSize(11);
      root.addView(warning);
    }
    ScrollView vertical = new ScrollView(this);
    HorizontalScrollView horizontal = new HorizontalScrollView(this);
    android.widget.FrameLayout center = new FrameLayout(this);
    center.addView(
        surface,
        new android.widget.FrameLayout.LayoutParams(
            Math.max(200, getResources().getDisplayMetrics().widthPixels - dp(24)),
            1,
            Gravity.CENTER_HORIZONTAL));
    horizontal.addView(center);
    vertical.addView(horizontal);
    root.addView(vertical, new LinearLayout.LayoutParams(-1, 0, 1));
    setZoom(1);
  }

  void setZoom(float value) {
    zoom = Math.max(0.5f, Math.min(3, value));
    double[] size = NotebookSurface.size(page);
    int width = (int) ((getResources().getDisplayMetrics().widthPixels - dp(24)) * zoom);
    surface.setLayoutParams(
        new android.widget.FrameLayout.LayoutParams(
            width, (int) (width * size[1] / size[0]), Gravity.CENTER_HORIZONTAL));
    surface.invalidate();
  }

  void saveNow() {
    if (pending != null) {
      handler.removeCallbacks(pending);
      pending = null;
    }
    if (!dirty || store == null || surface == null) return;
    try {
      surface.flushInk();
      page.put("modifiedAt", Snapshot.swiftNow());
      store.saveAsset(
          pageID, "notebookPage", metadata.optString("title"), metadata.optString("subject"), page);
      dirty = false;
      state.setText("Saved locally · Sync sends this page to your account");
    } catch (Exception e) {
      showError(e);
    }
  }

  void sync() {
    saveNow();
    if (store == null) return;
    if (store.busy()) {
      syncPending = true;
      return;
    }
    state.setText("Syncing in background…");
    store.sync(
        (message, ok) ->
            runOnUiThread(
                () -> {
                  state.setText(message);
                  if (syncPending) {
                    syncPending = false;
                    sync();
                  }
                }));
  }

  public void onResume() {
    super.onResume();
    if (store != null) {
      if (FirebaseAuth.getInstance().getCurrentUser() == null
          || !account.equals(FirebaseAuth.getInstance().getCurrentUser().getUid())) {
        finish();
        return;
      }
      store.startLiveUpdates(
          (m, changed) ->
              runOnUiThread(
                  () -> {
                    if (changed) sync();
                    else state.setText(m);
                  }));
    }
  }

  public void onPause() {
    saveNow();
    if (store != null) store.stopLiveUpdates();
    super.onPause();
  }

  public void onDestroy() {
    if (pending != null) handler.removeCallbacks(pending);
    super.onDestroy();
  }

  void editText(JSONObject existing) {
    try {
      LinearLayout form = new LinearLayout(this);
      form.setOrientation(LinearLayout.VERTICAL);
      form.setPadding(dp(20), dp(8), dp(20), dp(8));
      EditText input = new EditText(this);
      input.setText(existing == null ? "" : existing.optString("text"));
      input.setHint("Type your note");
      input.setMinLines(5);
      input.setGravity(Gravity.TOP);
      form.addView(input, new LinearLayout.LayoutParams(-1, -2));
      new MaterialAlertDialogBuilder(this)
          .setTitle("Text")
          .setView(form)
          .setNegativeButton("Cancel", null)
          .setPositiveButton(
              "Save",
              (d, w) -> {
                try {
                  if (existing != null) {
                    existing.put("text", input.getText().toString());
                    surface.changed.run();
                    surface.invalidate();
                  } else {
                    JSONObject text =
                        NotebookDocuments.element("text", 48, 70)
                            .put("text", input.getText().toString())
                            .put("width", Math.max(150, NotebookSurface.size(page)[0] - 96))
                            .put("height", 180)
                            .put("fontSize", 18)
                            .put("italic", false)
                            .put("underline", false)
                            .put("alignment", "left");
                    if (!pro) text.remove("kind");
                    surface.add(text, !pro);
                  }
                } catch (Exception e) {
                  showError(e);
                }
              })
          .show();
    } catch (Exception e) {
      showError(e);
    }
  }

  void inkSettings() {
    LinearLayout form = new LinearLayout(this);
    form.setOrientation(LinearLayout.VERTICAL);
    form.setPadding(dp(20), dp(8), dp(20), dp(8));
    CheckBox fingers = new CheckBox(this);
    fingers.setText("Allow finger drawing (stylus always works)");
    fingers.setChecked(surface.fingerInk);
    form.addView(fingers);
    SeekBar width = new SeekBar(this);
    width.setMax(18);
    width.setProgress((int) surface.brush);
    form.addView(label("Brush width"));
    form.addView(width);
    SeekBar alpha = new SeekBar(this);
    alpha.setMax(100);
    alpha.setProgress((int) (surface.opacity * 100));
    form.addView(label("Ink opacity"));
    form.addView(alpha);
    LinearLayout colors = row();
    int[] palette = {0xFF172536, 0xFF315FAA, 0xFFB24752, 0xFF278569, 0xFF9670BD};
    for (int color : palette) {
      Button b = button("●", () -> surface.color = color);
      b.setTextColor(color);
      colors.addView(b);
    }
    form.addView(colors);
    new MaterialAlertDialogBuilder(this)
        .setTitle("Ink settings")
        .setView(form)
        .setPositiveButton(
            "Done",
            (d, w) -> {
              surface.fingerInk = fingers.isChecked();
              surface.brush = Math.max(1, width.getProgress());
              surface.opacity = Math.max(0.05f, alpha.getProgress() / 100f);
            })
        .show();
  }

  TextView label(String text) {
    TextView view = new TextView(this);
    view.setText(text);
    view.setTextColor(foreground);
    return view;
  }

  void properties() {
    JSONObject selected = surface.selected;
    if (selected == null) {
      state.setText("Choose Select, then tap an element first.");
      return;
    }
    LinearLayout form = new LinearLayout(this);
    form.setOrientation(LinearLayout.VERTICAL);
    form.setPadding(dp(20), dp(8), dp(20), dp(8));
    if (selected.has("text")) form.addView(button("Edit text", () -> editText(selected)));
    EditText size = new EditText(this);
    size.setHint("Text size");
    size.setInputType(2);
    size.setText(String.valueOf(selected.optInt("fontSize", 22)));
    form.addView(size);
    SeekBar opacity = new SeekBar(this);
    opacity.setMax(100);
    opacity.setProgress((int) (100 * selected.optDouble("opacity", 1)));
    form.addView(label("Element opacity"));
    form.addView(opacity);
    SeekBar width = new SeekBar(this);
    width.setMax((int) NotebookSurface.size(page)[0]);
    width.setProgress((int) selected.optDouble("width", 180));
    form.addView(label("Width"));
    form.addView(width);
    SeekBar height = new SeekBar(this);
    height.setMax((int) NotebookSurface.size(page)[1]);
    height.setProgress((int) selected.optDouble("height", 100));
    form.addView(label("Height"));
    form.addView(height);
    CheckBox bold = new CheckBox(this);
    bold.setText("Bold");
    bold.setChecked(selected.optBoolean("bold"));
    form.addView(bold);
    LinearLayout colors = row();
    for (int color : new int[] {0xFF172536, 0xFF315FAA, 0xFFB24752, 0xFF278569}) {
      Button b =
          button(
              "●",
              () -> {
                try {
                  selected.put("color", NotebookDocuments.color(color));
                  surface.changed.run();
                  surface.invalidate();
                } catch (Exception e) {
                  showError(e);
                }
              });
      b.setTextColor(color);
      colors.addView(b);
    }
    form.addView(colors);
    LinearLayout actions = row();
    actions.addView(button("Duplicate", () -> duplicate()));
    actions.addView(
        button(
            "Delete",
            () -> {
              try {
                surface.removeSelected();
              } catch (Exception e) {
                showError(e);
              }
            }));
    form.addView(actions);
    actions = row();
    actions.addView(
        button(
            "Bring front",
            () -> {
              try {
                surface.reorder(true);
              } catch (Exception e) {
                showError(e);
              }
            }));
    actions.addView(
        button(
            "Send back",
            () -> {
              try {
                surface.reorder(false);
              } catch (Exception e) {
                showError(e);
              }
            }));
    form.addView(actions);
    ScrollView scroll = new ScrollView(this);
    scroll.addView(form);
    new MaterialAlertDialogBuilder(this)
        .setTitle("Element properties")
        .setView(scroll)
        .setPositiveButton(
            "Done",
            (d, w) -> {
              try {
                selected
                    .put(
                        "fontSize",
                        Math.max(8, Math.min(100, Integer.parseInt(size.getText().toString()))))
                    .put("bold", bold.isChecked())
                    .put("opacity", opacity.getProgress() / 100.0)
                    .put("width", Math.max(20, width.getProgress()))
                    .put("height", Math.max(20, height.getProgress()));
                surface.changed.run();
                surface.invalidate();
              } catch (Exception e) {
                showError(e);
              }
            })
        .show();
  }

  void duplicate() {
    try {
      if (surface.selected == null) return;
      JSONObject copy =
          new JSONObject(surface.selected.toString())
              .put("id", NotebookDocuments.id())
              .put("x", surface.selected.optDouble("x") + 20)
              .put("y", surface.selected.optDouble("y") + 20);
      surface.add(copy, surface.selectedText);
    } catch (Exception e) {
      showError(e);
    }
  }

  void layers() {
    try {
      List<JSONObject> values = new ArrayList<>();
      List<Boolean> text = new ArrayList<>();
      for (String group : new String[] {"elements", "textObjects"}) {
        JSONArray array = page.optJSONArray(group);
        if (array != null)
          for (int i = 0; i < array.length(); i++) {
            JSONObject e = array.getJSONObject(i);
            if (e.optString("id").startsWith("android-ink-")) continue;
            values.add(e);
            text.add(group.equals("textObjects"));
          }
      }
      String[] labels = new String[values.size()];
      for (int i = 0; i < labels.length; i++)
        labels[i] =
            (i + 1)
                + " · "
                + values.get(i).optString("kind", "Text")
                + " "
                + values.get(i).optString("text", "");
      new MaterialAlertDialogBuilder(this)
          .setTitle("Layers (bottom to top)")
          .setItems(
              labels,
              (d, i) -> {
                surface.selected = values.get(i);
                surface.selectedText = text.get(i);
                surface.mode = NotebookSurface.SELECT;
                surface.invalidate();
                properties();
              })
          .setNegativeButton("Done", null)
          .show();
    } catch (Exception e) {
      showError(e);
    }
  }

  void copy() {
    if (surface.selected == null) return;
    ((android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE))
        .setPrimaryClip(ClipData.newPlainText("SATHI element", surface.selected.toString()));
  }

  void paste() {
    try {
      android.content.ClipboardManager clipboard =
          (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
      if (!clipboard.hasPrimaryClip()) return;
      String value = clipboard.getPrimaryClip().getItemAt(0).coerceToText(this).toString();
      if (value.length() > 1000000) throw new Exception("Clipboard item is too large");
      JSONObject item;
      try {
        item = new JSONObject(value);
      } catch (Exception e) {
        item =
            NotebookDocuments.element("text", 50, 100)
                .put("text", value)
                .put("italic", false)
                .put("underline", false)
                .put("alignment", "left");
        item.remove("kind");
      }
      item.put("id", NotebookDocuments.id())
          .put("x", item.optDouble("x", 50) + 15)
          .put("y", item.optDouble("y", 100) + 15);
      surface.add(item, !item.has("kind"));
    } catch (Exception e) {
      showError(e);
    }
  }

  public void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (request != 7 || result != RESULT_OK || data == null) return;
    Uri uri = data.getData();
    store.io.execute(
        () -> {
          try {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            try (InputStream in = getContentResolver().openInputStream(uri)) {
              BitmapFactory.decodeStream(in, null, bounds);
            }
            int sample = 1;
            while (bounds.outWidth / sample > 1600 || bounds.outHeight / sample > 1600) sample *= 2;
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = sample;
            Bitmap image;
            try (InputStream in = getContentResolver().openInputStream(uri)) {
              image = BitmapFactory.decodeStream(in, null, options);
            }
            if (image == null) throw new IOException("Image could not be read");
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            image.compress(
                image.hasAlpha() ? Bitmap.CompressFormat.PNG : Bitmap.CompressFormat.JPEG, 85, out);
            byte[] bytes = out.toByteArray();
            if (bytes.length > 8000000) throw new IOException("Choose a smaller image");
            double width = Math.min(400, NotebookSurface.size(page)[0] - 80),
                height = width * image.getHeight() / image.getWidth();
            runOnUiThread(
                () -> {
                  try {
                    surface.add(
                        NotebookDocuments.element("image", 40, 80)
                            .put("width", width)
                            .put("height", height)
                            .put("image", java.util.Base64.getEncoder().encodeToString(bytes)),
                        false);
                  } catch (Exception e) {
                    showError(e);
                  }
                });
          } catch (Exception e) {
            runOnUiThread(() -> showError(e));
          }
        });
  }

  void exportCurrent() {
    saveNow();
    store.io.execute(
        () -> {
          try {
            JSONArray ids = new JSONArray().put(pageID);
            File file =
                exportPdf(
                    this,
                    store,
                    new JSONObject().put("pageIDs", ids).put("title", "Notebook page"));
            runOnUiThread(() -> sharePdf(this, file));
          } catch (Exception e) {
            runOnUiThread(() -> showError(e));
          }
        });
  }

  public static File exportPdf(Context context, Store store, JSONObject book) throws Exception {
    JSONArray ids = book.getJSONArray("pageIDs");
    if (ids.length() == 0) throw new IOException("Add a page first");
    PdfDocument pdf = new PdfDocument();
    try {
      for (int i = 0; i < ids.length(); i++) {
        JSONObject page = store.asset(ids.getString(i));
        if (!page.optString("drawing").isEmpty() && page.optString("previewPNG").isEmpty())
          throw new IOException(
              "This page contains original Apple handwriting. Export that page from Apple for a"
                  + " complete PDF; Android preserves its original ink.");
        double[] size = NotebookSurface.size(page);
        PdfDocument.Page out =
            pdf.startPage(
                new PdfDocument.PageInfo.Builder((int) size[0], (int) size[1], i + 1).create());
        NotebookSurface.drawPage(out.getCanvas(), page, new HashMap<>(), false);
        pdf.finishPage(out);
      }
      File folder = new File(context.getCacheDir(), "exports");
      folder.mkdirs();
      File output = new File(folder, "SATHI-notebook-" + System.currentTimeMillis() + ".pdf");
      try (OutputStream stream = new FileOutputStream(output)) {
        pdf.writeTo(stream);
      }
      return output;
    } finally {
      pdf.close();
    }
  }

  public static void sharePdf(Context context, File file) {
    Uri uri =
        androidx.core.content.FileProvider.getUriForFile(
            context, context.getPackageName() + ".files", file);
    context.startActivity(
        Intent.createChooser(
            new Intent(Intent.ACTION_SEND)
                .setType("application/pdf")
                .putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            "Share notebook PDF"));
  }

  void showError(Exception e) {
    if (state != null) state.setText(e.getMessage());
    new MaterialAlertDialogBuilder(this)
        .setTitle("Could not complete action")
        .setMessage(e.getMessage())
        .setPositiveButton("OK", null)
        .show();
  }
}
