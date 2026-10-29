package com.karandeep.sathi;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.time.format.*;
import java.util.*;
import java.util.regex.*;
import java.util.zip.*;
import javax.xml.parsers.*;
import org.json.*;
import org.w3c.dom.*;

/** Same date/day/time headers, professor pairing and stable cell IDs as TimetableLogic.swift. */
public final class ExcelImport {
  static final Pattern TIME = Pattern.compile("\\d{1,2}[:.]\\d{2}\\s*[-–—]\\s*\\d{1,2}[:.]\\d{2}");
  static final Pattern SECTION =
      Pattern.compile("(?i)\\(\\s*sec(?:tion)?\\s*[-:]?\\s*([A-Z])\\s*\\)");
  static final Pattern SECTION_LABEL =
      Pattern.compile("(?i)\\bsec(?:tion)?\\.?\\s*[-:]?\\s*([A-Z])\\b");

  public static JSONObject read(byte[] input, String name) throws Exception {
    Map<String, byte[]> zip = new HashMap<>();
    int total = 0;
    try (ZipInputStream in = new ZipInputStream(new ByteArrayInputStream(input))) {
      ZipEntry entry;
      while ((entry = in.getNextEntry()) != null) {
        if (entry.isDirectory()) continue;
        if (zip.size() > 2000) throw new Exception("Workbook has too many entries");
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int n;
        while ((n = in.read(buffer)) != -1) {
          total += n;
          if (total > 100000000) throw new Exception("Workbook is too large when expanded");
          out.write(buffer, 0, n);
        }
        zip.put(entry.getName(), out.toByteArray());
      }
    }
    List<String> strings = new ArrayList<>();
    if (zip.containsKey("xl/sharedStrings.xml")) {
      NodeList items = xml(zip.get("xl/sharedStrings.xml")).getElementsByTagName("si");
      for (int i = 0; i < items.getLength(); i++) {
        NodeList text = ((Element) items.item(i)).getElementsByTagName("t");
        StringBuilder s = new StringBuilder();
        for (int j = 0; j < text.getLength(); j++) s.append(text.item(j).getTextContent());
        strings.add(s.toString());
      }
    }
    Map<String, String> relationships = new HashMap<>();
    if (zip.containsKey("xl/_rels/workbook.xml.rels")) {
      NodeList rs = xml(zip.get("xl/_rels/workbook.xml.rels")).getElementsByTagName("Relationship");
      for (int i = 0; i < rs.getLength(); i++) {
        Element r = (Element) rs.item(i);
        String path = r.getAttribute("Target");
        relationships.put(
            r.getAttribute("Id"), path.startsWith("/") ? path.substring(1) : "xl/" + path);
      }
    }
    List<String> paths = new ArrayList<>(), names = new ArrayList<>();
    if (zip.containsKey("xl/workbook.xml")) {
      NodeList sheets = xml(zip.get("xl/workbook.xml")).getElementsByTagName("sheet");
      for (int i = 0; i < sheets.getLength(); i++) {
        Element s = (Element) sheets.item(i);
        String path = relationships.get(s.getAttribute("r:id"));
        if (path != null && zip.containsKey(path)) {
          paths.add(path);
          names.add(s.getAttribute("name"));
        }
      }
    }
    if (paths.isEmpty()) throw new Exception("No readable Excel worksheets found");
    JSONArray sessions = new JSONArray(), events = new JSONArray(), warnings = new JSONArray();
    for (int sheet = 0; sheet < paths.size(); sheet++) {
      String sheetName = names.get(sheet);
      TreeMap<Integer, TreeMap<Integer, Cell>> rows = new TreeMap<>();
      NodeList cells = xml(zip.get(paths.get(sheet))).getElementsByTagName("c");
      for (int i = 0; i < cells.getLength(); i++) {
        Element e = (Element) cells.item(i);
        String address = e.getAttribute("r");
        Matcher pos = Pattern.compile("([A-Z]+)(\\d+)").matcher(address);
        if (!pos.matches()) continue;
        int col = 0;
        for (char ch : pos.group(1).toCharArray()) col = col * 26 + ch - 'A' + 1;
        int row = Integer.parseInt(pos.group(2));
        String value = "";
        NodeList v = e.getElementsByTagName("v");
        if (v.getLength() > 0) value = v.item(0).getTextContent();
        String type = e.getAttribute("t");
        if (type.equals("s")) {
          int index = Integer.parseInt(value);
          if (index < 0 || index >= strings.size())
            throw new Exception("Invalid Excel shared string");
          value = strings.get(index);
        } else if (type.equals("inlineStr")) {
          NodeList ts = e.getElementsByTagName("t");
          StringBuilder s = new StringBuilder();
          for (int j = 0; j < ts.getLength(); j++) s.append(ts.item(j).getTextContent());
          value = s.toString();
        }
        if (!value.trim().isEmpty())
          rows.computeIfAbsent(row, k -> new TreeMap<>()).put(col, new Cell(address, value.trim()));
      }
      if (rows.isEmpty()) continue;
      int header = rows.firstKey();
      for (int number : rows.keySet()) {
        boolean date = false, day = false;
        for (Cell c : rows.get(number).values()) {
          if (c.text.equalsIgnoreCase("date")) date = true;
          if (c.text.equalsIgnoreCase("day")) day = true;
        }
        if (date && day) {
          header = number;
          break;
        }
      }
      int dateCol = 1, dayCol = 2;
      TreeMap<Integer, String> slots = new TreeMap<>();
      for (Map.Entry<Integer, Cell> cell : rows.get(header).entrySet()) {
        if (cell.getValue().text.equalsIgnoreCase("date")) dateCol = cell.getKey();
        if (cell.getValue().text.equalsIgnoreCase("day")) dayCol = cell.getKey();
        if (TIME.matcher(cell.getValue().text).find())
          slots.put(cell.getKey(), cell.getValue().text);
      }
      if (slots.isEmpty()) {
        warnings.put(sheetName + ": no time-slot headers detected");
        continue;
      }
      String inherited = label(sheetName);
      if (inherited.isEmpty()) {
        Set<String> sections = new HashSet<>();
        for (int r : rows.keySet())
          if (r < header)
            for (Cell cell : rows.get(r).values()) {
              String l = label(cell.text);
              if (!l.isEmpty()) sections.add(l);
            }
        if (sections.size() == 1) inherited = sections.iterator().next();
      }
      for (int row : rows.keySet()) {
        if (row <= header) continue;
        Map<Integer, Cell> cellsInRow = rows.get(row);
        String date = date(cell(cellsInRow, dateCol));
        if (date.isEmpty()) continue;
        String day = cell(cellsInRow, dayCol);
        Map<Integer, Cell> faculty = rows.getOrDefault(row + 1, new TreeMap<>());
        for (int column : slots.keySet()) {
          Cell cell = cellsInRow.get(column);
          if (cell == null) continue;
          String source = sheetName + "!" + cell.address, slot = slots.get(column);
          List<String> entries = lines(cell.text), teachers = lines(cell(faculty, column));
          if (entries.isEmpty()) continue;
          boolean hasProfessor = false, allProfessor = true;
          for (String t : teachers) if (professor(t)) hasProfessor = true;
          for (String entry : entries) if (!professor(entry)) allProfessor = false;
          if (event(cell.text) && !hasProfessor) {
            events.put(eventRow(date, slot, cell.text, source));
            continue;
          }
          if (allProfessor) {
            warnings.put(source + ": professor appears in subject row");
            continue;
          }
          for (int index = 0; index < entries.size(); index++) {
            String entry = entries.get(index), teacher = "";
            if (teachers.size() == entries.size()) teacher = teachers.get(index);
            else if (teachers.size() == 1 && professor(teachers.get(0))) teacher = teachers.get(0);
            if (event(entry) || !professor(teacher)) {
              events.put(eventRow(date, slot, entry, source));
              if (!event(entry))
                warnings.put(
                    source
                        + ": no matching professor for '"
                        + entry
                        + "' — treated as event; verify if this is a class");
              continue;
            }
            Matcher m = SECTION.matcher(entry);
            String section = inherited, subject = entry;
            if (m.find()) {
              section = m.group(1).toUpperCase(Locale.ROOT);
              subject = m.replaceFirst("").trim();
            }
            sessions.put(
                new JSONObject()
                    .put("id", "Sheet" + (sheet + 1) + "-" + cell.address + "-" + index)
                    .put("date", date)
                    .put("day", day)
                    .put("time", slot)
                    .put("subject", subject)
                    .put("section", section)
                    .put("teacher", teacher)
                    .put("source", source));
          }
        }
      }
    }
    Map<String, List<JSONObject>> grouped = new TreeMap<>();
    for (int i = 0; i < sessions.length(); i++) {
      JSONObject s = sessions.getJSONObject(i);
      grouped
          .computeIfAbsent(
              s.getString("subject") + "|" + s.getString("section"), k -> new ArrayList<>())
          .add(s);
    }
    JSONArray subjects = new JSONArray();
    for (String key : grouped.keySet()) {
      List<JSONObject> list = grouped.get(key);
      JSONObject first = list.get(0);
      int count = list.size();
      double credits =
          count == 20 ? 3 : count == 15 ? 2.25 : count == 10 ? 1.5 : count == 7 ? 1 : 0;
      subjects.put(
          new JSONObject()
              .put("key", key)
              .put(
                  "name",
                  first.getString("subject")
                      + (first.getString("section").isEmpty()
                          ? ""
                          : " (Sec " + first.getString("section") + ")"))
              .put("count", count)
              .put("credits", credits));
    }
    if (sessions.length() == 0 && events.length() == 0)
      throw new Exception(
          "No dated timetable rows found. Expected Date, Day and time-slot headers.");
    return new JSONObject()
        .put("workbook", name)
        .put("sessions", sessions)
        .put("subjects", subjects)
        .put("events", events)
        .put("warnings", warnings);
  }

