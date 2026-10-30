package com.karandeep.sathi;

import android.content.*;
import android.graphics.*;
import android.text.*;
import android.view.*;
import java.io.*;
import java.util.*;
import org.json.*;

/**
 * Native Canvas/stylus editor. Ink is a transparent portable image layer, never PencilKit bytes.
 */
public final class NotebookSurface extends View {
  public static final int PAN = 0, PEN = 1, ERASER = 2, SELECT = 3;
  JSONObject document, selected;
  boolean selectedText;
  int mode = PEN, color = Color.rgb(30, 42, 56);
  float brush = 2.5f, opacity = 1;
  boolean fingerInk = true;
  Runnable changed = () -> {}, selectionChanged = () -> {};
  java.util.function.Consumer<Float> zoomChanged = v -> {};
  private Bitmap ink;
  private Canvas inkCanvas;
  private String inkID;
  private float lastX, lastY, downX, downY;
  private boolean drawing;
  private final Deque<Bitmap> undo = new ArrayDeque<>();
  private final Map<String, Bitmap> images = new HashMap<>();
  private final ScaleGestureDetector scale;

  public NotebookSurface(Context context, JSONObject document) throws Exception {
    super(context);
    this.document = document;
    double[] size = size(document);
    int width = (int) Math.min(1600, size[0]), height = (int) (width * size[1] / size[0]);
    ink = Bitmap.createBitmap(width, Math.max(1, height), Bitmap.Config.ARGB_8888);
    inkCanvas = new Canvas(ink);
    JSONArray elements = document.optJSONArray("elements");
    if (elements == null) {
      elements = new JSONArray();
      document.put("elements", elements);
    }
    for (int i = 0; i < elements.length(); i++) {
      JSONObject e = elements.getJSONObject(i);
      if (e.optString("id").startsWith("android-ink-")) {
        inkID = e.getString("id");
        Bitmap prior = decode(e.optString("image"), images, e.optString("id"));
        if (prior != null) {
          Paint paint = new Paint(3);
          paint.setAlpha((int) (255 * e.optDouble("opacity", 1)));
          float k = width / (float) size[0];
          inkCanvas.drawBitmap(
              prior,
              null,
              new RectF(
                  (float) e.optDouble("x") * k,
                  (float) e.optDouble("y") * k,
                  (float) (e.optDouble("x") + e.optDouble("width")) * k,
                  (float) (e.optDouble("y") + e.optDouble("height")) * k),
              paint);
        }
        break;
      }
    }
    if (inkID == null) inkID = "android-ink-" + NotebookDocuments.id();
    setLayerType(View.LAYER_TYPE_SOFTWARE, null);
    setContentDescription("Notebook page canvas. Choose pen, eraser, pan or select.");
    scale =
        new ScaleGestureDetector(
            context,
            new ScaleGestureDetector.SimpleOnScaleGestureListener() {
              public boolean onScale(ScaleGestureDetector detector) {
                zoomChanged.accept(detector.getScaleFactor());
                return true;
              }
            });
  }

  public static double[] size(JSONObject doc) {
    return NotebookDocuments.size(
        doc.optJSONObject("paper") == null ? new JSONObject() : doc.optJSONObject("paper"));
  }

  public static int rgb(JSONObject value, int fallback) {
    if (value == null) return fallback;
    return Color.rgb(
        (int) (255 * value.optDouble("red", 0)),
        (int) (255 * value.optDouble("green", 0)),
        (int) (255 * value.optDouble("blue", 0)));
  }

  public void undo() {
    if (undo.isEmpty()) return;
    Bitmap old = ink;
    ink = undo.removeLast();
    inkCanvas = new Canvas(ink);
    old.recycle();
    changed.run();
    invalidate();
  }

  void remember() {
    undo.addLast(ink.copy(Bitmap.Config.ARGB_8888, true));
    while (undo.size() > 8) undo.removeFirst().recycle();
  }

