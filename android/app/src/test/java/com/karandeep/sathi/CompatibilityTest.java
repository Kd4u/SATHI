package com.karandeep.sathi;

import static org.junit.Assert.*;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.zip.*;
import org.json.*;
import org.junit.Test;

public class CompatibilityTest {
  String value(String text) throws Exception {
    return Snapshot.value(new JSONObject().put("text", text));
  }

  @Test
  public void fingerprintAndSheetMergeAcrossDevicesAndKeepRealDisagreements() throws Exception {
    String key = "study:proof:class1";
    String base = Snapshot.value(new JSONObject().put("officialDuty",false).put("updatedAt",1));
    String finger = Snapshot.value(new JSONObject().put("officialDuty",false).put("fingerprint",true).put("updatedAt",2));
    String signed = Snapshot.value(new JSONObject().put("officialDuty",false).put("signedSheet",true).put("updatedAt",3));
    Snapshot.Exchange exchange = Snapshot.exchange(Map.of(key,base), Map.of(key,finger), Map.of(key,signed), null);
    JSONObject proof = Snapshot.object(exchange.cloud,key);
    assertTrue(exchange.conflicts.isEmpty());
    assertTrue(proof.getBoolean("fingerprint")); assertTrue(proof.getBoolean("signedSheet")); assertTrue(proof.getBoolean("attended"));
    String no = Snapshot.value(new JSONObject().put("officialDuty",false).put("fingerprint",false).put("updatedAt",3));
    assertTrue(Snapshot.exchange(Map.of(key,base), Map.of(key,finger), Map.of(key,no), null).conflicts.contains(key));
    assertTrue(Snapshot.sameRecords(exchange.cloud, Snapshot.merge(Map.of(key,base), Map.of(key,finger), Map.of(key,signed))));
  }

  @Test
  public void verifiedLegacySupplementCannotRegressAndDoesNotUndoCancellations() throws Exception {
    JSONObject one = session("c1", "2026-11-01", 9).put("source", "Sheet1!C2");
    JSONObject two = session("j1", "2026-11-01", 21).put("source", "Sheet1!J2");
    JSONObject old = new JSONObject().put("sessions", new JSONArray().put(one)).put("subjects", new JSONArray()).put("events", new JSONArray());
    JSONObject complete = new JSONObject(old.toString()).put("sessions", new JSONArray().put(one).put(two)).put("importRevision", 2);
    String legacy = Snapshot.value(old), full = Snapshot.value(complete);
    Snapshot.Exchange plan = Snapshot.exchange(Map.of(), Map.of("timetable", full), Map.of("timetable", legacy), null);
    assertEquals(full, plan.cloud.get("timetable"));
    assertEquals(full, plan.local.get("timetable"));
    old.put("importRevision", 2);
    assertNull(Snapshot.completeTimetable(Snapshot.value(old), full));
  }

  @Test
  public void odSyncsEvenWhenTimetableConflicts() throws Exception {
    String old = reportRecord("old"), mine = reportRecord("mine"), cloud = reportRecord("cloud");
    String od = Base64.getEncoder().encodeToString("\"OD\"".getBytes(StandardCharsets.UTF_8));
    Map<String, String> base = Map.of("timetable", old);
    Map<String, String> local = Map.of("timetable", mine, "attendance:class1", od);
    Snapshot.Exchange plan = Snapshot.exchange(base, local, Map.of("timetable", cloud), null);
    assertEquals(od, plan.cloud.get("attendance:class1"));
    assertEquals(mine, plan.local.get("timetable"));
    assertEquals(old, plan.checkpoint.get("timetable"));
    Snapshot.Exchange retry = Snapshot.exchange(plan.checkpoint, plan.local, plan.cloud, null);
    assertEquals(plan.cloud, retry.cloud);
    assertEquals(plan.local, retry.local);
  }

  String reportRecord(String name) throws Exception {
    return Snapshot.value(new JSONObject().put("workbook",name).put("sessions",new JSONArray())
      .put("subjects",new JSONArray()).put("events",new JSONArray()));
  }

