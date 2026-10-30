package com.karandeep.sathi;

import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

/** Wire format shared with Swift's [String: Data]; preserve unknown records byte for byte. */
public final class Snapshot {
  public static Map<String, String> decode(byte[] bytes) throws Exception {
    JSONObject records =
        new JSONObject(new String(bytes, StandardCharsets.UTF_8)).getJSONObject("records");
    Map<String, String> result = new TreeMap<>();
    Iterator<String> keys = records.keys();
    while (keys.hasNext()) {
      String key = keys.next(), data = records.getString(key);
      Base64.getDecoder().decode(data);
      result.put(key, data);
    }
    validate(result);
    return result;
  }

  public static byte[] encode(Map<String, String> records) throws Exception {
    JSONObject values = new JSONObject();
    for (String key : new TreeSet<>(records.keySet())) values.put(key, records.get(key));
    return new JSONObject().put("records", values).toString().getBytes(StandardCharsets.UTF_8);
  }

  static boolean equivalent(String a, String b) {
    if (Objects.equals(a, b)) return true;
    if (a == null || b == null) return false;
    try {
      Object left = new JSONTokener(new String(Base64.getDecoder().decode(a), StandardCharsets.UTF_8)).nextValue();
      Object right = new JSONTokener(new String(Base64.getDecoder().decode(b), StandardCharsets.UTF_8)).nextValue();
      return jsonEqual(left, right);
    } catch (Exception e) { return false; }
  }

  private static boolean jsonEqual(Object a, Object b) throws Exception {
    if (a instanceof JSONObject && b instanceof JSONObject) {
      JSONObject x = (JSONObject) a, y = (JSONObject) b;
      if (x.length() != y.length()) return false;
      Iterator<String> keys = x.keys();
      while (keys.hasNext()) {
        String key = keys.next();
        if (!y.has(key) || !jsonEqual(x.get(key), y.get(key))) return false;
      }
      return true;
    }
    if (a instanceof JSONArray && b instanceof JSONArray) {
      JSONArray x = (JSONArray) a, y = (JSONArray) b;
      if (x.length() != y.length()) return false;
      for (int i = 0; i < x.length(); i++) if (!jsonEqual(x.get(i), y.get(i))) return false;
      return true;
    }
    if (a instanceof Number && b instanceof Number)
      return new java.math.BigDecimal(a.toString()).compareTo(new java.math.BigDecimal(b.toString())) == 0;
    return Objects.equals(a, b);
  }

  public static boolean sameRecords(Map<String, String> a, Map<String, String> b) {
    if (!a.keySet().equals(b.keySet())) return false;
    for (String key : a.keySet()) if (!equivalent(a.get(key), b.get(key))) return false;
    return true;
  }

  static String completeTimetable(String a, String b) {
    if (a == null || b == null) return null;
    try {
      JSONObject left = new JSONObject(new String(Base64.getDecoder().decode(a), StandardCharsets.UTF_8));
      JSONObject right = new JSONObject(new String(Base64.getDecoder().decode(b), StandardCharsets.UTF_8));
      JSONArray x = left.getJSONArray("sessions"), y = right.getJSONArray("sessions");
      if (x.length() == 0 || y.length() == 0 || x.length() == y.length()) return null;
      JSONObject newer = x.length() > y.length() ? left : right, older = x.length() > y.length() ? right : left;
      if (newer.optInt("importRevision",0) < 2 || older.optInt("importRevision",0) >= 2) return null;
      JSONArray more = x.length() > y.length() ? x : y, less = x.length() > y.length() ? y : x;
      Map<String, JSONObject> index = new HashMap<>();
      for (int i = 0; i < more.length(); i++) {
        JSONObject row = more.getJSONObject(i);
        if (index.put(row.getString("id"), row) != null) return null;
      }
      for (int i = 0; i < less.length(); i++) {
        JSONObject old = less.getJSONObject(i), next = index.get(old.getString("id"));
        if (next == null) return null;
        for (String field : List.of("id", "date", "time", "subject", "section", "source"))
          if (!old.has(field) || !next.has(field) || !old.getString(field).equals(next.getString(field))) return null;
      }
      return x.length() > y.length() ? a : b;
    } catch (Exception e) { return null; }
  }

  public static final class Exchange {
    public final Map<String, String> cloud, local, checkpoint;
    public final Set<String> conflicts;
    Exchange(Map<String, String> cloud, Map<String, String> local,
             Map<String, String> checkpoint, Set<String> conflicts) {
      this.cloud = cloud; this.local = local; this.checkpoint = checkpoint; this.conflicts = conflicts;
    }
  }

