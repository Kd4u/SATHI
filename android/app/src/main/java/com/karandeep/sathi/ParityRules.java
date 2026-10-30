package com.karandeep.sathi;

import java.util.*;
import org.json.*;

/** Shared-schema operations, independent of Android views and network. */
public final class ParityRules {
  static final String[] IDENTITY = {"id", "date", "time", "subject", "section", "source"};

  public static JSONObject normaliseProof(JSONObject source) throws Exception {
    JSONObject result = new JSONObject(source.toString());
    if (!result.has("officialDuty")) result.put("officialDuty", false);
    if (!result.has("updatedAt")) result.put("updatedAt", Snapshot.swiftNow());
    return result;
  }

  public static String key(JSONObject row) {
    return row.optString("subject") + "|" + row.optString("section");
  }

  public static boolean containsAll(JSONObject complete, JSONObject prior) throws Exception {
    JSONArray incoming = complete.getJSONArray("sessions"), old = prior.getJSONArray("sessions");
    Map<String, JSONObject> index = new HashMap<>();
    for (int i = 0; i < incoming.length(); i++) {
      JSONObject r = incoming.getJSONObject(i);
      if (index.put(r.getString("id"), r) != null) return false;
    }
    if (old.length() == 0) return false;
    for (int i = 0; i < old.length(); i++) {
      JSONObject row = old.getJSONObject(i), other = index.get(row.getString("id"));
      if (other == null) return false;
      for (String f : IDENTITY) if (!row.optString(f).equals(other.optString(f))) return false;
    }
    return true;
  }

  public static JSONArray subjects(JSONArray rows) throws Exception {
    Map<String, List<JSONObject>> groups = new TreeMap<>();
    for (int i = 0; i < rows.length(); i++) {
      JSONObject r = rows.getJSONObject(i);
      groups.computeIfAbsent(key(r), v -> new ArrayList<>()).add(r);
    }
    JSONArray result = new JSONArray();
    for (String key : groups.keySet()) {
      List<JSONObject> list = groups.get(key);
      JSONObject r = list.get(0);
      int n = list.size();
      double credits = n == 20 ? 3 : n == 15 ? 2.25 : n == 10 ? 1.5 : n == 7 ? 1 : 0;
      result.put(
          new JSONObject()
              .put("key", key)
              .put(
                  "name",
                  r.getString("subject")
                      + (r.optString("section").isEmpty()
                          ? ""
                          : " (Sec " + r.getString("section") + ")"))
              .put("count", n)
              .put("credits", credits));
    }
    return result;
  }

  public static Map<String, Integer> ordinals(Map<String, String> records) throws Exception {
    Set<String> selected = new HashSet<>();
    for (JSONObject r : Schedule.classes(records)) selected.add(r.getString("id"));
    JSONArray raw = Snapshot.object(records, "timetable").optJSONArray("sessions");
    Map<String, List<JSONObject>> groups = new TreeMap<>();
    if (raw != null)
      for (int i = 0; i < raw.length(); i++) {
        JSONObject r = raw.getJSONObject(i);
        if (selected.contains(r.optString("id")))
          groups.computeIfAbsent(key(r), v -> new ArrayList<>()).add(r);
      }
    Map<String, Integer> result = new HashMap<>();
    for (List<JSONObject> list : groups.values()) {
      list.sort(
          Comparator.comparingLong((JSONObject r) -> Schedule.instant(r, false))
              .thenComparing(r -> r.optString("id")));
      for (int i = 0; i < list.size(); i++) result.put(list.get(i).getString("id"), i + 1);
    }
    return result;
  }

  public static JSONObject archive(Map<String, String> records) throws Exception {
    JSONObject selection = Snapshot.object(records, "selection"),
        index = Snapshot.object(records, "study:semesters"),
        prefs = Snapshot.object(records, "study:preferences");
    JSONObject attendance = new JSONObject(),
        proofs = new JSONObject(),
        overrides = new JSONObject();
    JSONArray events = new JSONArray(), chosen = new JSONArray();
    for (JSONObject r : Schedule.classes(records)) chosen.put(r.getString("id"));
    for (String key : records.keySet()) {
      if (key.startsWith("attendance:"))
        attendance.put(key.substring(11), new JSONTokener(Snapshot.text(records, key)).nextValue());
      if (key.startsWith("study:proof:"))
        proofs.put(key.substring(12), Snapshot.object(records, key));
      if (key.startsWith("study:override:"))
        overrides.put(key.substring(15), Snapshot.object(records, key));
      if (key.startsWith("event:")) events.put(Snapshot.object(records, key));
    }
    return new JSONObject()
        .put("report", Snapshot.object(records, "timetable"))
        .put("number", selection.optInt("semester", 1))
        .put(
            "selectedKeys",
            selection.optJSONArray("keys") == null
                ? new JSONArray()
                : selection.getJSONArray("keys"))
        .put("attendance", attendance)
        .put("proofRecords", proofs)
        .put("overrides", overrides)
        .put("semesterID", index.optString("current"))
        .put("section", prefs.optString("firstYearSection"))
        .put("customEvents", events)
        .put("minimumAttendance", selection.optInt("minimumAttendance", 80))
        .put("selectedSessionIDs", chosen);
  }