  @Test
  public void explicitResolutionPreservesIndependentEdits() throws Exception {
    Map<String, String> base = Map.of("a", value("old"), "b", value("old"));
    Map<String, String> local = Map.of("a", value("mine"), "b", value("old"));
    Map<String, String> remote = Map.of("a", value("cloud"), "b", value("independent"));
    assertEquals(value("mine"), Snapshot.merge(base, local, remote, true).get("a"));
    assertEquals(value("independent"), Snapshot.merge(base, local, remote, true).get("b"));
    assertEquals(remote, Snapshot.merge(base, local, remote, false));
  }

  @Test
  public void jsonKeyOrderDoesNotInventAConflict() throws Exception {
    String a = Base64.getEncoder().encodeToString("{\"a\":1,\"b\":2}".getBytes(StandardCharsets.UTF_8));
    String b = Base64.getEncoder().encodeToString("{\"b\":2,\"a\":1}".getBytes(StandardCharsets.UTF_8));
    String remote = value("real edit");
    assertEquals(remote, Snapshot.merge(Map.of("x", a), Map.of("x", b), Map.of("x", remote)).get("x"));
    assertEquals(a, Snapshot.merge(Map.of(), Map.of("x", a), Map.of("x", b)).get("x"));
  }

  @Test
  public void swiftWireRoundTripPreservesUnknownRecords() throws Exception {
    Map<String, String> records =
        new TreeMap<>(
            Map.of(
                "future:record",
                value("हिन्दी and notes"),
                "attendance:Sheet1-C4-0",
                Base64.getEncoder()
                    .encodeToString("\"Attended\"".getBytes(StandardCharsets.UTF_8))));
    assertEquals(records, Snapshot.decode(Snapshot.encode(records)));
    assertEquals("\"Attended\"", Snapshot.text(records, "attendance:Sheet1-C4-0"));
  }

  @Test
  public void mergeRetainsOtherDeviceChangesAndDeletion() throws Exception {
    Map<String, String> base = Map.of("a", value("original"), "b", value("delete"));
    Map<String, String> local = Map.of("a", value("edited"));
    Map<String, String> remote = new TreeMap<>(base);
    remote.put("c", value("other phone"));
    Map<String, String> merged = Snapshot.merge(base, local, remote);
    assertFalse(merged.containsKey("b"));
    assertEquals(local.get("a"), merged.get("a"));
    assertEquals(remote.get("c"), merged.get("c"));
  }

  @Test
  public void conflictingDeviceEditsNeverSilentlyWin() throws Exception {
    try {
      Snapshot.merge(
          Map.of("a", value("base")), Map.of("a", value("local")), Map.of("a", value("remote")));
      fail("Expected conflict");
    } catch (Exception e) {
      assertTrue(e.getMessage().contains("Both devices changed"));
    }
  }

  @Test
  public void localEditsDuringSyncStayQueued() throws Exception {
    Map<String, String> captured = Map.of("a", value("before"));
    Map<String, String> current = Map.of("a", value("typing"));
    Map<String, String> merged = new TreeMap<>(captured);
    merged.put("b", value("remote"));
    Map<String, String> next = Snapshot.merge(captured, current, merged);
    assertEquals(current.get("a"), next.get("a"));
    assertEquals(merged.get("b"), next.get("b"));
  }

  JSONObject session(String id, String date, int hour) throws Exception {
    return new JSONObject()
        .put("id", id)
        .put("date", date)
        .put("time", hour + ":00 – " + (hour + 1) + ":00")
        .put("subject", "Course")
        .put("section", "");
  }

  @Test
  public void attendanceRulesMatchAppleIncludingThreeClassPenaltyAndOD() throws Exception {
    List<JSONObject> sessions = new ArrayList<>();
    for (int i = 0; i < 5; i++) sessions.add(session("s" + i, "2020-01-01", 8 + i));
    Map<String, String> records = new TreeMap<>();
    records.put(
        "study:proof:s0",
        Snapshot.value(
            new JSONObject()
                .put("attended", true)
                .put("fingerprint", true)
                .put("signedSheet", false)));
    assertTrue(Schedule.penalties(sessions, records).isEmpty());
    assertEquals("Attended", Schedule.status(sessions.get(0), records, Set.of()));
    records.put("study:preferences", Snapshot.value(new JSONObject().put("proofCrosscheck", true)));
    Set<String> penalties = Schedule.penalties(sessions, records);
    assertEquals(Set.of("s1", "s2", "s3"), penalties);
    assertEquals("Missed", Schedule.status(sessions.get(0), records, penalties));
    assertEquals("Unmarked", Schedule.status(sessions.get(4), records, penalties));
    records.put("study:proof:s1", Snapshot.value(new JSONObject().put("officialDuty", true)));
    assertEquals("OD", Schedule.status(sessions.get(1), records, penalties));
  }