  public static Exchange exchange(Map<String, String> base, Map<String, String> local,
                                  Map<String, String> remote, Boolean preferLocal) throws Exception {
    String complete = completeTimetable(local.get("timetable"), remote.get("timetable"));
    if (complete != null) {
      local = new TreeMap<>(local); remote = new TreeMap<>(remote);
      local.put("timetable", complete); remote.put("timetable", complete);
    }
    if (preferLocal != null) {
      Map<String, String> merged = merge(base, local, remote, preferLocal);
      return new Exchange(merged, merged, merged, Set.of());
    }
    Set<String> changed = new HashSet<>(base.keySet()); changed.addAll(local.keySet());
    for (String key : new HashSet<>(changed)) if (equivalent(base.get(key), local.get(key))) changed.remove(key);
    Set<String> blocked = new TreeSet<>();
    for (String key : changed)
      if (!equivalent(remote.get(key), base.get(key)) && !equivalent(remote.get(key), local.get(key))) blocked.add(key);
    if (blocked.contains("timetable")) blocked.addAll(List.of("timetable", "selection", "study:semesters", "study:preferences"));
    Map<String, String> cloud = new TreeMap<>(remote);
    for (String key : changed) if (!blocked.contains(key)) copyRecord(cloud, local, key);
    Map<String, String> applied = new TreeMap<>(cloud), checkpoint = new TreeMap<>(cloud);
    for (String key : blocked) { copyRecord(applied, local, key); copyRecord(checkpoint, base, key); }
    validate(cloud); validate(applied);
    return new Exchange(cloud, applied, checkpoint, blocked);
  }

  private static void copyRecord(Map<String, String> into, Map<String, String> from, String key) {
    if (from.containsKey(key)) into.put(key, from.get(key)); else into.remove(key);
  }

  public static Map<String, String> merge(
      Map<String, String> base, Map<String, String> local, Map<String, String> remote)
      throws Exception {
    return merge(base, local, remote, null);
  }

  public static Map<String, String> merge(
      Map<String, String> base, Map<String, String> local, Map<String, String> remote,
      Boolean preferLocal) throws Exception {
    Map<String, String> result = new TreeMap<>(remote);
    Set<String> keys = new HashSet<>(base.keySet());
    keys.addAll(local.keySet());
    for (String key : keys) {
      String before = base.get(key), after = local.get(key), cloud = remote.get(key);
      if (equivalent(before, after)) continue;
      if (!equivalent(cloud, before) && !equivalent(cloud, after)) {
        if (preferLocal != null) {
          if (preferLocal) {
            if (after == null) result.remove(key); else result.put(key, after);
          }
          continue;
        }
        throw new Exception(
            "Both devices changed "
                + key
                + ". Your local copy is safe. Sync from the other device or export a backup before"
                + " resolving this conflict.");
      }
      if (after == null) result.remove(key);
      else result.put(key, after);
    }
    if (preferLocal != null && !equivalent(base.get("timetable"), local.get("timetable"))
        && !equivalent(remote.get("timetable"), base.get("timetable"))
        && !equivalent(remote.get("timetable"), local.get("timetable"))) {
      Map<String, String> source = preferLocal ? local : remote;
      for (String related : List.of("timetable", "selection", "study:semesters", "study:preferences")) {
        if (source.containsKey(related)) result.put(related, source.get(related)); else result.remove(related);
      }
    }
    validate(result);
    return result;
  }

  public static void validate(Map<String, String> data) throws Exception {
    if (data.containsKey("timetable")) {
      JSONObject report = object(data, "timetable");
      report.getJSONArray("sessions");
      report.getJSONArray("events");
      report.getJSONArray("subjects");
    }
    if (encodeUnchecked(data).length >= 900000)
      throw new Exception(
          "Timetable exceeds the shared cloud size limit. Your saved copy is safe.");
  }

  private static byte[] encodeUnchecked(Map<String, String> data) {
    return data.toString().getBytes(StandardCharsets.UTF_8);
  }

  public static String text(Map<String, String> data, String key) {
    String value = data.get(key);
    return value == null
        ? "{}"
        : new String(Base64.getDecoder().decode(value), StandardCharsets.UTF_8);
  }

  public static JSONObject object(Map<String, String> data, String key) throws Exception {
    return new JSONObject(text(data, key));
  }

  public static String value(Object value) {
    return Base64.getEncoder()
        .encodeToString(
            (value instanceof String ? JSONObject.quote((String) value) : value.toString())
                .getBytes(StandardCharsets.UTF_8));
  }

  public static double swiftNow() {
    return System.currentTimeMillis() / 1000.0 - 978307200;
  }
}
