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

  public static Map<String, String> merge(
      Map<String, String> base, Map<String, String> local, Map<String, String> remote)
      throws Exception {
    Map<String, String> result = new TreeMap<>(remote);
    Set<String> keys = new HashSet<>(base.keySet());
    keys.addAll(local.keySet());
    for (String key : keys) {
      String before = base.get(key), after = local.get(key), cloud = remote.get(key);
      if (Objects.equals(before, after)) continue;
      if (!Objects.equals(cloud, before) && !Objects.equals(cloud, after))
        throw new Exception(
            "Both devices changed "
                + key
                + ". Your local copy is safe. Sync from the other device or export a backup before"
                + " resolving this conflict.");
      if (after == null) result.remove(key);
      else result.put(key, after);
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