  static Document xml(byte[] bytes) throws Exception {
    // Android's XML implementation does not support Xerces feature names.
    // XLSX XML is UTF-8: reject declarations/entities before the parser can use them.
    for (byte b : bytes) if (b == 0) throw new IOException("Unsupported Excel XML encoding");
    String xml = StandardCharsets.UTF_8.newDecoder()
        .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
        .decode(java.nio.ByteBuffer.wrap(bytes)).toString();
    String upper = xml.toUpperCase(Locale.ROOT);
    if (upper.contains("<!DOCTYPE") || upper.contains("<!ENTITY")) {
      throw new IOException("Workbook XML contains unsupported document declarations");
    }
    DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
    factory.setExpandEntityReferences(false);
    javax.xml.parsers.DocumentBuilder builder = factory.newDocumentBuilder();
    builder.setEntityResolver((publicId, systemId) -> {
      throw new org.xml.sax.SAXException("External workbook entities are not supported");
    });
    return builder.parse(new ByteArrayInputStream(bytes));
  }

  static String cell(Map<Integer, Cell> row, int col) {
    Cell c = row.get(col);
    return c == null ? "" : c.text;
  }

  static String label(String value) {
    String s = value.trim();
    if (s.matches("[A-Za-z]")) return s.toUpperCase(Locale.ROOT);
    Matcher m = SECTION_LABEL.matcher(s);
    return m.find() ? m.group(1).toUpperCase(Locale.ROOT) : "";
  }