  public void flushInk() throws Exception {
    ByteArrayOutputStream bytes = new ByteArrayOutputStream();
    ink.compress(Bitmap.CompressFormat.PNG, 100, bytes);
    JSONArray list = document.getJSONArray("elements");
    JSONObject layer = null;
    for (int i = 0; i < list.length(); i++)
      if (list.getJSONObject(i).optString("id").equals(inkID)) layer = list.getJSONObject(i);
    double[] size = size(document);
    if (layer == null) {
      layer = NotebookDocuments.element("image", 0, 0).put("id", inkID);
      list.put(layer);
    }
    layer
        .put("x", 0)
        .put("y", 0)
        .put("width", size[0])
        .put("height", size[1])
        .put("opacity", 1)
        .put("image", java.util.Base64.getEncoder().encodeToString(bytes.toByteArray()));
  }

  protected void onDraw(Canvas canvas) {
    super.onDraw(canvas);
    double[] dimensions = size(document);
    float k = getWidth() / (float) dimensions[0];
    canvas.save();
    canvas.scale(k, k);
    drawPage(canvas, document, images, true);
    canvas.drawBitmap(
        ink, null, new RectF(0, 0, (float) dimensions[0], (float) dimensions[1]), new Paint(3));
    if (selected != null) {
      Paint p = new Paint(3);
      p.setStyle(Paint.Style.STROKE);
      p.setStrokeWidth(2 / k);
      p.setColor(0xFF4267A9);
      canvas.drawRect(bounds(selected), p);
    }
    canvas.restore();
  }

  public static void drawPage(
      Canvas c, JSONObject doc, Map<String, Bitmap> images, boolean skipInk) {
    JSONObject paper = doc.optJSONObject("paper");
    if (paper == null) paper = new JSONObject();
    double[] size = size(doc);
    Paint p = new Paint(3);
    p.setColor(rgb(paper.optJSONObject("background"), Color.WHITE));
    c.drawRect(0, 0, (float) size[0], (float) size[1], p);
    p.setColor(rgb(paper.optJSONObject("ruleColor"), 0xFFA6BFDA));
    p.setAlpha(90);
    p.setStrokeWidth(0.6f);
    String template = paper.optString("template", "ruled");
    float spacing =
        (float)
            Math.max(
                8,
                paper.optDouble(
                    template.equals("grid")
                        ? "gridSpacing"
                        : template.equals("dotted") ? "dotSpacing" : "spacing",
                    28));
    float margin = (float) paper.optDouble("margin", 42);
    if (!template.equals("blank")) {
      for (float y = spacing; y < size[1]; y += spacing) {
        if (template.equals("dotted")) {
          for (float x = spacing; x < size[0]; x += spacing) c.drawCircle(x, y, 0.8f, p);
        } else c.drawLine(margin, y, (float) size[0] - margin / 2, y, p);
      }
      if (template.equals("grid"))
        for (float x = spacing; x < size[0]; x += spacing) c.drawLine(x, 0, x, (float) size[1], p);
      if (template.equals("cornell"))
        c.drawLine((float) size[0] * 0.28f, 0, (float) size[0] * 0.28f, (float) size[1], p);
    }
    Bitmap preview = decode(doc.optString("previewPNG"), images, "apple-preview");
    if (preview != null)
      c.drawBitmap(preview, null, new RectF(0, 0, (float) size[0], (float) size[1]), new Paint(3));
    JSONArray elements = doc.optJSONArray("elements");
    if (elements != null)
      for (int i = 0; i < elements.length(); i++) {
        JSONObject e = elements.optJSONObject(i);
        if (e == null || skipInk && e.optString("id").startsWith("android-ink-")) continue;
        drawElement(c, e, images);
      }
    JSONArray text = doc.optJSONArray("textObjects");
    if (text != null)
      for (int i = 0; i < text.length(); i++) {
        JSONObject e = text.optJSONObject(i);
        if (e != null) drawText(c, e);
      }
  }

  static RectF bounds(JSONObject e) {
    float x = (float) e.optDouble("x"), y = (float) e.optDouble("y");
    return new RectF(
        x, y, x + (float) e.optDouble("width", 180), y + (float) e.optDouble("height", 100));
  }