  public static Map<String, String> archivedRecords(JSONObject archive) throws Exception {
    Map<String, String> r = new TreeMap<>();
    r.put("timetable", Snapshot.value(archive.getJSONObject("report")));
    r.put(
        "selection",
        Snapshot.value(
            new JSONObject()
                .put("semester", archive.optInt("number", 1))
                .put("keys", archive.getJSONArray("selectedKeys"))));
    r.put(
        "study:semesters",
        Snapshot.value(
            new JSONObject()
                .put("current", archive.getString("semesterID"))
                .put("semesters", new JSONArray())));
    JSONObject prefs =
        new JSONObject()
            .put("firstYearSection", archive.optString("section"))
            .put("programme", "MBA");
    if (archive.has("selectedSessionIDs"))
      prefs.put(
          "manualSelections",
          new JSONObject()
              .put(archive.getString("semesterID"), archive.getJSONArray("selectedSessionIDs")));
    r.put("study:preferences", Snapshot.value(prefs));
    for (String group : new String[] {"attendance", "proofRecords", "overrides"}) {
      JSONObject values = archive.optJSONObject(group);
      if (values == null) continue;
      Iterator<String> keys = values.keys();
      while (keys.hasNext()) {
        String id = keys.next();
        String prefix =
            group.equals("attendance")
                ? "attendance:"
                : group.equals("proofRecords") ? "study:proof:" : "study:override:";
        r.put(prefix + id, Snapshot.value(values.get(id)));
      }
    }
    JSONArray events = archive.optJSONArray("customEvents");
    if (events != null)
      for (int i = 0; i < events.length(); i++) {
        JSONObject e = events.getJSONObject(i);
        r.put("event:" + e.getString("id"), Snapshot.value(e));
      }
    return r;
  }

  public static JSONObject appendProgramme(JSONObject existing, JSONObject incoming, String course)
      throws Exception {
    JSONObject result = new JSONObject(existing.toString());
    JSONArray rows = result.getJSONArray("sessions");
    Set<String> seen = new HashSet<>();
    for (int i = 0; i < rows.length(); i++) {
      JSONObject r = rows.getJSONObject(i);
      seen.add(
          r.optString("date")
              + "|"
              + r.optString("time")
              + "|"
              + key(r)
              + "|"
              + Schedule.programme(r.optString("source")));
    }
    JSONArray more = incoming.getJSONArray("sessions");
    boolean tagged = false;
    for (int i = 0; i < more.length(); i++)
      if (Schedule.programme(more.getJSONObject(i).optString("source")).equals(course))
        tagged = true;
    for (int i = 0; i < more.length(); i++) {
      JSONObject r = new JSONObject(more.getJSONObject(i).toString());
      if (tagged && !Schedule.programme(r.optString("source")).equals(course)) continue;
      String identity =
          r.optString("date") + "|" + r.optString("time") + "|" + key(r) + "|" + course;
      if (!seen.add(identity)) continue;
      r.put("id", course + "-" + r.getString("id"))
          .put("source", course + " / " + r.optString("source"));
      rows.put(r);
    }
    JSONArray events = result.optJSONArray("events");
    if (events == null) events = new JSONArray();
    JSONArray incomingEvents = incoming.optJSONArray("events");
    if (incomingEvents != null)
      for (int i = 0; i < incomingEvents.length(); i++) {
        JSONObject e = new JSONObject(incomingEvents.getJSONObject(i).toString());
        e.put("source", course + " / " + e.optString("source"));
        events.put(e);
      }
    return result
        .put("sessions", rows)
        .put("subjects", subjects(rows))
        .put("events", events)
        .put("importRevision", 2);
  }
}