  @Test
  public void manualSelectionOverridesElectivesAndRetainsStableIDs() throws Exception {
    Map<String, String> records = new TreeMap<>();
    JSONArray sessions = new JSONArray().put(session("a", "2026-11-01", 9)).put(session("b", "2026-11-02", 10));
    records.put("timetable", Snapshot.value(new JSONObject().put("sessions", sessions)));
    records.put("selection", Snapshot.value(new JSONObject().put("semester", 5).put("keys", new JSONArray())));
    records.put("study:semesters", Snapshot.value(new JSONObject().put("current", "term")));
    records.put("study:preferences", Snapshot.value(new JSONObject().put("manualSelections", new JSONObject().put("term", new JSONArray().put("b")))));
    List<JSONObject> chosen = Schedule.classes(records);
    assertEquals(1, chosen.size()); assertEquals("b", chosen.get(0).getString("id"));
  }

  @Test
  public void examDayIsOneEventNotEight() throws Exception {
    JSONArray events = new JSONArray();
    for (int i = 0; i < 8; i++)
      events.put(
          new JSONObject()
              .put("date", "2026-10-27")
              .put("time", (8 + i) + ":00")
              .put("title", "END TERM EXAMINATIONS"));
    Map<String, String> records =
        Map.of(
            "timetable",
            Snapshot.value(
                new JSONObject()
                    .put("sessions", new JSONArray())
                    .put("subjects", new JSONArray())
                    .put("events", events)));
    assertEquals(1, Schedule.events(records, "2026-10-27").size());
    assertEquals("All day", Schedule.events(records, "2026-10-27").get(0).getString("time"));
  }

  @Test
  public void xlsxParserRetainsSwiftCellIdentifiersAndSeparatesEvents() throws Exception {
    Map<String, String> files = new LinkedHashMap<>();
    files.put(
        "xl/workbook.xml",
        "<workbook xmlns:r='urn:relationships'><sheets><sheet name='Section A'"
            + " r:id='rId1'/></sheets></workbook>");
    files.put(
        "xl/_rels/workbook.xml.rels",
        "<Relationships><Relationship Id='rId1' Target='worksheets/sheet1.xml'/></Relationships>");
    files.put(
        "xl/worksheets/sheet1.xml",
        "<worksheet><sheetData><row r='1'>"
            + cell("A1", "Date")
            + cell("B1", "Day")
            + cell("C1", "09:00-10:30")
            + cell("D1", "21:15")
            + "</row><row r='2'>"
            + cell("A2", "2026-10-27")
            + cell("B2", "Tuesday")
            + cell("C2", "Course (Sec A) - 1")
            + cell("D2", "Course (Sec A) - 2")
            + "</row><row r='3'>"
            + cell("C3", "Prof. Example")
            + cell("D3", "Prof. Example")
            + "</row><row r='4'>"
            + cell("A4", "2026-10-28")
            + cell("C4", "END TERM EXAMINATIONS")
            + "</row></sheetData></worksheet>");
    ByteArrayOutputStream bytes = new ByteArrayOutputStream();
    try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
      for (String name : files.keySet()) {
        zip.putNextEntry(new ZipEntry(name));
        zip.write(files.get(name).getBytes(StandardCharsets.UTF_8));
        zip.closeEntry();
      }
    }
    JSONObject report = ExcelImport.read(bytes.toByteArray(), "fixture.xlsx");
    JSONObject s = report.getJSONArray("sessions").getJSONObject(0);
    assertEquals("Sheet1-C2-0", s.getString("id"));
    assertEquals("Course", s.getString("subject"));
    assertEquals("A", s.getString("section"));
    assertEquals(1, report.getJSONArray("events").length());
    assertEquals(2, report.getJSONArray("sessions").length());
    assertEquals("21:15-22:45", report.getJSONArray("sessions").getJSONObject(1).getString("time"));
    assertEquals("Course", report.getJSONArray("sessions").getJSONObject(1).getString("subject"));
  }

  String cell(String address, String value) {
    return "<c r='" + address + "' t='inlineStr'><is><t>" + value + "</t></is></c>";
  }
}
