package com.karandeep.sathi;

import android.app.*;
import android.content.*;
import android.content.res.Configuration;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.app.AppCompatDelegate;
import androidx.credentials.*;
import androidx.credentials.exceptions.*;
import com.google.android.libraries.identity.googleid.*;
import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.bottomnavigation.BottomNavigationView;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.color.DynamicColors;
import com.google.android.material.color.MaterialColors;
import com.google.android.material.datepicker.MaterialDatePicker;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.material.materialswitch.MaterialSwitch;
import com.google.android.material.navigation.NavigationBarView;
import com.google.android.material.navigationrail.NavigationRailView;
import com.google.android.material.textfield.TextInputEditText;
import com.google.android.material.textfield.TextInputLayout;
import com.google.android.material.timepicker.MaterialTimePicker;
import com.google.android.material.timepicker.TimeFormat;
import com.google.firebase.auth.*;
import java.io.*;
import java.time.*;
import java.time.format.*;
import java.util.*;
import org.json.*;

/** Native Android screens; all network and workbook work runs outside the UI thread. */
public class MainActivity extends AppCompatActivity {
  Store store;
  LinearLayout root, body, header;
  TextView statusView;
  int tabIndex = 0;
  LocalDate selectedDate = Schedule.today();
  boolean dark;
  int bg, card, ink, secondary, accent;
  String status = "Saved on this device";
  Handler handler = new Handler(Looper.getMainLooper());
  private Dialog editor;
  private Runnable saveDraft;
  private boolean authBusy;
  private ScrollView contentScroll;
  private int renderedTab = -1;
  private boolean nextSemesterImport = false;
  private JSONObject pendingImportPreferences;
  private int importSemester = 1;
  private String pendingProgramme = "";
  private java.util.function.Consumer<Uri> documentResult;
  private boolean reviewing = false;
  private Set<String> reviewSelection;
  private String wholeProgramme = "All", wholeSection = "All";
  private LocalDate wholeDate = Schedule.today();
  private final Runnable hourly =
      new Runnable() {
        public void run() {
          if (FirebaseAuth.getInstance().getCurrentUser() != null
              && System.currentTimeMillis() - store.lastSync() >= 3600000) sync(false);
          handler.postDelayed(this, 60000);
        }
      };

  public void onCreate(Bundle saved) {
    String initialMode = getSharedPreferences("appearance", 0).getString("mode", "system");
    AppCompatDelegate.setDefaultNightMode(
        initialMode.equals("dark")
            ? AppCompatDelegate.MODE_NIGHT_YES
            : initialMode.equals("light")
                ? AppCompatDelegate.MODE_NIGHT_NO
                : AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM);
    setTheme(R.style.SathiTheme);
    super.onCreate(saved);
    if (getSharedPreferences("appearance", 0).getBoolean("systemAccent", true))
      DynamicColors.applyToActivityIfAvailable(this);
    if (!SathiApp.configured) {
      LinearLayout setup = new LinearLayout(this);
      setup.setOrientation(LinearLayout.VERTICAL);
      setup.setGravity(Gravity.CENTER);
      setup.setPadding(48, 48, 48, 48);
      TextView message = new TextView(this);
      message.setText(
          "SATHI developer setup\n\n"
              + "Configure your own Firebase project before using sign-in and cloud sync. See"
              + " docs/SETUP.md and run scripts/configure_android.py with your"
              + " google-services.json.");
      message.setTextSize(18);
      setup.addView(message);
      setContentView(setup);
      return;
    }
    store = Store.get(this);
    try {
      store.activate();
    } catch (Exception e) {
      status = e.getMessage();
    }
    if (saved != null) {
      tabIndex = saved.getInt("tab");
      selectedDate = LocalDate.parse(saved.getString("date", Schedule.today().toString()));
    }
    render();
    if (FirebaseAuth.getInstance().getCurrentUser() != null) sync(false);
    handler.postDelayed(hourly, 60000);
    handler.post(() -> routeIntent(getIntent()));
  }