  static List<String> lines(String value) {
    String normalized =
        value.replaceAll("(?i)\\(\\s*sec(?:tion)?\\s*\\n\\s*([A-Z])\\s*\\)", "(Sec $1)");
    List<String> out = new ArrayList<>();
    for (String s : normalized.split("\\R")) if (!s.trim().isEmpty()) out.add(s.trim());
    return out;
  }

  static boolean professor(String s) {
    return Pattern.compile("(?i)^\\s*(?:prof\\.?|professor)\\s+").matcher(s).find();
  }

  static boolean event(String value) {
    String s = value.toUpperCase(Locale.ROOT);
    if (s.trim().equals("ID") || s.trim().equals("OFF DAY")) return true;
    for (String key :
        new String[] {
          "QUIZ",
          "HOLIDAY",
          "INDEPENDENCE DAY",
          "REPUBLIC DAY",
          "DUSSEHRA",
          "DIWALI",
          "CHRISTMAS",
          "GANDHI JAYANTI",
          "EXAM",
          "MID TERM",
          "MID-TERM",
          "END TERM",
          "END-TERM",
          "BREAK",
          "VACATION",
          "INAUGURATION",
          "CONVOCATION",
          "NO CLASS",
          "PRESENTATION",
          "ORIENTATION",
          "INDUCTION",
          "SPORTS DAY",
          "CULTURAL DAY"
        }) if (s.contains(key)) return true;
    return false;
  }

  static JSONObject eventRow(String date, String slot, String title, String source)
      throws Exception {
    return new JSONObject()
        .put("date", date)
        .put("time", slot)
        .put("title", title)
        .put("source", source);
  }

  static String date(String value) {
    try {
      double n = Double.parseDouble(value);
      if (n > 30000 && n < 90000) return LocalDate.of(1899, 12, 30).plusDays((long) n).toString();
    } catch (Exception ignored) {
    }
    try {
      return LocalDate.parse(value).toString();
    } catch (Exception ignored) {
    }
    for (String format : new String[] {"d/M/uuuu", "d-M-uuuu", "d MMM uuuu"})
      try {
        return LocalDate.parse(
                value,
                DateTimeFormatter.ofPattern(format, Locale.ENGLISH)
                    .withResolverStyle(ResolverStyle.STRICT))
            .toString();
      } catch (Exception ignored) {
      }
    return "";
  }

  static class Cell {
    final String address, text;

    Cell(String a, String t) {
      address = a;
      text = t;
    }
  }
}