  static void drawElement(Canvas c, JSONObject e, Map<String, Bitmap> images) {
    String kind = e.optString("kind");
    RectF r = bounds(e);
    Paint p = new Paint(3);
    p.setColor(rgb(e.optJSONObject("color"), 0xFF4267A9));
    p.setAlpha((int) (255 * Math.max(0, Math.min(1, e.optDouble("opacity", 1)))));
    if (kind.equals("image")) {
      Bitmap image = decode(e.optString("image"), images, e.optString("id"));
      if (image != null) c.drawBitmap(image, null, r, p);
    } else if (kind.equals("text")) drawText(c, e);
    else if (kind.equals("ellipse")) c.drawOval(r, p);
    else if (kind.equals("line") || kind.equals("arrow")) {
      p.setStrokeWidth(3);
      c.drawLine(r.left, r.top, r.right, r.bottom, p);
      if (kind.equals("arrow")) {
        double angle = Math.atan2(r.height(), r.width());
        for (double side : new double[] {-0.5, 0.5})
          c.drawLine(
              r.right,
              r.bottom,
              r.right - (float) (14 * Math.cos(angle + side)),
              r.bottom - (float) (14 * Math.sin(angle + side)),
              p);
      }
    } else if (kind.equals("rectangle")) c.drawRoundRect(r, 10, 10, p);
  }

  static void drawText(Canvas c, JSONObject e) {
    TextPaint p = new TextPaint(3);
    p.setColor(rgb(e.optJSONObject("color"), 0xFF1F2937));
    p.setAlpha((int) (255 * e.optDouble("opacity", 1)));
    p.setTextSize((float) e.optDouble("fontSize", 18));
    int style =
        e.optBoolean("bold")
            ? (e.optBoolean("italic") ? Typeface.BOLD_ITALIC : Typeface.BOLD)
            : (e.optBoolean("italic") ? Typeface.ITALIC : Typeface.NORMAL);
    p.setTypeface(Typeface.create("sans-serif", style));
    p.setUnderlineText(e.optBoolean("underline"));
    String text = e.optString("text");
    int width = Math.max(20, (int) e.optDouble("width", 340));
    Layout.Alignment alignment =
        e.optString("alignment").equals("center")
            ? Layout.Alignment.ALIGN_CENTER
            : e.optString("alignment").equals("right")
                ? Layout.Alignment.ALIGN_OPPOSITE
                : Layout.Alignment.ALIGN_NORMAL;
    StaticLayout layout =
        StaticLayout.Builder.obtain(text, 0, text.length(), p, width)
            .setAlignment(alignment)
            .setIncludePad(false)
            .build();
    c.save();
    c.translate((float) e.optDouble("x"), (float) e.optDouble("y"));
    layout.draw(c);
    c.restore();
  }