  public void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    setIntent(intent);
    routeIntent(intent);
  }

  void routeIntent(Intent intent) {
    if (store == null || FirebaseAuth.getInstance().getCurrentUser() == null) return;
    String expected = intent.getStringExtra("account");
    if (expected != null && !expected.equals(FirebaseAuth.getInstance().getCurrentUser().getUid()))
      return;
    String date = intent.getStringExtra("date");
    try {
      if (date != null) selectedDate = LocalDate.parse(date);
    } catch (Exception ignored) {
    }
    Uri data = intent.getData();
    String route = data == null ? "" : data.getHost();
    if ("notebooks".equals(route)) tabIndex = 2;
    else if ("calendar".equals(route)) tabIndex = 1;
    else tabIndex = 0;
    render();
    if ("add".equals(route)) handler.post(this::addEvent);
  }

  public void onSaveInstanceState(Bundle out) {
    super.onSaveInstanceState(out);
    out.putInt("tab", tabIndex);
    out.putString("date", selectedDate.toString());
  }

  private void startLiveUpdates() {
    if (store == null) return;
    store.startLiveUpdates(
        (message, changed) ->
            runOnUiThread(
                () -> {
                  if (changed) sync(false);
                  else {
                    status = message;
                    if (editor == null) render();
                  }
                }));
  }

  public void onResume() {
    super.onResume();
    if (store != null && FirebaseAuth.getInstance().getCurrentUser() != null) {
      startLiveUpdates();
      sync(false);
    }
  }

  public void onPause() {
    if (store != null) store.stopLiveUpdates();
    flushDraft();
    super.onPause();
  }

  public void onDestroy() {
    handler.removeCallbacks(hourly);
    flushDraft();
    super.onDestroy();
  }

  int dp(float n) {
    return Math.round(n * getResources().getDisplayMetrics().density);
  }

  void appearance() {
    String mode = getSharedPreferences("appearance", 0).getString("mode", "system");
    dark =
        mode.equals("dark")
            || (mode.equals("system")
                && (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                    == Configuration.UI_MODE_NIGHT_YES);
    bg =
        MaterialColors.getColor(
            this, com.google.android.material.R.attr.colorSurface, dark ? 0xFF101418 : 0xFFF7F9FC);
    card =
        MaterialColors.getColor(
            this,
            com.google.android.material.R.attr.colorSurfaceContainer,
            dark ? 0xFF1B2026 : 0xFFEDF1F8);
    ink =
        MaterialColors.getColor(
            this,
            com.google.android.material.R.attr.colorOnSurface,
            dark ? 0xFFF1F5FB : 0xFF17253B);
    secondary =
        MaterialColors.getColor(
            this,
            com.google.android.material.R.attr.colorOnSurfaceVariant,
            dark ? 0xFFB6C1CF : 0xFF526071);
    String color = store.object("study:preferences").optString("accent", "blue");
    String[] accentNames = {
      "blue", "purple", "green", "teal", "indigo", "pink", "orange", "mint", "cyan", "red", "brown",
      "yellow"
    };
    String[] accentValues = {
      "#448AFF", "#9B7DE8", "#35A583", "#26A69A", "#7986CB", "#EC7AAB", "#EF9950", "#55BDA5",
      "#4DB6D1", "#E66B70", "#AE8B75", "#D2AA45"
    };
    accent = Color.parseColor(dark ? "#72B9F7" : "#1679C8");
    for (int i = 0; i < accentNames.length; i++)
      if (accentNames[i].equals(color)) accent = Color.parseColor(accentValues[i]);
    if (android.os.Build.VERSION.SDK_INT >= 31
        && getSharedPreferences("appearance", 0).getBoolean("systemAccent", true)) {
      accent =
          getColor(dark ? android.R.color.system_accent1_200 : android.R.color.system_accent1_500);
    }
    getWindow().setStatusBarColor(bg);
    getWindow().setNavigationBarColor(bg);
    getWindow()
        .getDecorView()
        .setSystemUiVisibility(
            dark
                ? 0
                : View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
  }

  TextView text(String value, int size, int color, boolean bold) {
    TextView v = new TextView(this);
    v.setText(value);
    v.setTextSize(
        (float)
            (size
                * Math.max(
                    0.8,
                    Math.min(
                        1.4,
                        store == null
                            ? 1
                            : store.object("study:preferences").optDouble("fontScale", 1)))));
    v.setTextColor(color);
    v.setFontFeatureSettings("kern");
    if (bold) v.setTypeface(null, Typeface.BOLD);
    v.setLineSpacing(dp(2), 1);
    return v;
  }

  LinearLayout vertical() {
    LinearLayout v = new LinearLayout(this);
    v.setOrientation(LinearLayout.VERTICAL);
    return v;
  }

  LinearLayout row() {
    LinearLayout r = new LinearLayout(this);
    r.setGravity(Gravity.CENTER_VERTICAL);
    return r;
  }

  GradientDrawable shape(int color, int radius) {
    GradientDrawable d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(radius));
    return d;
  }

  void gap(LinearLayout parent, int h) {
    View v = new View(this);
    parent.addView(v, new LinearLayout.LayoutParams(1, dp(h)));
  }

  void title(LinearLayout parent, String title, String subtitle) {
    parent.addView(text(title, 28, ink, true));
    if (!subtitle.isEmpty()) {
      gap(parent, 5);
      parent.addView(text(subtitle, 14, secondary, false));
    }
    gap(parent, 22);
  }

  LinearLayout panel(LinearLayout parent) {
    MaterialCardView surface = new MaterialCardView(this);
    surface.setCardBackgroundColor(card);
    surface.setRadius(dp(22));
    surface.setCardElevation(0);
    surface.setStrokeColor(androidx.core.graphics.ColorUtils.setAlphaComponent(secondary, 35));
    surface.setStrokeWidth(dp(1));
    LinearLayout content = vertical();
    content.setPadding(dp(18), dp(16), dp(18), dp(16));
    surface.addView(content, new android.widget.FrameLayout.LayoutParams(-1, -2));
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
    lp.bottomMargin = dp(12);
    parent.addView(surface, lp);
    return content;
  }

  Button button(String label, Runnable action) {
    MaterialButton b =
        new MaterialButton(
            this, null, com.google.android.material.R.attr.materialButtonOutlinedStyle);
    b.setText(label);
    b.setAllCaps(false);
    b.setTextSize(14);
    b.setTextColor(accent);
    b.setStrokeColor(
        android.content.res.ColorStateList.valueOf(
            androidx.core.graphics.ColorUtils.setAlphaComponent(accent, 100)));
    b.setBackgroundTintList(
        android.content.res.ColorStateList.valueOf(
            androidx.core.graphics.ColorUtils.compositeColors(
                androidx.core.graphics.ColorUtils.setAlphaComponent(accent, 15), card)));
    b.setCornerRadius(dp(16));
    b.setMinHeight(dp(48));
    b.setOnClickListener(v -> action.run());
    return b;
  }

  void action(LinearLayout p, String label, Runnable r) {
    p.addView(button(label, r), new LinearLayout.LayoutParams(-1, dp(52)));
    gap(p, 6);
  }

  void render() {
    int previousScroll =
        contentScroll != null && renderedTab == tabIndex ? contentScroll.getScrollY() : 0;
    appearance();
    root = vertical();
    root.setBackgroundColor(bg);
    root.setFitsSystemWindows(true);
    setContentView(root);
    if (Build.VERSION.SDK_INT >= 35) {
      root.setOnApplyWindowInsetsListener(
          (v, insets) -> {
            android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return insets;
          });
    }
    if (FirebaseAuth.getInstance().getCurrentUser() == null) {
      onboarding();
      return;
    }
    String[] destinations = {"Today", "Calendar", "Notebooks", "Dashboard", "Settings"};
    MaterialToolbar toolbar = new MaterialToolbar(this);
    toolbar.setTitle(destinations[Math.max(0, Math.min(4, tabIndex))]);
    toolbar.setTitleTextColor(ink);
    toolbar.setBackgroundColor(bg);
    toolbar
        .getMenu()
        .add(0, 100, 0, "Sync")
        .setIcon(R.drawable.ic_sync)
        .setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS);
    toolbar.getMenu().findItem(100).setEnabled(!store.busy());
    toolbar
        .getMenu()
        .add(0, 101, 1, "Add")
        .setIcon(R.drawable.ic_add)
        .setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS);
    toolbar.setOnMenuItemClickListener(
        item -> {
          if (item.getItemId() == 100) sync(true);
          else if (tabIndex == 2) newBook("");
          else addEvent();
          return true;
        });
    root.addView(toolbar, new LinearLayout.LayoutParams(-1, dp(60)));
    LinearLayout workspace = row();
    workspace.setGravity(Gravity.TOP);
    root.addView(workspace, new LinearLayout.LayoutParams(-1, 0, 1));
    boolean wide = getResources().getConfiguration().screenWidthDp >= 600;
    if (wide) {
      NavigationRailView rail = new NavigationRailView(this);
      configureNavigation(rail, destinations);
      workspace.addView(rail, new LinearLayout.LayoutParams(dp(96), -1));
    }
    ScrollView scroll = new ScrollView(this);
    contentScroll = scroll;
    scroll.setFillViewport(true);
    FrameLayout center = new FrameLayout(this);
    body = vertical();
    body.setPadding(dp(18), dp(12), dp(18), dp(28));
    FrameLayout.LayoutParams centered =
        new FrameLayout.LayoutParams(
            wide ? Math.min(dp(920), getResources().getDisplayMetrics().widthPixels - dp(100)) : -1,
            -2,
            Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    center.addView(body, centered);
    scroll.addView(center);
    workspace.addView(scroll, new LinearLayout.LayoutParams(0, -1, 1));
    try {
      switch (tabIndex) {
        case 0:
          today();
          break;
        case 1:
          calendar();
          break;
        case 2:
          notebooks();
          break;
        case 3:
          dashboard();
          break;
        default:
          settings();
      }
    } catch (Exception e) {
      title(
          body,
          "Your saved data is safe",
          e.getMessage() == null ? "Sync to retrieve your timetable." : e.getMessage());
      action(body, "Sync", () -> sync(true));
    }
    if (!wide) {
      BottomNavigationView nav = new BottomNavigationView(this);
      configureNavigation(nav, destinations);
      root.addView(nav, new LinearLayout.LayoutParams(-1, dp(80)));
    }
    renderedTab = tabIndex;
    scroll.post(() -> scroll.scrollTo(0, previousScroll));
  }

  void configureNavigation(NavigationBarView nav, String[] labels) {
    nav.setBackgroundColor(card);
    nav.setLabelVisibilityMode(NavigationBarView.LABEL_VISIBILITY_LABELED);
    android.content.res.ColorStateList tint =
        new android.content.res.ColorStateList(
            new int[][] {new int[] {android.R.attr.state_checked}, new int[] {}},
            new int[] {accent, secondary});
    nav.setItemIconTintList(tint);
    nav.setItemTextColor(tint);
    nav.setItemActiveIndicatorColor(
        android.content.res.ColorStateList.valueOf(
            androidx.core.graphics.ColorUtils.setAlphaComponent(accent, 35)));
    int[] icons = {
      R.drawable.ic_home,
      R.drawable.ic_calendar,
      R.drawable.ic_book,
      R.drawable.ic_progress,
      R.drawable.ic_settings
    };
    for (int i = 0; i < labels.length; i++)
      nav.getMenu().add(0, i + 1, i, labels[i]).setIcon(icons[i]);
    nav.setSelectedItemId(tabIndex + 1);
    nav.setOnItemSelectedListener(
        item -> {
          int index = item.getItemId() - 1;
          if (index != tabIndex) {
            tabIndex = index;
            if (index == 0) selectedDate = Schedule.today();
            render();
          }
          return true;
        });
  }

  void onboarding() {
    LinearLayout welcome = vertical();
    welcome.setGravity(Gravity.CENTER);
    welcome.setPadding(dp(30), dp(50), dp(30), dp(30));
    root.addView(welcome, new LinearLayout.LayoutParams(-1, -1));
    ImageView logo = new ImageView(this);
    logo.setImageResource(R.mipmap.ic_launcher);
    welcome.addView(logo, new LinearLayout.LayoutParams(dp(92), dp(92)));
    gap(welcome, 24);
    TextView h = text("Your day, organised.", 30, ink, true);
    h.setGravity(Gravity.CENTER);
    welcome.addView(h);
    gap(welcome, 16);
    TextView intro =
        text(
            "Your timetable, attendance and notes.\nOne account across your devices.",
            16,
            secondary,
            false);
    intro.setGravity(Gravity.CENTER);
    welcome.addView(intro);
    gap(welcome, 32);
    Button sign = button(authBusy ? "Signing in…" : "Continue with Google", this::signIn);
    sign.setEnabled(!authBusy);
    welcome.addView(sign, new LinearLayout.LayoutParams(-1, dp(54)));
    gap(welcome, 16);
    TextView hint =
        text(
            "Use your personal Google account, rather than a college or work account. SATHI"
                + " remembers your sign-in on this phone.",
            13,
            secondary,
            false);
    hint.setGravity(Gravity.CENTER);
    welcome.addView(hint);
    gap(welcome, 20);
    TextView state = text(status, 12, secondary, false);
    state.setGravity(Gravity.CENTER);
    welcome.addView(state);
  }

  void signIn() {
    try {
      JSONObject config =
          new JSONObject(
              new String(
                  IO.read(getAssets().open("firebase.json"), 100000),
                  java.nio.charset.StandardCharsets.UTF_8));
      String client = config.getString("webClientId");
      GetGoogleIdOption google =
          new GetGoogleIdOption.Builder()
              .setServerClientId(client)
              .setFilterByAuthorizedAccounts(false)
              .setAutoSelectEnabled(true)
              .build();
      GetCredentialRequest request =
          new GetCredentialRequest.Builder().addCredentialOption(google).build();
      authBusy = true;
      render();
      CredentialManager.create(this)
          .getCredentialAsync(
              this,
              request,
              null,
              getMainExecutor(),
              new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                public void onResult(GetCredentialResponse response) {
                  try {
                    GoogleIdTokenCredential google =
                        GoogleIdTokenCredential.createFrom(response.getCredential().getData());
                    FirebaseAuth.getInstance()
                        .signInWithCredential(
                            GoogleAuthProvider.getCredential(google.getIdToken(), null))
                        .addOnCompleteListener(
                            task -> {
                              authBusy = false;
                              if (task.isSuccessful()) {
                                try {
                                  store.activate();
                                  store.journal("google_sign_in", new JSONObject());
                                  status = "Signed in. Loading your saved timetable…";
                                  render();
                                  startLiveUpdates();
                                  sync(false);
                                } catch (Exception e) {
                                  error(e);
                                }
                              } else {
                                status = "Sign-in failed: " + task.getException().getMessage();
                                render();
                              }
                            });
                  } catch (Exception e) {
                    authBusy = false;
                    error(e);
                    render();
                  }
                }

                public void onError(GetCredentialException e) {
                  authBusy = false;
                  status =
                      e instanceof NoCredentialException
                          ? "No Google account is available. Add your personal Google account in"
                              + " Android Settings, update Google Play services, then try again."
                          : e instanceof GetCredentialCancellationException
                              ? "Sign-in cancelled. Continue whenever you are ready."
                              : "Google sign-in: " + e.getMessage();
                  render();
                }
              });
    } catch (Exception e) {
      authBusy = false;
      error(e);
    }
  }

  private boolean pendingSync = false;

  void sync(boolean explicit) {
    sync(explicit, null);
  }

  void sync(boolean explicit, Boolean preferLocal) {
    flushDraft();
    if (store.busy()) {
      if (preferLocal == null) pendingSync = true;
      return;
    }
    status = "Syncing in the background…";
    if (tabIndex == 4) render();
    store.sync(
        (message, ok) ->
            runOnUiThread(
                () -> {
                  status = message;
                  if (pendingSync) {
                    pendingSync = false;
                    handler.post(() -> sync(false));
                  }
                  if (editor == null) render();
                  if (explicit) {
                    Toast.makeText(this, message, Toast.LENGTH_LONG).show();
                    if (store.hasConflicts() || (!ok && message.contains("Both devices changed"))) {
                      new MaterialAlertDialogBuilder(this)
                          .setTitle("Choose a version for conflicting records")
                          .setMessage(
                              "Both versions will be backed up on this device first. Timetable"
                                  + " conflicts also use that version’s semester, subjects and"
                                  + " study preferences. Other independent edits are kept. If your"
                                  + " Mac has the correct timetable, sync it there first, then"
                                  + " choose cloud here.")
                          .setPositiveButton("Use cloud", (d, w) -> sync(true, false))
                          .setNegativeButton("Use this device", (d, w) -> sync(true, true))
                          .setNeutralButton("Cancel", null)
                          .show();
                    }
                  }
                }),
        preferLocal);
  }

  void dateRow(LinearLayout parent) {
    LinearLayout r = row();
    r.addView(
        button(
            "‹",
            () -> {
              selectedDate = selectedDate.minusDays(1);
              render();
            }),
        new LinearLayout.LayoutParams(dp(48), dp(48)));
    TextView date =
        text(selectedDate.format(DateTimeFormatter.ofPattern("EEE, d MMM yyyy")), 16, ink, true);
    date.setGravity(Gravity.CENTER);
    date.setOnClickListener(v -> pickDate());
    r.addView(date, new LinearLayout.LayoutParams(0, dp(48), 1));
    r.addView(
        button(
            "›",
            () -> {
              selectedDate = selectedDate.plusDays(1);
              render();
            }),
        new LinearLayout.LayoutParams(dp(48), dp(48)));
    parent.addView(r);
    gap(parent, 16);
  }

  void pickDate() {
    datePicker(
        selectedDate.toString(),
        date -> {
          selectedDate = LocalDate.parse(date);
          render();
        });
  }

  void empty() {
    LinearLayout p = panel(body);
    p.addView(text("Your timetable belongs here", 22, ink, true));
    gap(p, 10);
    p.addView(
        text(
            "Use Sync to retrieve your saved schedule from your other devices. For a new account,"
                + " import an Excel timetable.",
            14,
            secondary,
            false));
    gap(p, 16);
    action(p, "Sync saved timetable", () -> sync(true));
    action(p, "Import Excel or SATHI JSON", this::chooseImport);
  }

  private JSONObject reviewDraft;
  private String reviewOriginal;

  void wholeTimetable(boolean review) {
    try {
      if (!store.hasTimetable()) {
        empty();
        return;
      }
      reviewing = review;
      wholeDate = selectedDate;
      reviewDraft = review ? new JSONObject(store.object("timetable").toString()) : null;
      reviewOriginal = Snapshot.value(store.object("timetable"));
      reviewSelection = new HashSet<>();
      for (JSONObject r : Schedule.classes(store.copy())) reviewSelection.add(r.getString("id"));
      Dialog dialog = new Dialog(this, R.style.SathiTheme);
      LinearLayout layout = vertical();
      layout.setBackgroundColor(bg);
      layout.setPadding(dp(16), dp(12), dp(16), dp(12));
      LinearLayout bar = row();
      bar.addView(button("Back", dialog::dismiss));
      bar.addView(
          text(review ? "Check timetable" : "Whole timetable", 20, ink, true),
          new LinearLayout.LayoutParams(0, -2, 1));
      layout.addView(bar);
      ScrollView scroll = new ScrollView(this);
      LinearLayout content = vertical();
      scroll.addView(content);
      layout.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
      if (review)
        layout.addView(
            button(
                "Save checked classes",
                () -> {
                  try {
                    if (!Snapshot.equivalent(
                        reviewOriginal, Snapshot.value(store.object("timetable"))))
                      throw new Exception(
                          "The timetable changed on another device. Your review is still open; copy"
                              + " your edits before reopening it.");
                    reviewDraft.put(
                        "subjects", ParityRules.subjects(reviewDraft.getJSONArray("sessions")));
                    JSONArray ids = new JSONArray();
                    for (String id : reviewSelection) ids.put(id);
                    store.replaceReviewedReport(reviewDraft, ids);
                    dialog.dismiss();
                    afterEdit();
                  } catch (Exception e) {
                    error(e);
                  }
                }));
      Runnable[] draw = new Runnable[1];
      draw[0] =
          () -> {
            try {
              drawWholeWeek(content, dialog, review, draw[0]);
            } catch (Exception e) {
              error(e);
            }
          };
      draw[0].run();
      dialog.setContentView(layout);
      dialog.setOnDismissListener(
          d -> {
            reviewing = false;
            reviewDraft = null;
          });
      dialog.show();
      dialog.getWindow().setLayout(-1, -1);
    } catch (Exception e) {
      error(e);
    }
  }

  void drawWholeWeek(LinearLayout target, Dialog dialog, boolean review, Runnable redraw)
      throws Exception {
    target.removeAllViews();
    JSONObject report = review ? reviewDraft : store.object("timetable");
    JSONArray source = report.getJSONArray("sessions");
    List<JSONObject> rows = new ArrayList<>();
    TreeSet<String> dates = new TreeSet<>();
    for (int i = 0; i < source.length(); i++) {
      JSONObject r = source.getJSONObject(i);
      if (!wholeProgramme.equals("All")
          && !Schedule.programme(r.optString("source")).equals(wholeProgramme)) continue;
      if (!wholeSection.equals("All")
          && !r.optString("section").isEmpty()
          && !r.optString("section").equals(wholeSection)) continue;
      rows.add(r);
      dates.add(r.getString("date"));
    }
    LinearLayout filters = row();
    filters.addView(
        button(
            "Course: " + wholeProgramme,
            () ->
                new MaterialAlertDialogBuilder(this)
                    .setTitle("Course")
                    .setItems(
                        new String[] {"All", "MBA", "DBM", "DBAI", "HHM"},
                        (d, i) -> {
                          wholeProgramme = new String[] {"All", "MBA", "DBM", "DBAI", "HHM"}[i];
                          redraw.run();
                        })
                    .show()),
        new LinearLayout.LayoutParams(0, -2, 1));
    filters.addView(
        button(
            "Section: " + wholeSection,
            () ->
                new MaterialAlertDialogBuilder(this)
                    .setTitle("Section")
                    .setItems(
                        new String[] {"All", "A", "B", "C", "D"},
                        (d, i) -> {
                          wholeSection = new String[] {"All", "A", "B", "C", "D"}[i];
                          redraw.run();
                        })
                    .show()),
        new LinearLayout.LayoutParams(0, -2, 1));
    target.addView(filters);
    if (rows.isEmpty()) {
      target.addView(text("No matching schedule is saved.", 18, ink, true));
      if (!wholeProgramme.equals("All"))
        target.addView(
            button(
                "Upload " + wholeProgramme + " schedule",
                () -> {
                  pendingProgramme = wholeProgramme;
                  dialog.dismiss();
                  openWorkbookPicker();
                }));
      return;
    }
    LocalDate first = LocalDate.parse(dates.first()), last = LocalDate.parse(dates.last());
    if (wholeDate.isBefore(first)) wholeDate = first;
    if (wholeDate.isAfter(last))
      wholeDate = last.minusDays(6).isBefore(first) ? first : last.minusDays(6);
    LinearLayout navigation = row();
    Button prev =
        button(
            "‹",
            () -> {
              wholeDate = wholeDate.minusDays(7);
              redraw.run();
            });
    prev.setEnabled(wholeDate.isAfter(first));
    navigation.addView(prev);
    Button jump =
        button(
            wholeDate.format(DateTimeFormatter.ofPattern("d MMM"))
                + " – "
                + wholeDate.plusDays(6).format(DateTimeFormatter.ofPattern("d MMM")),
            () ->
                datePicker(
                    wholeDate.toString(),
                    value -> {
                      wholeDate = LocalDate.parse(value);
                      redraw.run();
                    }));
    navigation.addView(jump, new LinearLayout.LayoutParams(0, -2, 1));
    Button next =
        button(
            "›",
            () -> {
              wholeDate = wholeDate.plusDays(7);
              redraw.run();
            });
    next.setEnabled(wholeDate.plusDays(6).isBefore(last));
    navigation.addView(next);
    target.addView(navigation);
    target.addView(
        text(
            review
                ? "Tap each class you attend. Hold a class to correct its name, section, teacher or"
                      + " time."
                : "All uploaded subjects, seven days at a time. Overlapping classes remain"
                      + " visible.",
            13,
            secondary,
            false));
    if (review) target.addView(button("Check / edit time slots", () -> editSlots(redraw)));
    rows.sort(
        Comparator.comparingLong((JSONObject r) -> Schedule.instant(r, false))
            .thenComparing(r -> r.optString("subject")));
    for (int offset = 0; offset < 7; offset++) {
      LocalDate day = wholeDate.plusDays(offset);
      gap(target, 16);
      target.addView(text(day.format(DateTimeFormatter.ofPattern("EEEE, d MMM")), 18, ink, true));
      int count = 0;
      for (JSONObject row : rows)
        if (row.optString("date").equals(day.toString())) {
          count++;
          String label =
              row.optString("time")
                  + " · "
                  + row.optString("subject")
                  + (row.optString("section").isEmpty() ? "" : " · " + row.optString("section"));
          if (review) {
            com.google.android.material.checkbox.MaterialCheckBox check =
                new com.google.android.material.checkbox.MaterialCheckBox(this);
            check.setText(label + "\n" + row.optString("teacher"));
            check.setTextColor(ink);
            check.setChecked(reviewSelection.contains(row.getString("id")));
            check.setOnCheckedChangeListener(
                (v, checked) -> {
                  if (checked) reviewSelection.add(row.optString("id"));
                  else reviewSelection.remove(row.optString("id"));
                });
            check.setOnLongClickListener(
                v -> {
                  editReviewedRow(row, redraw);
                  return true;
                });
            target.addView(check);
          } else {
            LinearLayout card = panel(target);
            card.addView(text(row.optString("time"), 13, accent, true));
            card.addView(text(row.optString("subject"), 16, ink, true));
            card.addView(
                text(
                    row.optString("teacher")
                        + (row.optString("section").isEmpty()
                            ? ""
                            : " · Section " + row.optString("section")),
                    12,
                    secondary,
                    false));
          }
        }
      if (count == 0) target.addView(text("No classes", 13, secondary, false));
    }
  }

  void editReviewedRow(JSONObject row, Runnable redraw) {
    LinearLayout form = vertical();
    form.setPadding(dp(18), 0, dp(18), 0);
    EditText name = field(form, "Subject", row.optString("subject")),
        section = field(form, "Section (leave blank for common)", row.optString("section")),
        teacher = field(form, "Teacher", row.optString("teacher")),
        day = dateField(form, "Date", row.optString("date")),
        start = timeField(form, "Start", Schedule.start(row).toString()),
        end = timeField(form, "End", Schedule.end(row).toString());
    editorDialog(
        "Correct class",
        form,
        () -> {
          try {
            validateWindow(day, start, end);
            if (name.getText().toString().trim().isEmpty())
              throw new Exception("Enter a subject name");
            row.put("subject", name.getText().toString().trim())
                .put("section", section.getText().toString().trim().toUpperCase(Locale.ROOT))
                .put("teacher", teacher.getText().toString().trim())
                .put("date", day.getText().toString())
                .put("time", start.getText() + " – " + end.getText());
            redraw.run();
            return true;
          } catch (Exception e) {
            error(e);
            return false;
          }
        });
  }

  void editSlots(Runnable redraw) {
    try {
      TreeSet<String> slots = new TreeSet<>();
      JSONArray rows = reviewDraft.getJSONArray("sessions");
      for (int i = 0; i < rows.length(); i++) slots.add(rows.getJSONObject(i).getString("time"));
      String[] values = slots.toArray(new String[0]);
      new MaterialAlertDialogBuilder(this)
          .setTitle("Choose a time slot to correct")
          .setItems(
              values,
              (d, i) -> {
                try {
                  JSONObject sample = new JSONObject().put("time", values[i]);
                  LinearLayout form = vertical();
                  form.setPadding(dp(18), 0, dp(18), 0);
                  EditText start = timeField(form, "Starts", Schedule.start(sample).toString()),
                      end = timeField(form, "Ends", Schedule.end(sample).toString());
                  editorDialog(
                      "Edit slot for every day",
                      form,
                      () -> {
                        try {
                          if (!LocalTime.parse(end.getText())
                              .isAfter(LocalTime.parse(start.getText())))
                            throw new Exception("End time must follow start");
                          for (int r = 0; r < rows.length(); r++)
                            if (rows.getJSONObject(r).optString("time").equals(values[i]))
                              rows.getJSONObject(r)
                                  .put("time", start.getText() + " – " + end.getText());
                          redraw.run();
                          return true;
                        } catch (Exception e) {
                          error(e);
                          return false;
                        }
                      });
                } catch (Exception e) {
                  error(e);
                }
              })
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  void reminderTiming() {
    LinearLayout form = vertical();
    form.setPadding(dp(18), 0, dp(18), 0);
    JSONObject prefs = store.object("study:preferences");
    EditText
        lead =
            field(
                form,
                "Minutes before class",
                String.valueOf(prefs.optInt("fingerprintLeadMinutes", 15))),
        sheet =
            field(
                form,
                "Minutes after start for sheet",
                String.valueOf(prefs.optInt("sheetReminderMinutes", 40)));
    lead.setInputType(2);
    sheet.setInputType(2);
    editorDialog(
        "Reminder timing",
        form,
        () -> {
          try {
            int a = Integer.parseInt(lead.getText().toString()),
                b = Integer.parseInt(sheet.getText().toString());
            if (a < 1 || a > 120 || b < 1 || b > 180)
              throw new Exception("Use 1–120 before and 1–180 after start");
            JSONObject p = store.object("study:preferences");
            p.put("fingerprintLeadMinutes", a).put("sheetReminderMinutes", b);
            store.put("study:preferences", p);
            afterEdit();
            return true;
          } catch (Exception e) {
            error(e);
            return false;
          }
        });
  }

  void soundChoice() {
    new MaterialAlertDialogBuilder(this)
        .setTitle("Notification sound")
        .setItems(
            new String[] {"System default", "SATHI chime", "Silent"},
            (d, i) -> {
              try {
                JSONObject p = store.object("study:preferences");
                p.put("sounds", i != 2).put("notificationSound", i == 1 ? "sathi" : "default");
                store.put("study:preferences", p);
                afterEdit();
              } catch (Exception e) {
                error(e);
              }
            })
        .show();
  }

  void themeChoices() {
    new MaterialAlertDialogBuilder(this)
        .setTitle("Choose a theme")
        .setItems(
            new String[] {"Campus blue", "Midnight indigo", "Forest", "Soft rose", "Sunset"},
            (d, i) -> {
              try {
                JSONObject p = store.object("study:preferences");
                p.put("accent", new String[] {"blue", "indigo", "green", "pink", "orange"}[i])
                    .put("appearanceMode", i == 1 ? "dark" : "system");
                store.put("study:preferences", p);
                getSharedPreferences("appearance", 0)
                    .edit()
                    .putBoolean("systemAccent", false)
                    .putString("mode", i == 1 ? "dark" : "system")
                    .apply();
                recreate();
              } catch (Exception e) {
                error(e);
              }
            })
        .show();
  }

  void campusDocument(String kind) {
    try {
      File file = null;
      for (String extension : new String[] {"pdf", "png", "jpg"}) {
        File candidate = store.campusFile(kind + "." + extension);
        if (candidate.exists()) {
          file = candidate;
          break;
        }
      }
      final File saved = file;
      if (saved == null) {
        pickCampusDocument(kind);
        return;
      }
      new MaterialAlertDialogBuilder(this)
          .setTitle(kind.equals("menu") ? "Mess menu" : "Laundry schedule")
          .setItems(
              new String[] {"Open saved document", "Replace document"},
              (d, i) -> {
                if (i == 1) pickCampusDocument(kind);
                else
                  try {
                    File cache = new File(getCacheDir(), "exports");
                    cache.mkdirs();
                    File copy = new File(cache, saved.getName());
                    try (InputStream in = new FileInputStream(saved);
                        OutputStream out = new FileOutputStream(copy)) {
                      byte[] bytes = new byte[8192];
                      int n;
                      while ((n = in.read(bytes)) != -1) out.write(bytes, 0, n);
                    }
                    Uri uri =
                        androidx.core.content.FileProvider.getUriForFile(
                            this, getPackageName() + ".files", copy);
                    startActivity(
                        new Intent(Intent.ACTION_VIEW)
                            .setDataAndType(
                                uri,
                                saved.getName().endsWith("pdf") ? "application/pdf" : "image/*")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION));
                  } catch (Exception e) {
                    error(e);
                  }
              })
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  void pickCampusDocument(String kind) {
    documentResult =
        uri -> {
          store.io.execute(
              () -> {
                try (InputStream in = getContentResolver().openInputStream(uri)) {
                  String type = getContentResolver().getType(uri);
                  String extension = type != null && type.contains("pdf") ? "pdf" : "png";
                  byte[] data = readLimited(in, 20000000);
                  File destination = store.campusFile(kind + "." + extension);
                  Store.atomic(destination, data);
                  for (String e : new String[] {"pdf", "png", "jpg"})
                    if (!e.equals(extension)) store.campusFile(kind + "." + e).delete();
                  runOnUiThread(
                      () ->
                          Toast.makeText(this, "Saved on this device", Toast.LENGTH_SHORT).show());
                } catch (Exception e) {
                  runOnUiThread(() -> error(e));
                }
              });
        };
    startActivityForResult(
        new Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(Intent.EXTRA_MIME_TYPES, new String[] {"application/pdf", "image/*"}),
        41);
  }

  void openWorkbookPicker() {
    Intent intent =
        new Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(
                Intent.EXTRA_MIME_TYPES,
                new String[] {
                  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                  "application/json"
                });
    startActivityForResult(intent, 31);
  }

  void today() throws Exception {
    title(body, "Today", "Your classes and campus activities.");
    if (!store.hasTimetable()) {
      empty();
      return;
    }
    dateRow(body);
    if (store.object("study:preferences").optBoolean("campusShortcuts")) {
      LinearLayout shortcuts = row();
      shortcuts.addView(
          button("Mess menu", () -> campusDocument("menu")),
          new LinearLayout.LayoutParams(0, -2, 1));
      shortcuts.addView(
          button("Laundry", () -> campusDocument("laundry")),
          new LinearLayout.LayoutParams(0, -2, 1));
      body.addView(shortcuts);
    }
    if (termEnded())
      action(
          body,
          "Import next semester",
          () -> {
            nextSemesterImport = true;
            chooseImport();
          });
    scheduleRows(selectedDate);
  }

  void calendar() throws Exception {
    title(body, "Calendar", "Your selected classes and activities.");
    LinearLayout actions = row();
    actions.addView(
        button("Whole timetable", () -> wholeTimetable(false)),
        new LinearLayout.LayoutParams(0, -2, 1));
    actions.addView(button("History", this::semesterHistory));
    body.addView(actions);
    LinearLayout week = row();
    LocalDate first = selectedDate.minusDays(selectedDate.getDayOfWeek().getValue() - 1);
    for (int i = 0; i < 7; i++) {
      LocalDate day = first.plusDays(i);
      Button b =
          button(
              day.format(DateTimeFormatter.ofPattern("EE")) + "\n" + day.getDayOfMonth(),
              () -> {
                selectedDate = day;
                render();
              });
      b.setTextSize(11);
      b.setPadding(0, 0, 0, 0);
      if (day.equals(selectedDate))
        b.setBackgroundTintList(
            android.content.res.ColorStateList.valueOf(
                androidx.core.graphics.ColorUtils.setAlphaComponent(accent, 45)));
      week.addView(b, new LinearLayout.LayoutParams(0, dp(64), 1));
    }
    body.addView(week);
    dateRow(body);
    action(body, "Choose another date", this::pickDate);
    scheduleRows(selectedDate);
  }

  void scheduleRows(LocalDate date) throws Exception {
    Map<String, String> records = store.copy();
    List<JSONObject> selected = Schedule.classes(records);
    Set<String> penalties = Schedule.penalties(selected, records);
    Map<String, Integer> ordinals = ParityRules.ordinals(records);
    List<JSONObject> timeline = new ArrayList<>();
    int classes = 0;
    for (JSONObject row : selected)
      if (date.toString().equals(row.optString("date"))) {
        timeline.add(new JSONObject(row.toString()).put("_class", true));
        classes++;
      }
    List<JSONObject> events = Schedule.events(records, date.toString());
    for (JSONObject e : events) timeline.add(new JSONObject(e.toString()).put("_class", false));
    timeline.sort(
        Comparator.comparingLong((JSONObject row) -> Schedule.instant(row, false))
            .thenComparing(row -> row.optString("subject", row.optString("title"))));
    body.addView(
        text(classes + " classes · " + events.size() + " activities", 13, secondary, false));
    gap(body, 12);
    for (JSONObject row : timeline) {
      LinearLayout panel = panel(body);
      boolean lecture = row.optBoolean("_class");
      if (lecture) {
        String state = Schedule.status(row, records, penalties);
        panel.addView(
            text(
                "Lecture "
                    + ordinals.getOrDefault(row.optString("id"), 1)
                    + " · "
                    + row.optString("time"),
                13,
                accent,
                true));
        gap(panel, 6);
        panel.addView(text(row.optString("subject"), 19, ink, true));
        panel.addView(
            text(
                row.optString("teacher")
                    + (row.optString("section").isEmpty()
                        ? ""
                        : " · Section " + row.optString("section")),
                12,
                secondary,
                false));
        panel.addView(text(state, 12, state.equals("Missed") ? 0xFFCC554F : accent, true));
        long start = Schedule.instant(row, false),
            end = Schedule.instant(row, true),
            now = System.currentTimeMillis();
        if (store.object("study:preferences").optBoolean("classCountdown", true)
            && end > now
            && start - now <= 3600000) {
          TextView timer = text("", 13, accent, true);
          panel.addView(timer);
          timer.post(
              new Runnable() {
                public void run() {
                  if (!timer.isAttachedToWindow()) return;
                  long current = System.currentTimeMillis();
                  long target =
                      start
                          - store.object("study:preferences").optInt("fingerprintTargetMinutes", 1)
                              * 60000L;
                  timer.setText(
                      current < start
                          ? Math.max(0, (target - current + 59999) / 60000)
                              + " min until fingerprint target"
                          : Math.max(0, (end - current + 59999) / 60000) + " min left in class");
                  if (current < end) timer.postDelayed(this, 1000);
                }
              });
        }
        LinearLayout controls = row();
        if (store.object("study:preferences").optBoolean("proofCrosscheck", false)) {
          JSONObject proof = store.object("study:proof:" + row.optString("id"));
          controls.addView(
              button(
                  (proof.optBoolean("fingerprint") ? "✓ " : "") + "Fingerprint",
                  () -> quickProof(row, "fingerprint")),
              new LinearLayout.LayoutParams(0, -2, 1));
          controls.addView(
              button(
                  (proof.optBoolean("signedSheet") ? "✓ " : "") + "Signed",
                  () -> quickProof(row, "signedSheet")),
              new LinearLayout.LayoutParams(0, -2, 1));
        }
        controls.addView(button("Mark / edit", () -> classActions(row)));
        panel.addView(controls);
        panel.setOnClickListener(v -> attendance(row));
      } else {
        panel.addView(text(row.optString("time"), 13, accent, true));
        gap(panel, 5);
        panel.addView(text(row.optString("title"), 19, ink, true));
        if (!row.optString("notes").isEmpty())
          panel.addView(text(row.optString("notes"), 13, secondary, false));
        panel.addView(button("Attendance / edit", () -> eventActions(row)));
      }
    }
    if (timeline.isEmpty()) {
      LinearLayout clear = panel(body);
      clear.addView(text("A clear day", 22, ink, true));
      clear.addView(text("No classes or activities scheduled.", 14, secondary, false));
    }
    action(body, "Add activity", this::addEvent);
  }

  void quickProof(JSONObject row, String field) {
    try {
      String key = "study:proof:" + row.getString("id");
      JSONObject proof = store.object(key);
      proof.put(field, !proof.optBoolean(field));
      if (proof.optBoolean("fingerprint")
          && proof.optBoolean("signedSheet")
          && (!proof.has("attended") || proof.optBoolean("attended"))) proof.put("attended", true);
      proof.put("updatedAt", Snapshot.swiftNow());
      store.put(key, proof);
      afterEdit();
    } catch (Exception e) {
      error(e);
    }
  }

  void mark(JSONObject row, String state) {
    try {
      String id = row.getString("id");
      JSONObject proof = store.object("study:proof:" + id);
      proof.put("officialDuty", state.equals("OD")).put("updatedAt", Snapshot.swiftNow());
      if (!state.equals("OD")) proof.put("attended", state.equals("Attended"));
      store.put("attendance:" + id, state);
      store.put("study:proof:" + id, proof);
      afterEdit();
    } catch (Exception e) {
      error(e);
    }
  }

  void afterEdit() {
    ScheduleWidget.refresh(this);
    render();
    sync(false);
  }

  void classActions(JSONObject row) {
    new MaterialAlertDialogBuilder(this)
        .setTitle(row.optString("subject"))
        .setItems(
            new String[] {
              "Attendance details",
              "Present",
              "Missed",
              "Official duty (OD)",
              "Reschedule / postpone / prepone",
              "Clear attendance"
            },
            (d, i) -> {
              try {
                if (i == 0) attendance(row);
                else if (i < 4) mark(row, new String[] {"", "Attended", "Missed", "OD"}[i]);
                else if (i == 4) reschedule(row);
                else {
                  store.remove("attendance:" + row.getString("id"));
                  store.remove("study:proof:" + row.getString("id"));
                  afterEdit();
                }
              } catch (Exception e) {
                error(e);
              }
            })
        .show();
  }

  void reschedule(JSONObject row) {
    LinearLayout form = vertical();
    form.setPadding(dp(18), 0, dp(18), 0);
    EditText title = field(form, "Title", row.optString("subject", row.optString("title")));
    EditText day = dateField(form, "Date", row.optString("date"));
    EditText start = timeField(form, "Start", Schedule.start(row).toString()),
        end =
            timeField(
                form,
                "End",
                Schedule.end(row).isAfter(Schedule.start(row))
                    ? Schedule.end(row).toString()
                    : Schedule.start(row).plusMinutes(90).toString());
    editorDialog(
        "Reschedule",
        form,
        () -> {
          try {
            validateWindow(day, start, end);
            String id = row.getString("id");
            store.put(
                "study:override:" + id,
                new JSONObject()
                    .put("id", id)
                    .put("date", day.getText().toString())
                    .put("start", start.getText().toString())
                    .put("end", end.getText().toString())
                    .put("title", title.getText().toString())
                    .put("cancelled", false)
                    .put("added", false)
                    .put("semesterID", store.object("study:semesters").optString("current")));
            afterEdit();
            return true;
          } catch (Exception e) {
            error(e);
            return false;
          }
        });
  }

  interface SaveForm {
    boolean save();
  }

  void editorDialog(String title, LinearLayout form, SaveForm save) {
    ScrollView scroll = new ScrollView(this);
    scroll.addView(form);
    AlertDialog dialog =
        new MaterialAlertDialogBuilder(this)
            .setTitle(title)
            .setView(scroll)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Save", null)
            .create();
    dialog.setOnShowListener(
        d ->
            dialog
                .getButton(-1)
                .setOnClickListener(
                    v -> {
                      if (save.save()) dialog.dismiss();
                    }));
    dialog.show();
  }

  EditText dateField(LinearLayout form, String label, String value) {
    EditText input = field(form, label, value);
    input.setFocusable(false);
    input.setOnClickListener(v -> datePicker(input.getText().toString(), input::setText));
    return input;
  }

  EditText timeField(LinearLayout form, String label, String value) {
    EditText input = field(form, label, value);
    input.setFocusable(false);
    input.setOnClickListener(
        v -> {
          LocalTime clock;
          try {
            clock = LocalTime.parse(input.getText());
          } catch (Exception e) {
            clock = LocalTime.of(9, 0);
          }
          MaterialTimePicker picker =
              new MaterialTimePicker.Builder()
                  .setHour(clock.getHour())
                  .setMinute(clock.getMinute())
                  .setTimeFormat(
                      android.text.format.DateFormat.is24HourFormat(this)
                          ? TimeFormat.CLOCK_24H
                          : TimeFormat.CLOCK_12H)
                  .setTitleText(label)
                  .build();
          picker.addOnPositiveButtonClickListener(
              w ->
                  input.setText(
                      String.format(
                          Locale.ROOT, "%02d:%02d", picker.getHour(), picker.getMinute())));
          picker.show(getSupportFragmentManager(), "time");
        });
    return input;
  }

  void validateWindow(EditText date, EditText start, EditText end) throws Exception {
    LocalDate.parse(date.getText());
    if (!LocalTime.parse(end.getText()).isAfter(LocalTime.parse(start.getText())))
      throw new Exception("End time must follow start time");
  }

  void datePicker(String initial, java.util.function.Consumer<String> chosen) {
    LocalDate day;
    try {
      day = LocalDate.parse(initial);
    } catch (Exception e) {
      day = Schedule.today();
    }
    MaterialDatePicker<Long> picker =
        MaterialDatePicker.Builder.datePicker()
            .setSelection(day.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
            .setTitleText("Choose date")
            .build();
    picker.addOnPositiveButtonClickListener(
        value ->
            chosen.accept(
                Instant.ofEpochMilli(value).atZone(ZoneOffset.UTC).toLocalDate().toString()));
    picker.show(getSupportFragmentManager(), "date");
  }

  boolean termEnded() {
    try {
      JSONArray rows = store.object("timetable").getJSONArray("sessions");
      String end = "";
      for (int i = 0; i < rows.length(); i++)
        if (end.compareTo(rows.getJSONObject(i).optString("date")) < 0)
          end = rows.getJSONObject(i).getString("date");
      JSONArray events = store.object("timetable").optJSONArray("events");
      if (events != null)
        for (int i = 0; i < events.length(); i++) {
          String date = events.getJSONObject(i).optString("date");
          if (end.compareTo(date) < 0) end = date;
        }
      return !end.isEmpty() && end.compareTo(Schedule.today().toString()) < 0;
    } catch (Exception e) {
      return false;
    }
  }

  void attendance(JSONObject session) {
    try {
      String key = "study:proof:" + session.getString("id");
      JSONObject proof = store.object(key);
      LinearLayout form = vertical();
      form.setPadding(dp(22), dp(10), dp(22), dp(10));
      String[] names = {
        "Attended class",
        "Fingerprint recorded",
        "Attendance sheet signed",
        "Official duty (counts as present)"
      };
      String[] keys = {"attended", "fingerprint", "signedSheet", "officialDuty"};
      Spinner[] choices = new Spinner[4];
      int[] initial = new int[4];
      for (int i = 0; i < 4; i++) {
        form.addView(text(names[i], 14, ink, true));
        Spinner choice = new Spinner(this);
        String[] values =
            i == 3 ? new String[] {"No", "Yes"} : new String[] {"Not recorded", "Yes", "No"};
        ArrayAdapter<String> adapter =
            new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, values);
        choice.setAdapter(adapter);
        choice.setSelection(
            i == 3
                ? (proof.optBoolean(keys[i]) ? 1 : 0)
                : proof.has(keys[i]) ? (proof.optBoolean(keys[i]) ? 1 : 2) : 0);
        form.addView(choice, new LinearLayout.LayoutParams(-1, dp(48)));
        choices[i] = choice;
        initial[i] = choice.getSelectedItemPosition();
      }
      form.addView(
          text(
              "Only record what happened. A mismatch between fingerprint and sheet marks this class"
                  + " and the next three classes as missed under your attendance rule. Unmarked"
                  + " classes are not assumed present.",
              12,
              secondary,
              false));
      new MaterialAlertDialogBuilder(this)
          .setTitle(session.optString("subject"))
          .setView(form)
          .setNegativeButton("Cancel", null)
          .setPositiveButton(
              "Save",
              (d, w) -> {
                try {
                  JSONObject fresh = store.object(key);
                  for (int i = 0; i < 4; i++) {
                    int value = choices[i].getSelectedItemPosition();
                    if (value == initial[i]) continue;
                    if (i == 3) fresh.put(keys[i], value == 1);
                    else if (value == 0) fresh.remove(keys[i]);
                    else fresh.put(keys[i], value == 1);
                  }
                  if (fresh.optBoolean("fingerprint")
                      && fresh.optBoolean("signedSheet")
                      && !fresh.has("attended")
                      && choices[0].getSelectedItemPosition() == initial[0])
                    fresh.put("attended", true);
                  fresh.put("updatedAt", Snapshot.swiftNow());
                  store.put(key, fresh);
                  status = "Attendance saved; syncing confirmations…";
                  sync(false);
                  ScheduleWidget.refresh(this);
                  render();
                } catch (Exception e) {
                  error(e);
                }
              })
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  EditText field(LinearLayout form, String hint, String initial) {
    TextInputLayout box = new TextInputLayout(this);
    box.setHint(hint);
    box.setBoxBackgroundMode(TextInputLayout.BOX_BACKGROUND_OUTLINE);
    box.setBoxCornerRadii(dp(12), dp(12), dp(12), dp(12));
    TextInputEditText input = new TextInputEditText(box.getContext());
    input.setText(initial);
    input.setTextColor(ink);
    input.setTextSize(16);
    input.setSingleLine(true);
    box.addView(input, new LinearLayout.LayoutParams(-1, -2));
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
    lp.topMargin = dp(8);
    lp.bottomMargin = dp(8);
    form.addView(box, lp);
    return input;
  }

  void addEvent() {
    editEvent(null);
  }

  void editEvent(JSONObject original) {
    try {
      JSONObject value = original == null ? new JSONObject() : new JSONObject(original.toString());
      LinearLayout form = vertical();
      form.setPadding(dp(18), 0, dp(18), 0);
      EditText name = field(form, "Activity title", value.optString("title"));
      Spinner type = new Spinner(this);
      String[] types = {
        "Quiz", "Guest lecture", "Presentation", "Placement", "Workshop", "Meeting", "Other"
      };
      type.setAdapter(
          new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, types));
      type.setSelection(Math.max(0, Arrays.asList(types).indexOf(value.optString("type"))));
      form.addView(type);
      List<String> subjects = new ArrayList<>();
      subjects.add("No subject / general activity");
      for (JSONObject r : Schedule.classes(store.copy()))
        if (!subjects.contains(r.optString("subject"))) subjects.add(r.optString("subject"));
      Spinner subject = new Spinner(this);
      subject.setAdapter(
          new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, subjects));
      subject.setSelection(Math.max(0, subjects.indexOf(value.optString("subject"))));
      form.addView(subject);
      EditText day = dateField(form, "Date", value.optString("date", selectedDate.toString())),
          start = timeField(form, "Start", value.optString("start", "09:00")),
          end = timeField(form, "End", value.optString("end", "10:00")),
          notes = field(form, "Notes", value.optString("notes"));
      notes.setSingleLine(false);
      notes.setMinLines(2);
      editorDialog(
          original == null ? "New activity" : "Edit / reschedule activity",
          form,
          () -> {
            try {
              validateWindow(day, start, end);
              if (name.getText().toString().trim().isEmpty())
                throw new Exception("Enter an activity title");
              String id =
                  value.optString("id", UUID.randomUUID().toString().toUpperCase(Locale.ROOT));
              value
                  .put("id", id)
                  .put("title", name.getText().toString().trim())
                  .put("type", types[type.getSelectedItemPosition()])
                  .put(
                      "subject",
                      subject.getSelectedItemPosition() == 0
                          ? ""
                          : subjects.get(subject.getSelectedItemPosition()))
                  .put("date", day.getText().toString())
                  .put("start", start.getText().toString())
                  .put("end", end.getText().toString())
                  .put("notes", notes.getText().toString());
              store.put("event:" + id, value);
              afterEdit();
              return true;
            } catch (Exception e) {
              error(e);
              return false;
            }
          });
    } catch (Exception e) {
      error(e);
    }
  }

  void eventActions(JSONObject event) {
    boolean custom = !event.optString("id").startsWith("excel-");
    new MaterialAlertDialogBuilder(this)
        .setTitle(event.optString("title"))
        .setItems(
            new String[] {
              "Record attendance / OD",
              "Edit or reschedule",
              custom ? "Delete activity" : "Hide this event"
            },
            (d, i) -> {
              try {
                if (i == 0) {
                  JSONObject row =
                      new JSONObject(event.toString())
                          .put("subject", event.optString("title"))
                          .put(
                              "id",
                              custom ? "custom-" + event.getString("id") : event.getString("id"));
                  attendance(row);
                } else if (i == 1) {
                  if (custom) editEvent(store.object("event:" + event.getString("id")));
                  else reschedule(event);
                } else
                  new MaterialAlertDialogBuilder(this)
                      .setTitle("Remove this activity?")
                      .setNegativeButton("Cancel", null)
                      .setPositiveButton(
                          "Remove",
                          (x, w) -> {
                            try {
                              if (custom) store.remove("event:" + event.getString("id"));
                              else {
                                String id = event.getString("id");
                                store.put(
                                    "study:override:" + id,
                                    new JSONObject()
                                        .put("id", id)
                                        .put("date", event.getString("date"))
                                        .put("start", "00:00")
                                        .put("end", "00:01")
                                        .put("title", event.optString("title"))
                                        .put("cancelled", true)
                                        .put("added", false)
                                        .put(
                                            "semesterID",
                                            store.object("study:semesters").optString("current")));
                              }
                              afterEdit();
                            } catch (Exception e) {
                              error(e);
                            }
                          })
                      .show();
              } catch (Exception e) {
                error(e);
              }
            })
        .show();
  }

  void dashboard() throws Exception {
    title(body, "Your progress", "An honest view of the semester.");
    if (!store.hasTimetable()) {
      empty();
      return;
    }
    Map<String, String> records = store.copy();
    List<JSONObject> classes = Schedule.classes(records);
    Set<String> penalties = Schedule.penalties(classes, records);
    int present = 0, missed = 0, unmarked = 0, past = 0;
    Map<String, int[]> subjects = new TreeMap<>();
    for (JSONObject s : classes) {
      int[] counts = subjects.computeIfAbsent(s.optString("subject"), k -> new int[4]);
      counts[3]++;
      if (Schedule.instant(s, true) > System.currentTimeMillis()) continue;
      past++;
      String state = Schedule.status(s, records, penalties);
      if (state.equals("Attended") || state.equals("OD")) {
        present++;
        counts[0]++;
      } else if (state.equals("Missed")) {
        missed++;
        counts[1]++;
      } else {
        unmarked++;
        counts[2]++;
      }
    }
    LinearLayout hero = panel(body);
    hero.addView(
        text(
            present + missed == 0 ? "—" : Math.round(present * 100f / (present + missed)) + "%",
            48,
            accent,
            true));
    hero.addView(text("Recorded attendance", 16, ink, true));
    gap(hero, 10);
    hero.addView(
        text(
            present + " present · " + missed + " missed · " + unmarked + " unmarked",
            13,
            secondary,
            false));
    gap(hero, 8);
    hero.addView(text("Unmarked classes do not count as present or missed.", 12, secondary, false));
    LinearLayout overview = panel(body);
    overview.addView(text(past + " / " + classes.size() + " classes completed", 18, ink, true));
    gap(overview, 7);
    overview.addView(
        text(
            subjects.size()
                + " subjects · Semester "
                + store.object("selection").optInt("semester", 1),
            14,
            secondary,
            false));
    gap(body, 12);
    body.addView(text("Subjects", 21, ink, true));
    gap(body, 12);
    int target = store.object("selection").optInt("minimumAttendance", 80);
    for (String name : subjects.keySet()) {
      int[] c = subjects.get(name);
      LinearLayout p = panel(body);
      p.addView(text(name, 17, ink, true));
      lectureTiles(p, name, classes, records, penalties);
      gap(p, 9);
      p.addView(
          text(
              c[0] + c[1] == 0
                  ? "No confirmed attendance"
                  : Math.round(c[0] * 100f / (c[0] + c[1])) + "% recorded attendance",
              14,
              accent,
              true));
      gap(p, 7);
      p.addView(
          text(
              c[0] + " present · " + c[1] + " missed · " + c[2] + " unmarked",
              12,
              secondary,
              false));
      int needed =
          (int)
              Math.ceil(
                  Math.max(0, (target / 100.0 * (c[0] + c[1]) - c[0]) / (1 - target / 100.0)));
      if (needed > 0)
        p.addView(
            text(
                "Attend the next " + needed + " confirmed classes to reach " + target + "%",
                12,
                secondary,
                false));
    }
  }

  void lectureTiles(
      LinearLayout parent,
      String subject,
      List<JSONObject> classes,
      Map<String, String> records,
      Set<String> penalties)
      throws Exception {
    Map<String, Integer> ordinals = ParityRules.ordinals(records);
    List<JSONObject> entries = new ArrayList<>();
    for (JSONObject row : classes)
      if (row.optString("subject").equals(subject))
        entries.add(
            new JSONObject(row.toString())
                .put("_label", String.valueOf(ordinals.getOrDefault(row.optString("id"), 1))));
    for (String key : records.keySet())
      if (key.startsWith("event:")) {
        JSONObject e = Snapshot.object(records, key);
        if (e.optString("subject").equals(subject))
          entries.add(
              new JSONObject(e.toString())
                  .put("time", e.optString("start") + " – " + e.optString("end"))
                  .put("_activity", true)
                  .put("_label", e.optString("type").equals("Guest lecture") ? "G" : "A"));
      }
    entries.sort(
        Comparator.comparingLong((JSONObject row) -> Schedule.instant(row, false))
            .thenComparing(row -> row.optString("id")));
    LinearLayout line = null;
    int columns =
        Math.max(4, Math.min(10, (getResources().getConfiguration().screenWidthDp - 72) / 54));
    int i = 0;
    for (JSONObject row : entries) {
      if (i++ % columns == 0) {
        line = row();
        parent.addView(line);
      }
      Button tile =
          button(
              row.optString("_label"),
              () -> {
                if (row.optBoolean("_activity")) eventActions(row);
                else classActions(row);
              });
      tile.setPadding(0, 0, 0, 0);
      tile.setTextSize(13);
      String state =
          row.optBoolean("_activity")
              ? Snapshot.text(records, "attendance:custom-" + row.optString("id"))
              : Schedule.status(row, records, penalties);
      if (state.contains("Attended") || state.contains("OD"))
        tile.setBackgroundTintList(
            android.content.res.ColorStateList.valueOf(
                androidx.core.graphics.ColorUtils.setAlphaComponent(accent, 65)));
      tile.setContentDescription(
          "Lecture "
              + row.optString("_label")
              + ", "
              + row.optString("date")
              + ", "
              + row.optString("time"));
      line.addView(tile, new LinearLayout.LayoutParams(0, dp(48), 1));
    }
    if (line != null)
      for (int n = (i - 1) % columns + 1; n < columns; n++)
        line.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
  }

  void settings() throws Exception {
    title(body, "Settings", "Make SATHI yours.");
    FirebaseUser user = FirebaseAuth.getInstance().getCurrentUser();
    LinearLayout account = panel(body);
    account.addView(
        text(
            user.getDisplayName() == null ? "Your account" : user.getDisplayName(), 20, ink, true));
    gap(account, 6);
    account.addView(text(user.getEmail(), 14, secondary, false));
    gap(account, 12);
    account.addView(text(status, 13, accent, false));
    if (store.lastSync() > 0)
      account.addView(
          text(
              "Last sync: "
                  + Instant.ofEpochMilli(store.lastSync())
                      .atZone(Schedule.ZONE)
                      .format(DateTimeFormatter.ofPattern("d MMM, h:mm a")),
              12,
              secondary,
              false));
    gap(account, 8);
    account.addView(
        text(
            "Changes save on this phone immediately. Sync sends changes to other open devices"
                + " automatically. Background sync runs hourly, or when you tap Sync. Background"
                + " timing can be delayed by battery optimisation.",
            13,
            secondary,
            false));
    action(account, "Sync now", () -> sync(true));
    action(body, "Student profile", () -> studentProfile());
    action(body, "Check or correct timetable", () -> wholeTimetable(true));
    action(body, "Whole timetable", () -> wholeTimetable(false));
    LinearLayout appearance = panel(body);
    appearance.addView(text("Appearance", 18, ink, true));
    action(
        appearance,
        "Theme",
        () ->
            new MaterialAlertDialogBuilder(this)
                .setTitle("Appearance")
                .setItems(
                    new String[] {"System", "Light", "Dark"},
                    (d, i) -> {
                      getSharedPreferences("appearance", 0)
                          .edit()
                          .putString("mode", new String[] {"system", "light", "dark"}[i])
                          .apply();
                      recreate();
                    })
                .show());
    action(
        appearance,
        "Accent colour",
        () ->
            new MaterialAlertDialogBuilder(this)
                .setTitle("Accent colour")
                .setItems(
                    new String[] {
                      "System wallpaper",
                      "Blue",
                      "Purple",
                      "Green",
                      "Teal",
                      "Indigo",
                      "Pink",
                      "Orange",
                      "Mint",
                      "Cyan",
                      "Red",
                      "Brown",
                      "Yellow"
                    },
                    (d, i) -> {
                      getSharedPreferences("appearance", 0)
                          .edit()
                          .putBoolean("systemAccent", i == 0)
                          .apply();
                      if (i > 0)
                        preference(
                            "accent",
                            new String[] {
                                  "blue", "purple", "green", "teal", "indigo", "pink", "orange",
                                  "mint", "cyan", "red", "brown", "yellow"
                                }
                                [i - 1]);
                      else {
                        render();
                      }
                    })
                .show());
    action(
        appearance,
        "Text size",
        () ->
            new MaterialAlertDialogBuilder(this)
                .setTitle("Text size")
                .setItems(
                    new String[] {"Small", "Standard", "Large", "Extra large"},
                    (d, i) -> preference("fontScale", new double[] {0.9, 1, 1.15, 1.3}[i]))
                .show());
    action(appearance, "Ready-made themes", this::themeChoices);
    LinearLayout reminders = panel(body);
    reminders.addView(text("Notifications", 18, ink, true));
    toggle(reminders, "Fingerprint and sheet crosscheck", "proofCrosscheck", false);
    toggle(reminders, "Class and activity reminders", "reminders", false);
    toggle(reminders, "Live class countdown notification", "liveActivities", false);
    toggle(reminders, "Countdown inside class cards", "classCountdown", true);
    toggle(reminders, "Mess menu and laundry shortcuts", "campusShortcuts", false);
    action(reminders, "Reminder timing", this::reminderTiming);
    action(reminders, "Notification sound", this::soundChoice);
    toggle(reminders, "Notification sounds", "sounds", true);
    toggle(reminders, "Vibration", "haptics", true);
    reminders.addView(
        text(
            "Fingerprint reminder: 15 minutes before class. Sheet reminder: 40 minutes after the"
                + " start. Android may delay reminders; they do not mark attendance automatically.",
            12,
            secondary,
            false));
    LinearLayout schedule = panel(body);
    schedule.addView(text("Timetable", 18, ink, true));
    action(schedule, "Subjects and section", this::selection);
    action(schedule, "Import Excel or JSON", this::chooseImport);
    action(
        schedule,
        "Export account backup",
        () -> {
          Intent intent =
              new Intent(Intent.ACTION_CREATE_DOCUMENT)
                  .setType("application/json")
                  .addCategory(Intent.CATEGORY_OPENABLE)
                  .putExtra(Intent.EXTRA_TITLE, "SATHI-Android-backup.json");
          startActivityForResult(intent, 32);
        });
    action(schedule, "Semester history", this::semesterHistory);
    action(
        schedule,
        "Android Home Screen widget",
        () ->
            new MaterialAlertDialogBuilder(this)
                .setTitle("Add the SATHI widget")
                .setMessage(
                    "Touch and hold an empty area of your Home Screen, choose Widgets, then SATHI."
                        + " Resize it taller to show the next three days. Widgets read your local"
                        + " saved copy.")
                .setPositiveButton("OK", null)
                .show());
    action(
        body,
        "Sign out",
        () ->
            new MaterialAlertDialogBuilder(this)
                .setTitle("Sign out?")
                .setMessage(
                    "Your saved copy stays private on this device. Sync first to send any changes"
                        + " to your other devices.")
                .setNegativeButton("Cancel", null)
                .setPositiveButton(
                    "Sign out",
                    (d, w) -> {
                      try {
                        store.signOut();
                        ScheduleWidget.refresh(this);
                        render();
                      } catch (Exception e) {
                        error(e);
                      }
                    })
                .show());
    body.addView(
        text(
            "SATHI Android 1.2 · Android 10+\n"
                + "Native Material 3, dynamic colours, stylus canvas, widgets and actionable"
                + " countdown notifications.",
            12,
            secondary,
            false));
  }

  void toggle(LinearLayout p, String label, String key, boolean defaultValue) {
    MaterialSwitch sw = new MaterialSwitch(this);
    sw.setText(label);
    sw.setTextColor(ink);
    sw.setPadding(0, dp(12), 0, dp(12));
    sw.setChecked(store.object("study:preferences").optBoolean(key, defaultValue));
    sw.setOnCheckedChangeListener(
        (v, checked) -> {
          if (key.equals("reminders")
              && checked
              && Build.VERSION.SDK_INT >= 33
              && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                  != android.content.pm.PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[] {android.Manifest.permission.POST_NOTIFICATIONS}, 90);
          preference(key, checked);
        });
    p.addView(sw, new LinearLayout.LayoutParams(-1, dp(56)));
  }

  void preference(String key, Object value) {
    try {
      JSONObject p = store.object("study:preferences");
      defaults(p);
      p.put(key, value);
      store.put("study:preferences", p);
      ScheduleWidget.refresh(this);
      render();
    } catch (Exception e) {
      error(e);
    }
  }

  static void defaults(JSONObject p) throws Exception {
    JSONObject defaults =
        new JSONObject(
            "{\"didCustomizeAppearance\":false,\"accent\":\"blue\",\"glassOpacity\":0.75,\"fontScale\":1,\"sounds\":true,\"notificationSound\":\"default\",\"haptics\":true,\"reminders\":false,\"classCountdown\":true,\"liveActivities\":false,\"fingerprintLeadMinutes\":15,\"fingerprintTargetMinutes\":1,\"reminderGraceMinutes\":5,\"sheetReminderMinutes\":40,\"firstYearSection\":\"\",\"programme\":\"MBA\"}");
    Iterator<String> keys = defaults.keys();
    while (keys.hasNext()) {
      String k = keys.next();
      if (!p.has(k)) p.put(k, defaults.get(k));
    }
  }

  void studentProfile() {
    JSONObject prefs = store.object("study:preferences");
    int semester = store.object("selection").optInt("semester", 1);
    LinearLayout form = vertical();
    form.setPadding(dp(18), 0, dp(18), 0);
    EditText name = field(form, "Your name", prefs.optString("studentName", ""));
    Spinner course = new Spinner(this);
    String[] courses = {"MBA", "DBM", "DBAI", "HHM"};
    course.setAdapter(
        new ArrayAdapter<String>(this, android.R.layout.simple_spinner_dropdown_item, courses));
    for (int i = 0; i < courses.length; i++)
      if (courses[i].equals(prefs.optString("programme", "MBA"))) course.setSelection(i);
    form.addView(course);
    form.addView(
        text(
            "Semester " + semester + " · Year " + (semester <= 3 ? "1" : "2"),
            13,
            secondary,
            false));
    EditText section = field(form, "Section A, B, C or D", prefs.optString("firstYearSection", ""));
    if (semester >= 4) section.setVisibility(View.GONE);
    new MaterialAlertDialogBuilder(this)
        .setTitle("Student profile")
        .setView(form)
        .setNegativeButton("Cancel", null)
        .setPositiveButton(
            "Save",
            (dialog, which) -> {
              try {
                defaults(prefs);
                prefs
                    .put("studentName", name.getText().toString().trim())
                    .put("programme", courses[course.getSelectedItemPosition()])
                    .put("studentSemester", semester);
                if (semester <= 3)
                  prefs.put(
                      "firstYearSection",
                      section.getText().toString().trim().toUpperCase(Locale.ROOT));
                store.put("study:preferences", prefs);
                ScheduleWidget.refresh(this);
                render();
              } catch (Exception error) {
                error(error);
              }
            })
        .show();
  }

  void selection() {
    try {
      JSONObject report = store.object("timetable"), sel = store.object("selection");
      JSONArray subjects = report.optJSONArray("subjects");
      if (subjects == null) {
        empty();
        return;
      }
      LinearLayout form = vertical();
      form.setPadding(dp(18), 0, dp(18), 0);
      EditText section =
          field(
              form,
              "First-year section (A, B, C…)",
              store.object("study:preferences").optString("firstYearSection"));
      if (sel.optInt("semester", 1) >= 4) section.setVisibility(View.GONE);
      JSONArray selected = sel.optJSONArray("keys");
      Set<String> old = new HashSet<>();
      if (selected != null)
        for (int i = 0; i < selected.length(); i++) old.add(selected.getString(i));
      List<CheckBox> boxes = new ArrayList<>();
      for (int i = 0; i < subjects.length(); i++) {
        JSONObject s = subjects.getJSONObject(i);
        CheckBox b = new CheckBox(this);
        b.setText(s.optString("name"));
        b.setTextColor(ink);
        b.setTag(s.getString("key"));
        b.setChecked(old.contains(s.getString("key")));
        form.addView(b);
        boxes.add(b);
      }
      for (CheckBox box : boxes)
        box.setOnCheckedChangeListener(
            (button, checked) -> {
              if (checked) {
                String base = box.getTag().toString().split("\\|", -1)[0];
                for (CheckBox other : boxes)
                  if (other != box
                      && other.isChecked()
                      && other.getTag().toString().split("\\|", -1)[0].equals(base))
                    other.setChecked(false);
              }
            });
      ScrollView scroll = new ScrollView(this);
      scroll.addView(form);
      new MaterialAlertDialogBuilder(this)
          .setTitle("Your subjects")
          .setView(scroll)
          .setNegativeButton("Cancel", null)
          .setPositiveButton(
              "Save",
              (d, w) -> {
                try {
                  JSONArray keys = new JSONArray();
                  for (CheckBox b : boxes) if (b.isChecked()) keys.put(b.getTag().toString());
                  if (sel.optInt("semester", 1) >= 4 && keys.length() == 0)
                    throw new Exception("Choose at least one subject");
                  sel.put("keys", keys);
                  store.put("selection", sel);
                  JSONObject p = store.object("study:preferences");
                  defaults(p);
                  p.put(
                      "firstYearSection",
                      section.getText().toString().trim().toUpperCase(Locale.ROOT));
                  store.put("study:preferences", p);
                  sync(false);
                  ScheduleWidget.refresh(this);
                  render();
                } catch (Exception e) {
                  error(e);
                }
              })
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  void semesterHistory() {
    try {
      List<JSONObject> archived = new ArrayList<>();
      JSONObject index = store.assetIndex();
      Iterator<String> ids = index.keys();
      while (ids.hasNext()) {
        JSONObject meta = index.getJSONObject(ids.next());
        if (meta.optString("kind").equals("semester")) archived.add(meta);
      }
      if (archived.isEmpty()) {
        new MaterialAlertDialogBuilder(this)
            .setTitle("Semester history")
            .setMessage(
                "Previous terms are archived here when the next timetable is imported. Sync to"
                    + " retrieve archives from other devices.")
            .setPositiveButton("OK", null)
            .show();
        return;
      }
      String[] titles = new String[archived.size()];
      for (int i = 0; i < titles.length; i++) titles[i] = archived.get(i).optString("title");
      new MaterialAlertDialogBuilder(this)
          .setTitle("Previous semesters")
          .setItems(
              titles,
              (d, i) -> {
                try {
                  Map<String, String> records =
                      ParityRules.archivedRecords(store.asset(archived.get(i).getString("id")));
                  LinearLayout content = vertical();
                  content.setPadding(dp(18), dp(12), dp(18), dp(18));
                  List<JSONObject> classes = Schedule.classes(records);
                  Set<String> penalties = Schedule.penalties(classes, records);
                  for (JSONObject row : classes) {
                    LinearLayout panel = panel(content);
                    panel.addView(
                        text(
                            row.optString("date") + " · " + row.optString("time"),
                            12,
                            accent,
                            true));
                    panel.addView(text(row.optString("subject"), 17, ink, true));
                    panel.addView(
                        text(Schedule.status(row, records, penalties), 13, secondary, false));
                  }
                  ScrollView scroll = new ScrollView(this);
                  scroll.addView(content);
                  new MaterialAlertDialogBuilder(this)
                      .setTitle(titles[i] + " · " + classes.size() + " classes")
                      .setView(scroll)
                      .setPositiveButton("Done", null)
                      .show();
                } catch (Exception e) {
                  error(e);
                }
              })
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  void chooseImport() {
    LinearLayout form = vertical();
    form.setPadding(dp(18), 0, dp(18), 0);
    int next =
        store.hasTimetable()
            ? store.object("selection").optInt("semester", 1) + 1
            : store.object("study:preferences").optInt("studentSemester", 1);
    EditText semester = field(form, "Semester", String.valueOf(next));
    semester.setInputType(2);
    Spinner course = new Spinner(this);
    String[] courses = {"MBA", "DBM", "DBAI", "HHM"};
    course.setAdapter(
        new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, courses));
    course.setSelection(
        Math.max(
            0,
            Arrays.asList(courses)
                .indexOf(store.object("study:preferences").optString("programme", "MBA"))));
    form.addView(course);
    EditText section =
        field(
            form,
            "First-year section (A, B, C, D or blank for common)",
            store.object("study:preferences").optString("firstYearSection"));
    editorDialog(
        store.hasTimetable()
            ? "Next semester · current term will be archived"
            : "Your course and semester",
        form,
        () -> {
          try {
            int number = Integer.parseInt(semester.getText().toString());
            if (number < 1 || number > 20) throw new Exception("Enter a semester between 1 and 20");
            JSONObject prefs = store.object("study:preferences");
            prefs
                .put("studentSemester", number)
                .put("programme", courses[course.getSelectedItemPosition()])
                .put(
                    "firstYearSection",
                    section.getText().toString().trim().toUpperCase(Locale.ROOT));
            pendingImportPreferences = prefs;
            importSemester = number;
            openWorkbookPicker();
            return true;
          } catch (Exception e) {
            error(e);
            return false;
          }
        });
  }

  public void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (result != RESULT_OK || data == null || data.getData() == null) return;
    Uri uri = data.getData();
    if (request == 41 && documentResult != null) {
      java.util.function.Consumer<Uri> callback = documentResult;
      documentResult = null;
      callback.accept(uri);
      return;
    }
    if (request == 32) {
      store.io.execute(
          () -> {
            try (OutputStream out = getContentResolver().openOutputStream(uri)) {
              out.write(Snapshot.encode(store.copy()));
              runOnUiThread(
                  () -> Toast.makeText(this, "Account backup exported", Toast.LENGTH_SHORT).show());
            } catch (Exception e) {
              runOnUiThread(() -> error(e));
            }
          });
      return;
    }
    if (request == 31) {
      status = "Reading timetable…";
      render();
      store.io.execute(
          () -> {
            try (InputStream in = getContentResolver().openInputStream(uri)) {
              byte[] bytes = readLimited(in, 20000000);
              JSONObject report;
              if (bytes.length > 2 && bytes[0] == 'P' && bytes[1] == 'K')
                report = ExcelImport.read(bytes, "Imported timetable.xlsx");
              else
                report = new JSONObject(new String(bytes, java.nio.charset.StandardCharsets.UTF_8));
              JSONArray subjects = report.getJSONArray("subjects");
              report.getJSONArray("sessions");
              report.getJSONArray("events");
              runOnUiThread(() -> confirmImport(report, subjects));
            } catch (Exception e) {
              runOnUiThread(() -> error(e));
            }
          });
    }
  }

  void confirmImport(JSONObject report, JSONArray subjects) {
    try {
      if (!pendingProgramme.isEmpty()) {
        String course = pendingProgramme;
        pendingProgramme = "";
        JSONObject merged = ParityRules.appendProgramme(store.object("timetable"), report, course);
        store.put("timetable", merged);
        afterEdit();
        return;
      }
      int number = importSemester;
      int classes = report.getJSONArray("sessions").length();
      String warnings =
          report.optJSONArray("warnings") == null
              ? ""
              : report.getJSONArray("warnings").length()
                  + " import warnings; use Check timetable to review.";
      new MaterialAlertDialogBuilder(this)
          .setTitle("Import semester " + number + "?")
          .setMessage(
              subjects.length()
                  + " subject/section groups · "
                  + classes
                  + " source classes.\n"
                  + warnings
                  + (store.hasTimetable()
                      ? "\nYour current semester, attendance and notes will be retained in History."
                      : ""))
          .setNegativeButton("Cancel", null)
          .setPositiveButton(
              "Import",
              (d, w) -> {
                try {
                  JSONArray keys = new JSONArray();
                  if (number <= 3)
                    for (int i = 0; i < subjects.length(); i++)
                      keys.put(subjects.getJSONObject(i).getString("key"));
                  boolean supplement =
                      store.hasTimetable()
                          && ParityRules.containsAll(report, store.object("timetable"));
                  store.importReport(report, keys, number);
                  if (!supplement && pendingImportPreferences != null)
                    store.put("study:preferences", pendingImportPreferences);
                  pendingImportPreferences = null;
                  ScheduleWidget.refresh(this);
                  render();
                  sync(false);
                  if (number >= 4 && store.object("selection").optJSONArray("keys").length() == 0)
                    selection();
                } catch (Exception e) {
                  error(e);
                }
              })
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  static byte[] readLimited(InputStream in, int limit) throws Exception {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    byte[] buffer = new byte[8192];
    int n;
    while ((n = in.read(buffer)) != -1) {
      if (out.size() + n > limit) throw new IOException("File is too large");
      out.write(buffer, 0, n);
    }
    return out.toByteArray();
  }

  void notebooks() throws Exception {
    title(body, "Notebooks", "A place for every thought.");
    action(body, "New notebook", () -> newBook(""));
    action(body, "New quick note", () -> newNote(""));
    JSONObject index = store.assetIndex();
    List<JSONObject> books = new ArrayList<>();
    Iterator<String> ids = index.keys();
    while (ids.hasNext()) {
      JSONObject m = index.getJSONObject(ids.next());
      String kind = m.optString("kind");
      if (kind.equals("notebook") || kind.equals("note")) books.add(m);
    }
    books.sort(Comparator.comparing(m -> m.optString("title")));
    for (JSONObject m : books) {
      JSONObject data = store.asset(m.getString("id"));
      if (data.has("deletedAt")) continue;
      LinearLayout p = panel(body);
      p.addView(text(m.optString("title", "Notebook"), 20, ink, true));
      gap(p, 8);
      p.addView(
          text(
              m.optString("kind").equals("note")
                  ? "Quick note"
                  : data.optJSONArray("pageIDs") == null
                      ? "Notebook"
                      : data.getJSONArray("pageIDs").length() + " pages",
              13,
              accent,
              false));
      p.setOnClickListener(
          v -> {
            if (m.optString("kind").equals("note")) editNote(m);
            else openBook(m);
          });
    }
    if (books.isEmpty()) {
      LinearLayout p = panel(body);
      p.addView(text("Start something worth keeping", 21, ink, true));
      gap(p, 10);
      p.addView(
          text(
              "Create a subject notebook or a quick book. Pages support typing, Android"
                  + " stylus/finger ink, images and shapes. Apple PencilKit bytes are preserved in"
                  + " their original format.",
              14,
              secondary,
              false));
    }
    JSONArray subjects = store.object("timetable").optJSONArray("subjects");
    if (subjects != null) {
      gap(body, 16);
      body.addView(text("Subject notebooks", 20, ink, true));
      for (int i = 0; i < subjects.length(); i++) {
        String name = subjects.getJSONObject(i).optString("name");
        action(body, name, () -> newBook(name));
      }
    }
  }

  void newNote(String subject) {
    LinearLayout form = vertical();
    form.setPadding(dp(20), 0, dp(20), 0);
    EditText name = field(form, "Note title", subject.isEmpty() ? "Quick note" : subject);
    new MaterialAlertDialogBuilder(this)
        .setTitle("New note")
        .setView(form)
        .setNegativeButton("Cancel", null)
        .setPositiveButton(
            "Create",
            (d, w) -> {
              try {
                String id = UUID.randomUUID().toString().toUpperCase(Locale.ROOT);
                store.saveAsset(
                    id,
                    "note",
                    name.getText().toString().trim(),
                    subject,
                    new JSONObject().put("text", "").put("drawing", ""));
                editNote(store.assetIndex().getJSONObject(id));
              } catch (Exception e) {
                error(e);
              }
            })
        .show();
  }

  void newBook(String subject) {
    LinearLayout form = vertical();
    form.setPadding(dp(18), 0, dp(18), 0);
    EditText title = field(form, "Notebook name", subject.isEmpty() ? "Quick book" : subject);
    String[] papers = {"ruled", "blank", "grid", "dotted", "cornell", "checklist"},
        covers = {"linen", "plain", "leather", "grid"};
    Spinner paper = new Spinner(this);
    paper.setAdapter(
        new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, papers));
    form.addView(paper);
    Spinner cover = new Spinner(this);
    cover.setAdapter(
        new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, covers));
    form.addView(cover);
    editorDialog(
        "New notebook",
        form,
        () -> {
          try {
            if (title.getText().toString().trim().isEmpty())
              throw new Exception("Enter a notebook name");
            JSONObject book =
                NotebookDocuments.createBook(
                    title.getText().toString().trim(),
                    subject,
                    store.object("study:semesters").optString("current"),
                    papers[paper.getSelectedItemPosition()],
                    covers[cover.getSelectedItemPosition()],
                    accent);
            NotebookDocuments.saveBook(store, book);
            NotebookDocuments.addPage(store, book, 0, null);
            render();
            openBook(store.assetIndex().getJSONObject(book.getString("id")));
            sync(false);
            return true;
          } catch (Exception e) {
            error(e);
            return false;
          }
        });
  }

  void openBook(JSONObject metadata) {
    try {
      JSONObject book = store.asset(metadata.getString("id"));
      Dialog dialog = new Dialog(this, R.style.SathiTheme);
      LinearLayout layout = vertical();
      layout.setBackgroundColor(bg);
      layout.setPadding(dp(18), dp(12), dp(18), dp(12));
      LinearLayout bar = row();
      bar.addView(button("Back", dialog::dismiss));
      bar.addView(
          text(book.optString("title"), 20, ink, true), new LinearLayout.LayoutParams(0, -2, 1));
      layout.addView(bar);
      LinearLayout actions = row();
      actions.addView(
          button(
              "Add page",
              () -> {
                try {
                  NotebookDocuments.addPage(
                      store, book, book.getJSONArray("pageIDs").length(), null);
                  dialog.dismiss();
                  openBook(store.assetIndex().getJSONObject(book.getString("id")));
                } catch (Exception e) {
                  error(e);
                }
              }),
          new LinearLayout.LayoutParams(0, -2, 1));
      actions.addView(
          button(
              "Cover / paper",
              () ->
                  editBook(
                      book,
                      () -> {
                        dialog.dismiss();
                        try {
                          openBook(store.assetIndex().getJSONObject(book.getString("id")));
                        } catch (Exception e) {
                          error(e);
                        }
                      })));
      actions.addView(button("Export PDF", () -> exportBook(book)));
      layout.addView(actions);
      ScrollView scroll = new ScrollView(this);
      LinearLayout pages = vertical();
      scroll.addView(pages);
      layout.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
      JSONArray ids = book.getJSONArray("pageIDs");
      for (int i = 0; i < ids.length(); i++) {
        final int position = i;
        String id = ids.getString(i);
        LinearLayout panel = panel(pages);
        panel.addView(text("Page " + (i + 1), 19, ink, true));
        LinearLayout controls = row();
        controls.addView(button("Open", () -> openNotebookPage(id)));
        controls.addView(
            button(
                "Edit pages",
                () ->
                    new MaterialAlertDialogBuilder(this)
                        .setTitle("Page " + (position + 1))
                        .setItems(
                            new String[] {
                              "Insert page before",
                              "Insert page after",
                              "Duplicate page",
                              "Delete page"
                            },
                            (d, choice) -> {
                              try {
                                if (choice == 3) {
                                  new MaterialAlertDialogBuilder(this)
                                      .setTitle("Delete this page?")
                                      .setMessage(
                                          "The page is removed from the notebook. Its stored"
                                              + " content is retained for recovery.")
                                      .setNegativeButton("Cancel", null)
                                      .setPositiveButton(
                                          "Delete",
                                          (x, w) -> {
                                            try {
                                              NotebookDocuments.deletePage(store, book, id);
                                              dialog.dismiss();
                                              openBook(metadata);
                                              sync(false);
                                            } catch (Exception e) {
                                              error(e);
                                            }
                                          })
                                      .show();
                                  return;
                                }
                                NotebookDocuments.addPage(
                                    store,
                                    book,
                                    choice == 0 ? position : position + 1,
                                    choice == 2 ? store.asset(id) : null);
                                dialog.dismiss();
                                openBook(metadata);
                                sync(false);
                              } catch (Exception e) {
                                error(e);
                              }
                            })
                        .show()));
        panel.addView(controls);
        panel.setOnClickListener(v -> openNotebookPage(id));
      }
      if (ids.length() == 0)
        pages.addView(text("No pages yet. Add a page to start.", 16, secondary, false));
      dialog.setContentView(layout);
      dialog.show();
      dialog.getWindow().setLayout(-1, -1);
    } catch (Exception e) {
      error(e);
    }
  }

  void openNotebookPage(String id) {
    startActivity(new Intent(this, NotebookPageActivity.class).putExtra("pageID", id));
  }

  void editBook(JSONObject book, Runnable saved) {
    try {
      LinearLayout form = vertical();
      form.setPadding(dp(18), 0, dp(18), 0);
      EditText name = field(form, "Notebook name", book.optString("title"));
      String[] types = {"ruled", "blank", "grid", "dotted", "cornell", "checklist"},
          covers = {"linen", "plain", "leather", "grid"};
      Spinner paper = new Spinner(this);
      paper.setAdapter(
          new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, types));
      paper.setSelection(
          Math.max(
              0, Arrays.asList(types).indexOf(book.getJSONObject("paper").optString("template"))));
      form.addView(paper);
      Spinner cover = new Spinner(this);
      cover.setAdapter(
          new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, covers));
      cover.setSelection(Math.max(0, Arrays.asList(covers).indexOf(book.optString("coverStyle"))));
      form.addView(cover);
      editorDialog(
          "Cover and new-page style",
          form,
          () -> {
            try {
              book.put("title", name.getText().toString())
                  .put("coverStyle", covers[cover.getSelectedItemPosition()]);
              book.getJSONObject("paper").put("template", types[paper.getSelectedItemPosition()]);
              book.put("modifiedAt", Snapshot.swiftNow());
              NotebookDocuments.saveBook(store, book);
              saved.run();
              sync(false);
              return true;
            } catch (Exception e) {
              error(e);
              return false;
            }
          });
    } catch (Exception e) {
      error(e);
    }
  }

  void exportBook(JSONObject book) {
    Toast.makeText(this, "Preparing PDF…", Toast.LENGTH_SHORT).show();
    store.io.execute(
        () -> {
          try {
            File file = NotebookPageActivity.exportPdf(this, store, book);
            runOnUiThread(() -> NotebookPageActivity.sharePdf(this, file));
          } catch (Exception e) {
            runOnUiThread(() -> error(e));
          }
        });
  }

  void editNote(JSONObject meta) {
    try {
      String id = meta.getString("id");
      JSONObject document = store.asset(id);
      boolean page = meta.optString("kind").equals("notebookPage");
      if (page) {
        openNotebookPage(id);
        return;
      }
      editor = new Dialog(this, R.style.SathiTheme);
      LinearLayout sheet = vertical();
      sheet.setBackgroundColor(0xFFF9F6EE);
      sheet.setPadding(dp(18), dp(16), dp(18), dp(18));
      LinearLayout bar = row();
      Button done =
          button(
              "Done",
              () -> {
                flushDraft();
                editor.dismiss();
              });
      bar.addView(done);
      TextView label = text(meta.optString("title", "Notebook"), 17, 0xFF17253B, true);
      label.setPadding(dp(12), 0, 0, 0);
      bar.addView(label, new LinearLayout.LayoutParams(0, -2, 1));
      sheet.addView(bar);
      ScrollView scroll = new ScrollView(this);
      LinearLayout paper = vertical();
      paper.setPadding(dp(12), dp(12), dp(12), dp(40));
      paper.setBackground(new PaperDrawable());
      scroll.addView(paper);
      sheet.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
      if (!document.optString("drawing").isEmpty()) {
        TextView warning =
            text(
                "Apple handwriting is preserved in this page. View it on your Apple device; typed"
                    + " text below remains editable here.",
                12,
                0xFF64748B,
                false);
        paper.addView(warning);
        gap(paper, 16);
      }
      List<EditText> fields = new ArrayList<>();
      JSONArray boxes = page ? document.optJSONArray("textObjects") : null;
      if (page && (boxes == null || boxes.length() == 0)) {
        boxes =
            new JSONArray()
                .put(
                    new JSONObject()
                        .put("id", UUID.randomUUID().toString().toUpperCase(Locale.ROOT))
                        .put("text", "")
                        .put("x", 48)
                        .put("y", 70)
                        .put("width", 490)
                        .put("height", 160)
                        .put("fontSize", 18)
                        .put("bold", false)
                        .put("italic", false)
                        .put("underline", false)
                        .put("alignment", "left")
                        .put(
                            "color",
                            new JSONObject()
                                .put("red", 0.12)
                                .put("green", 0.16)
                                .put("blue", 0.21)));
        document.put("textObjects", boxes);
      }
      int count = page ? boxes.length() : 1;
      for (int i = 0; i < count; i++) {
        EditText edit = new EditText(this);
        edit.setText(page ? boxes.getJSONObject(i).optString("text") : document.optString("text"));
        edit.setTextColor(0xFF17253B);
        edit.setTextSize(18);
        edit.setGravity(Gravity.TOP);
        edit.setMinLines(count == 1 ? 20 : 5);
        edit.setBackgroundColor(Color.TRANSPARENT);
        edit.setHint("Start writing…");
        edit.setHintTextColor(0xFF7A8797);
        edit.setLineSpacing(dp(10), 1);
        paper.addView(edit, new LinearLayout.LayoutParams(-1, -2));
        fields.add(edit);
      }
      final JSONArray textBoxes = boxes;
      Runnable save =
          () -> {
            try {
              for (int i = 0; i < fields.size(); i++) {
                if (page)
                  textBoxes.getJSONObject(i).put("text", fields.get(i).getText().toString());
                else document.put("text", fields.get(i).getText().toString());
              }
              if (page) document.put("modifiedAt", Snapshot.swiftNow());
              store.saveAsset(
                  id,
                  meta.getString("kind"),
                  meta.optString("title"),
                  meta.optString("subject"),
                  document);
            } catch (Exception e) {
              error(e);
            }
          };
      TextWatcher watcher =
          new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

            public void onTextChanged(CharSequence s, int start, int before, int count) {
              if (saveDraft != null) handler.removeCallbacks(saveDraft);
              saveDraft = save;
              handler.postDelayed(saveDraft, 600);
            }

            public void afterTextChanged(Editable e) {}
          };
      for (EditText edit : fields) edit.addTextChangedListener(watcher);
      editor.setContentView(sheet);
      editor.setOnDismissListener(
          d -> {
            flushDraft();
            editor = null;
            render();
          });
      editor.show();
      editor.getWindow().setLayout(-1, -1);
      editor.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    } catch (Exception e) {
      editor = null;
      error(e);
    }
  }

  void flushDraft() {
    if (saveDraft != null) {
      Runnable save = saveDraft;
      saveDraft = null;
      handler.removeCallbacks(save);
      save.run();
    }
  }

  void error(Exception e) {
    status = e.getMessage() == null ? "Could not complete this action" : e.getMessage();
    Toast.makeText(this, status, Toast.LENGTH_LONG).show();
  }

  static class PaperDrawable extends android.graphics.drawable.Drawable {
    Paint p = new Paint(3);

    public void draw(Canvas c) {
      c.drawColor(0xFFF9F6EE);
      p.setColor(0xFFD4DFE7);
      p.setStrokeWidth(1);
      for (int y = 48; y < getBounds().height(); y += 42)
        c.drawLine(0, y, getBounds().width(), y, p);
      p.setColor(0xFFE8B8B4);
      c.drawLine(18, 0, 18, getBounds().height(), p);
    }

    public void setAlpha(int a) {}

    public void setColorFilter(android.graphics.ColorFilter f) {}

    public int getOpacity() {
      return android.graphics.PixelFormat.OPAQUE;
    }
  }

  static class Icon extends View {
    Paint p = new Paint(3);
    int kind;

    Icon(Context c, int k, int color) {
      super(c);
      kind = k;
      p.setColor(color);
      p.setStrokeWidth(1.8f);
      p.setStyle(Paint.Style.STROKE);
      p.setStrokeCap(Paint.Cap.ROUND);
      p.setStrokeJoin(Paint.Join.ROUND);
    }

    protected void onDraw(Canvas canvas) {
      canvas.save();
      canvas.scale(getWidth() / 24f, getHeight() / 24f);
      switch (kind) {
        case 0:
          Path home = new Path();
          home.moveTo(3, 10);
          home.lineTo(12, 3);
          home.lineTo(21, 10);
          home.moveTo(5, 9);
          home.lineTo(5, 21);
          home.lineTo(19, 21);
          home.lineTo(19, 9);
          home.moveTo(9, 21);
          home.lineTo(9, 14);
          home.lineTo(15, 14);
          home.lineTo(15, 21);
          canvas.drawPath(home, p);
          break;
        case 1:
          canvas.drawRoundRect(3, 5, 21, 21, 3, 3, p);
          canvas.drawLine(3, 10, 21, 10, p);
          canvas.drawLine(8, 3, 8, 7, p);
          canvas.drawLine(16, 3, 16, 7, p);
          for (int y = 14; y <= 18; y += 4)
            for (int x = 7; x <= 17; x += 5) canvas.drawPoint(x, y, p);
          break;
        case 2:
          canvas.drawRoundRect(4, 3, 20, 21, 2, 2, p);
          canvas.drawLine(8, 3, 8, 21, p);
          canvas.drawLine(11, 8, 17, 8, p);
          canvas.drawLine(11, 12, 17, 12, p);
          break;
        case 3:
          canvas.drawLine(4, 21, 21, 21, p);
          canvas.drawRect(5, 13, 8, 20, p);
          canvas.drawRect(11, 8, 14, 20, p);
          canvas.drawRect(17, 3, 20, 20, p);
          break;
        default:
          canvas.drawCircle(12, 12, 7, p);
          canvas.drawCircle(12, 12, 2.5f, p);
          for (int i = 0; i < 8; i++) {
            double a = i * Math.PI / 4;
            canvas.drawLine(
                12 + (float) Math.cos(a) * 7,
                12 + (float) Math.sin(a) * 7,
                12 + (float) Math.cos(a) * 10,
                12 + (float) Math.sin(a) * 10,
                p);
          }
      }
      canvas.restore();
    }
  }
}
