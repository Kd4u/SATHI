package com.karandeep.sathi;

import java.time.*;
import java.time.format.*;
import java.util.*;
import java.util.regex.*;
import org.json.*;

public final class Schedule {
  public static final ZoneId ZONE = ZoneId.of("Asia/Kolkata");

  public static LocalDate today() {
    return LocalDate.now(ZONE);
  }

  public static List<JSONObject> classes(Map<String, String> records) throws Exception {
    JSONObject report = Snapshot.object(records, "timetable"),
        selection = Snapshot.object(records, "selection"),
        prefs = Snapshot.object(records, "study:preferences");
    JSONArray sessions = report.optJSONArray("sessions"), keys = selection.optJSONArray("keys");
    Set<String> selected = new HashSet<>();
    if (keys != null) for (int i = 0; i < keys.length(); i++) selected.add(keys.getString(i));
    String section = prefs.optString("firstYearSection", "");
    int semester = selection.optInt("semester", 1);
    List<JSONObject> out = new ArrayList<>();
    String current = Snapshot.object(records, "study:semesters").optString("current");
    Set<String> ids = new HashSet<>();
    if (sessions != null)
      for (int i = 0; i < sessions.length(); i++) {
        JSONObject s = new JSONObject(sessions.getJSONObject(i).toString());
        String id = s.getString("id");
        ids.add(id);
        if (semester >= 4
            && !selected.contains(s.optString("subject") + "|" + s.optString("section"))) continue;
        if (semester < 4
            && !section.isEmpty()
            && !s.optString("section").isEmpty()
            && !section.equalsIgnoreCase(s.optString("section"))) continue;
        JSONObject edit =
            records.containsKey("study:override:" + id)
                ? Snapshot.object(records, "study:override:" + id)
                : null;
        if (edit != null
            && (!edit.has("semesterID") || edit.optString("semesterID").equals(current))) {
          if (edit.optBoolean("cancelled")) continue;
          s.put("date", edit.getString("date"))
              .put("time", edit.getString("start") + " – " + edit.getString("end"));
          if (!edit.optString("title").isEmpty()) s.put("subject", edit.getString("title"));
        }
        out.add(s);
      }
    for (String key : records.keySet())
      if (key.startsWith("study:override:")) {
        JSONObject edit = Snapshot.object(records, key);
        String id = edit.optString("id");
        if (!ids.contains(id)
            && edit.optBoolean("added")
            && !edit.optBoolean("cancelled")
            && edit.optString("semesterID").equals(current))
          out.add(
              new JSONObject()
                  .put("id", id)
                  .put("date", edit.getString("date"))
                  .put("time", edit.getString("start") + " – " + edit.getString("end"))
                  .put("subject", edit.getString("title"))
                  .put("teacher", "")
                  .put("section", ""));
      }
    out.sort(
        Comparator.comparing((JSONObject s) -> s.optString("date"))
            .thenComparing(s -> start(s).toString())
            .thenComparing(s -> s.optString("id")));
    return out;
  }

  public static List<JSONObject> events(Map<String, String> records, String date) throws Exception {
    List<JSONObject> out = new ArrayList<>();
    Set<String> seen = new HashSet<>();
    JSONArray a = Snapshot.object(records, "timetable").optJSONArray("events");
    if (a != null)
      for (int i = 0; i < a.length(); i++) {
        JSONObject e = new JSONObject(a.getJSONObject(i).toString());
        if (!date.equals(e.optString("date"))) continue;
        String title = e.optString("title").trim().replaceAll("\\s+", " ");
        String upper = title.toUpperCase(Locale.ROOT);
        boolean allDay =
            upper.contains("END TERM")
                || upper.contains("END-TERM")
                || upper.contains("HOLIDAY")
                || upper.contains("VACATION")
                || upper.contains("MID TERM");
        String key = allDay ? upper : title + e.optString("time");
        if (seen.add(key)) {
          if (allDay) e.put("time", "All day");
          out.add(e);
        }
      }
    for (String key : records.keySet())
      if (key.startsWith("event:")) {
        JSONObject e = Snapshot.object(records, key);
        if (date.equals(e.optString("date"))) {
          e.put("time", e.optString("start") + " – " + e.optString("end"));
          out.add(e);
        }
      }
    return out;
  }

  public static LocalTime start(JSONObject s) {
    return clock(s.optString("time"), 0);
  }

  public static LocalTime end(JSONObject s) {
    return clock(s.optString("time"), 1);
  }

  static LocalTime clock(String value, int index) {
    Matcher m =
        Pattern.compile("(\\d{1,2})[:.](\\d{2})\\s*(AM|PM)?", Pattern.CASE_INSENSITIVE)
            .matcher(value);
    int n = 0;
    while (m.find()) {
      if (n++ == index) {
        int hour = Integer.parseInt(m.group(1)), minute = Integer.parseInt(m.group(2));
        if (m.group(3) != null) hour = hour % 12 + (m.group(3).equalsIgnoreCase("PM") ? 12 : 0);
        try {
          return LocalTime.of(hour, minute);
        } catch (Exception ignored) {
        }
      }
    }
    return LocalTime.MIDNIGHT;
  }

  public static long instant(JSONObject s, boolean end) {
    try {
      return LocalDate.parse(s.getString("date"))
          .atTime(end ? end(s) : start(s))
          .atZone(ZONE)
          .toInstant()
          .toEpochMilli();
    } catch (Exception e) {
      return 0;
    }
  }

  public static Set<String> penalties(List<JSONObject> windows, Map<String, String> records)
      throws Exception {
    Set<String> out = new HashSet<>();
    long now = System.currentTimeMillis();
    for (int i = 0; i < windows.size(); i++) {
      JSONObject s = windows.get(i);
      JSONObject proof = Snapshot.object(records, "study:proof:" + s.optString("id"));
      if (instant(s, true) > now
          || proof.optBoolean("officialDuty")
          || !proof.has("fingerprint")
          || !proof.has("signedSheet")
          || proof.optBoolean("fingerprint") == proof.optBoolean("signedSheet")) continue;
      for (int j = i + 1; j < Math.min(i + 4, windows.size()); j++)
        out.add(windows.get(j).optString("id"));
    }
    return out;
  }

  public static String status(JSONObject s, Map<String, String> records, Set<String> penalties)
      throws Exception {
    String id = s.optString("id");
    String old =
        records.containsKey("attendance:" + id)
            ? new JSONTokener(Snapshot.text(records, "attendance:" + id)).nextValue().toString()
            : "Unmarked";
    JSONObject p = Snapshot.object(records, "study:proof:" + id);
    if (p.optBoolean("officialDuty") || old.equals("OD")) return "OD";
    if (penalties.contains(id)) return "Missed";
    if (p.has("attended") && !p.optBoolean("attended")) return "Missed";
    if (p.optBoolean("attended") && p.optBoolean("fingerprint") && p.optBoolean("signedSheet"))
      return "Attended";
    if (instant(s, true) <= System.currentTimeMillis()
        && p.has("fingerprint")
        && p.has("signedSheet")
        && (!p.optBoolean("fingerprint") || !p.optBoolean("signedSheet"))) return "Missed";
    return old;
  }
}