  static Bitmap decode(String data, Map<String, Bitmap> cache, String id) {
    if (data.isEmpty()) return null;
    String key = id + data.hashCode();
    if (cache.containsKey(key)) return cache.get(key);
    try {
      byte[] bytes = java.util.Base64.getDecoder().decode(data);
      BitmapFactory.Options opts = new BitmapFactory.Options();
      opts.inJustDecodeBounds = true;
      BitmapFactory.decodeByteArray(bytes, 0, bytes.length, opts);
      int sample = 1;
      while (opts.outWidth / sample > 2000 || opts.outHeight / sample > 2400) sample *= 2;
      opts = new BitmapFactory.Options();
      opts.inSampleSize = sample;
      Bitmap image = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, opts);
      cache.put(key, image);
      return image;
    } catch (Exception e) {
      return null;
    }
  }

  public boolean onTouchEvent(MotionEvent e) {
    scale.onTouchEvent(e);
    if (e.getPointerCount() > 1) {
      drawing = false;
      getParent().requestDisallowInterceptTouchEvent(true);
      return true;
    }
    if (mode == PAN) return false;
    boolean stylus =
        e.getToolType(0) == MotionEvent.TOOL_TYPE_STYLUS
            || e.getToolType(0) == MotionEvent.TOOL_TYPE_ERASER;
    if (mode != SELECT && !fingerInk && !stylus) return false;
    double[] size = size(document);
    float k = getWidth() / (float) size[0], x = e.getX() / k, y = e.getY() / k;
    if (e.getActionMasked() == MotionEvent.ACTION_DOWN) {
      downX = lastX = x;
      downY = lastY = y;
      if (mode == SELECT) {
        selected = hit(x, y);
        selectionChanged.run();
        invalidate();
        if (selected == null) return false;
      } else {
        remember();
        drawing = true;
        stroke(
            x,
            y,
            x,
            y,
            e.getPressure(),
            mode == ERASER || e.getToolType(0) == MotionEvent.TOOL_TYPE_ERASER);
      }
      getParent().requestDisallowInterceptTouchEvent(true);
      return true;
    }
    if (e.getActionMasked() == MotionEvent.ACTION_MOVE) {
      if (mode == SELECT && selected != null) {
        try {
          selected
              .put("x", Math.max(0, selected.optDouble("x") + x - lastX))
              .put("y", Math.max(0, selected.optDouble("y") + y - lastY));
        } catch (Exception ignored) {
        }
      } else if (drawing)
        stroke(
            lastX,
            lastY,
            x,
            y,
            e.getPressure(),
            mode == ERASER || e.getToolType(0) == MotionEvent.TOOL_TYPE_ERASER);
      lastX = x;
      lastY = y;
      invalidate();
      return true;
    }
    if (e.getActionMasked() == MotionEvent.ACTION_UP
        || e.getActionMasked() == MotionEvent.ACTION_CANCEL) {
      if (drawing || mode == SELECT && selected != null) changed.run();
      drawing = false;
      performClick();
      invalidate();
      return true;
    }
    return true;
  }

  public boolean performClick() {
    super.performClick();
    return true;
  }

  void stroke(float x, float y, float nx, float ny, float pressure, boolean erase) {
    float k = ink.getWidth() / (float) size(document)[0];
    Paint p = new Paint(3);
    p.setColor(color);
    p.setAlpha((int) (255 * opacity));
    p.setStrokeCap(Paint.Cap.ROUND);
    p.setStrokeJoin(Paint.Join.ROUND);
    p.setStrokeWidth((erase ? 14 : brush) * k * Math.max(0.5f, Math.min(1.5f, pressure)));
    if (erase) p.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.CLEAR));
    inkCanvas.drawLine(x * k, y * k, nx * k, ny * k, p);
    invalidate();
  }

  JSONObject hit(float x, float y) {
    for (String array : new String[] {"textObjects", "elements"}) {
      JSONArray values = document.optJSONArray(array);
      if (values == null) continue;
      for (int i = values.length() - 1; i >= 0; i--) {
        JSONObject value = values.optJSONObject(i);
        if (value == null || value.optString("id").startsWith("android-ink-")) continue;
        if (bounds(value).contains(x, y)) {
          selectedText = array.equals("textObjects");
          return value;
        }
      }
    }
    return null;
  }

  public void add(JSONObject element, boolean text) throws Exception {
    String key = text ? "textObjects" : "elements";
    JSONArray values = document.optJSONArray(key);
    if (values == null) {
      values = new JSONArray();
      document.put(key, values);
    }
    values.put(element);
    selected = element;
    selectedText = text;
    changed.run();
    invalidate();
  }

  public void removeSelected() throws Exception {
    if (selected == null) return;
    String key = selectedText ? "textObjects" : "elements";
    JSONArray prior = document.getJSONArray(key), next = new JSONArray();
    for (int i = 0; i < prior.length(); i++)
      if (!prior.getJSONObject(i).optString("id").equals(selected.optString("id")))
        next.put(prior.get(i));
    document.put(key, next);
    selected = null;
    changed.run();
    invalidate();
  }

  public void reorder(boolean front) throws Exception {
    if (selected == null) return;
    JSONObject value = selected;
    boolean text = selectedText;
    removeSelected();
    JSONArray values = document.getJSONArray(text ? "textObjects" : "elements");
    if (front) values.put(value);
    else {
      JSONArray next = new JSONArray().put(value);
      for (int i = 0; i < values.length(); i++) next.put(values.get(i));
      document.put(text ? "textObjects" : "elements", next);
    }
    selected = value;
    selectedText = text;
    changed.run();
    invalidate();
  }
}
