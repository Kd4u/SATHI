package com.karandeep.sathi;

import java.util.*;
import org.json.*;

/** Portable notebook manifests/pages use exactly the existing Apple JSON contract. */
public final class NotebookDocuments {
  public static String id() {
    return UUID.randomUUID().toString().toUpperCase(Locale.ROOT);
  }

  static JSONObject color(int rgb) throws Exception {
    return new JSONObject()
        .put("red", android.graphics.Color.red(rgb) / 255.0)
        .put("green", android.graphics.Color.green(rgb) / 255.0)
        .put("blue", android.graphics.Color.blue(rgb) / 255.0);
  }

  public static JSONObject paper(String template) throws Exception {
    return new JSONObject()
        .put("template", template)
        .put("size", "A4")
        .put("landscape", false)
        .put("customWidth", 595)
        .put("customHeight", 842)
        .put("background", new JSONObject().put("red", 1).put("green", 1).put("blue", 1))
        .put("ruleColor", new JSONObject().put("red", 0.65).put("green", 0.75).put("blue", 0.85))
        .put("backgroundOpacity", 1)
        .put("spacing", 28)
        .put("gridSpacing", 24)
        .put("dotSpacing", 20)
        .put("margin", 42);
  }

  public static double[] size(JSONObject paper) {
    String kind = paper.optString("size", "A4");
    double w =
        kind.equals("A5")
            ? 420
            : kind.equals("Letter")
                ? 612
                : kind.equals("Custom")
                    ? Math.min(2400, Math.max(200, paper.optDouble("customWidth", 595)))
                    : 595;
    double h =
        kind.equals("A5")
            ? 595
            : kind.equals("Letter")
                ? 792
                : kind.equals("Custom")
                    ? Math.min(3200, Math.max(200, paper.optDouble("customHeight", 842)))
                    : 842;
    return paper.optBoolean("landscape") ? new double[] {h, w} : new double[] {w, h};
  }

  public static JSONObject createBook(
      String title, String subject, String semester, String template, String cover, int color)
      throws Exception {
    return new JSONObject()
        .put("version", 1)
        .put("id", id())
        .put("title", title)
        .put("subject", subject)
        .put("semesterID", semester)
        .put("folder", "")
        .put("coverStyle", cover)
        .put("coverColor", color(color))
        .put("paper", paper(template))
        .put("pageIDs", new JSONArray())
        .put("pageSizes", new JSONObject())
        .put("importedLegacyIDs", new JSONArray())
        .put("removedPageIDs", new JSONArray())
        .put("modifiedAt", Snapshot.swiftNow());
  }

  public static JSONObject createPage(JSONObject book) throws Exception {
    return new JSONObject()
        .put("version", 1)
        .put("id", id())
        .put("notebookID", book.getString("id"))
        .put("paper", new JSONObject(book.getJSONObject("paper").toString()))
        .put("drawing", "")
        .put("textObjects", new JSONArray())
        .put("elements", new JSONArray())
        .put("modifiedAt", Snapshot.swiftNow());
  }

  public static String addPage(Store store, JSONObject book, int position, JSONObject copy)
      throws Exception {
    JSONObject page =
        copy == null
            ? createPage(book)
            : new JSONObject(copy.toString())
                .put("id", id())
                .put("notebookID", book.getString("id"))
                .put("modifiedAt", Snapshot.swiftNow());
    String id = page.getString("id");
    store.saveAsset(
        id, "notebookPage", book.getString("title") + " · page", book.optString("subject"), page);
    JSONArray prior = book.getJSONArray("pageIDs"), next = new JSONArray();
    int target = Math.max(0, Math.min(position, prior.length()));
    for (int i = 0; i <= prior.length(); i++) {
      if (i == target) next.put(id);
      if (i < prior.length()) next.put(prior.get(i));
    }
    book.put("pageIDs", next).put("modifiedAt", Snapshot.swiftNow());
    JSONObject sizes = book.optJSONObject("pageSizes");
    if (sizes == null) sizes = new JSONObject();
    double[] size = size(page.getJSONObject("paper"));
    sizes.put(id, new JSONObject().put("width", size[0]).put("height", size[1]));
    book.put("pageSizes", sizes);
    saveBook(store, book);
    return id;
  }

  public static void deletePage(Store store, JSONObject book, String id) throws Exception {
    JSONArray next = new JSONArray(), prior = book.getJSONArray("pageIDs");
    for (int i = 0; i < prior.length(); i++)
      if (!prior.getString(i).equals(id)) next.put(prior.get(i));
    JSONArray removed = book.optJSONArray("removedPageIDs");
    if (removed == null) removed = new JSONArray();
    removed.put(id);
    book.put("removedPageIDs", removed).put("pageIDs", next).put("modifiedAt", Snapshot.swiftNow());
    if (book.optJSONObject("pageSizes") != null) book.getJSONObject("pageSizes").remove(id);
    saveBook(store, book);
  }

  public static void saveBook(Store store, JSONObject book) throws Exception {
    store.saveAsset(
        book.getString("id"), "notebook", book.getString("title"), book.optString("subject"), book);
  }

  public static JSONObject element(String kind, double x, double y) throws Exception {
    return new JSONObject()
        .put("id", id())
        .put("kind", kind)
        .put("x", x)
        .put("y", y)
        .put("width", 180)
        .put("height", 100)
        .put("text", "Text")
        .put("fontSize", 22)
        .put("bold", false)
        .put("opacity", 1)
        .put("color", new JSONObject().put("red", 0.18).put("green", 0.42).put("blue", 0.72));
  }
}
