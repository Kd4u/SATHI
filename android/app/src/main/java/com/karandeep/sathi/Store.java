package com.karandeep.sathi;

import android.content.*;
import android.util.AtomicFile;
import com.google.android.gms.tasks.Tasks;
import com.google.firebase.auth.*;
import com.google.firebase.firestore.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

public final class Store {
  private static Store shared;

  public static synchronized Store get(Context c) {
    if (shared == null) shared = new Store(c.getApplicationContext());
    return shared;
  }

  private final Context context;
  public final ExecutorService io = Executors.newSingleThreadExecutor();
  private String owner = "";
  private File folder;
  private Map<String, String> records = new TreeMap<>(), baseline = new TreeMap<>();
  private boolean busy = false;
  private long lastSync = 0;
  private boolean hasConflicts = false;
  private ListenerRegistration liveListener;
  private String listenerUID;
  private Map<String, String> lastServerSnapshot;
  public synchronized boolean hasConflicts() { return hasConflicts; }

  public synchronized void stopLiveUpdates() {
    if (liveListener != null) liveListener.remove();
    liveListener = null; listenerUID = null; lastServerSnapshot = null;
  }

  public synchronized void startLiveUpdates(Completion callback) {
    if (owner.isEmpty() || owner.equals(listenerUID)) return;
    stopLiveUpdates();
    final String uid = owner; listenerUID = uid;
    liveListener = FirebaseFirestore.getInstance().collection("users").document(uid)
      .collection("sathi").document("snapshot").addSnapshotListener((doc, error) -> {
        boolean changed = false;
        synchronized (Store.this) {
          if (!owner.equals(uid) || !uid.equals(listenerUID)) return;
          if (error != null) { callback.done("Live sync unavailable: " + error.getMessage(), false); return; }
          if (doc == null || doc.getMetadata().hasPendingWrites() || doc.getMetadata().isFromCache()) return;
          try {
            Blob payload = doc.getBlob("payload");
            if (payload == null) return;
            Map<String, String> incoming = Snapshot.decode(payload.toBytes());
            if (lastServerSnapshot != null && Snapshot.sameRecords(lastServerSnapshot, incoming)) return;
            lastServerSnapshot = incoming;
            changed = !Snapshot.sameRecords(baseline, incoming);
          } catch (Exception e) { callback.done("Live update could not be read; saved data retained", false); return; }
        }
        if (changed) callback.done("Cloud changes available", true);
      });
  }

  public interface Completion {
    void done(String message, boolean ok);
  }

  private Store(Context c) {
    context = c;
  }

  public synchronized void activate() throws Exception {
    FirebaseUser user = FirebaseAuth.getInstance().getCurrentUser();
    String uid = user == null ? "" : user.getUid();
    if (uid.equals(owner) && folder != null) return;
    if (busy) throw new Exception("A sync is finishing. Please try again in a moment.");
    stopLiveUpdates();
    hasConflicts = false;
    owner = uid;
    records = new TreeMap<>();
    baseline = new TreeMap<>();
    lastSync = 0;
    folder = null;
    if (uid.isEmpty()) return;
    byte[] digest =
        MessageDigest.getInstance("SHA-256").digest(uid.getBytes(StandardCharsets.UTF_8));
    StringBuilder hash = new StringBuilder();
    for (byte b : digest) hash.append(String.format("%02x", b));
    folder = new File(context.getFilesDir(), "Accounts/" + hash);
    if (!folder.exists() && !folder.mkdirs()) throw new IOException("Cannot open account storage");
    File local = new File(folder, "snapshot.json");
    if (local.exists()) records = Snapshot.decode(read(local));
    File base = new File(folder, "baseline.json");
    if (base.exists()) baseline = Snapshot.decode(read(base));
    lastSync = context.getSharedPreferences("sync", 0).getLong(uid, 0);
  }

  public synchronized boolean busy() {
    return busy;
  }

  public synchronized long lastSync() {
    return lastSync;
  }

  public synchronized boolean hasTimetable() {
    return records.containsKey("timetable");
  }

  public synchronized Map<String, String> copy() {
    return new TreeMap<>(records);
  }

  public synchronized JSONObject object(String key) {
    try {
      return Snapshot.object(records, key);
    } catch (Exception e) {
      return new JSONObject();
    }
  }

  public synchronized void put(String key, Object value) throws Exception {
    requireAccount();
    Map<String, String> next = new TreeMap<>(records);
    next.put(key, Snapshot.value(value));
    Snapshot.validate(next);
    atomic(new File(folder, "snapshot.json"), Snapshot.encode(next));
    records = next;
    journal("record_saved", new JSONObject().put("record", key));
  }

  public synchronized void importReport(JSONObject report, JSONArray selected, int semester)
      throws Exception {
    requireAccount();
    Map<String, String> next = new TreeMap<>(records);
    // Replacing an active term silently would orphan attendance. Explicit archive first.
    if (next.containsKey("timetable"))
      throw new Exception(
          "A timetable is already saved. Use the Apple app to archive/import the next semester,"
              + " then Sync here. Your history stays intact.");
    next.put("timetable", Snapshot.value(report));
    next.put(
        "selection",
        Snapshot.value(
            new JSONObject()
                .put("semester", semester)
                .put("keys", selected)
                .put("minimumAttendance", 80)));
    String id = UUID.randomUUID().toString().toUpperCase(Locale.ROOT);
    JSONArray sessions = report.getJSONArray("sessions");
    String start = "", end = "";
    for (int i = 0; i < sessions.length(); i++) {
      String d = sessions.getJSONObject(i).getString("date");
      if (start.isEmpty() || d.compareTo(start) < 0) start = d;
      if (end.compareTo(d) < 0) end = d;
    }
    JSONObject summary =
        new JSONObject()
            .put("id", id)
            .put("number", semester)
            .put("title", "Semester " + semester)
            .put("start", start)
            .put("end", end);
    next.put(
        "study:semesters",
        Snapshot.value(
            new JSONObject().put("current", id).put("semesters", new JSONArray().put(summary))));
    Snapshot.validate(next);
    atomic(new File(folder, "snapshot.json"), Snapshot.encode(next));
    records = next;
    journal("timetable_imported", new JSONObject().put("workbook", report.optString("workbook")));
  }

  public synchronized void journal(String action, JSONObject details) throws Exception {
    requireAccount();
    File file = new File(folder, "activity-log.json");
    JSONArray list =
        file.exists()
            ? new JSONArray(new String(read(file), StandardCharsets.UTF_8))
            : new JSONArray();
    list.put(
        new JSONObject()
            .put("id", UUID.randomUUID().toString().toUpperCase(Locale.ROOT))
            .put("timestamp", Snapshot.swiftNow())
            .put("device", "Android")
            .put("action", action)
            .put("details", details));
    atomic(file, list.toString().getBytes(StandardCharsets.UTF_8));
  }

  public void sync(Completion callback) { sync(callback, null); }

  public void sync(Completion callback, Boolean preferLocal) {
    final String uid;
    final File directory;
    final Map<String, String> local, base;
    synchronized (this) {
      try {
        activate();
        requireAccount();
        if (busy) {
          callback.done("Sync already running", false);
          return;
        }
      } catch (Exception e) {
        callback.done(e.getMessage(), false);
        return;
      }
      busy = true;
      uid = owner;
      directory = folder;
      local = new TreeMap<>(records);
      base = new TreeMap<>(baseline);
    }
    io.execute(
        () -> {
          String message = "Up to date";
          boolean success = false;
          try {
            if (!base.isEmpty() && local.isEmpty())
              throw new Exception(
                  "Local storage is unexpectedly empty. Sync stopped to protect cloud data.");
            final File conflictBackup = new File(directory, "SyncConflictBackups/" + UUID.randomUUID());
            if (preferLocal != null) {
              if (!conflictBackup.mkdirs()) throw new IOException("Could not save conflict backup");
              atomic(new File(conflictBackup, "local.json"), Snapshot.encode(local));
              atomic(new File(conflictBackup, "baseline.json"), Snapshot.encode(base));
            }
            FirebaseFirestore db = FirebaseFirestore.getInstance();
            DocumentReference ref =
                db.collection("users").document(uid).collection("sathi").document("snapshot");
            Snapshot.Exchange exchange =
                Tasks.await(
                    db.runTransaction(
                        tx -> {
                          try {
                            DocumentSnapshot doc = tx.get(ref);
                            Map<String, String> remote = new TreeMap<>();
                            if (doc.exists()) {
                              Long schema = doc.getLong("schema");
                              Blob payload = doc.getBlob("payload");
                              if (schema == null || schema != 1 || payload == null)
                                throw new Exception(
                                    "Unrecognized cloud snapshot; saved data was not replaced.");
                              remote = Snapshot.decode(payload.toBytes());
                            } else if (!base.isEmpty())
                              throw new Exception("Cloud snapshot is missing. Local data is safe.");
                            if (preferLocal != null)
                              atomic(new File(conflictBackup, "remote-" + UUID.randomUUID() + ".json"), Snapshot.encode(remote));
                            Snapshot.Exchange exchangeResult = Snapshot.exchange(base, local, remote, preferLocal);
                            byte[] bytes = Snapshot.encode(exchangeResult.cloud);
                            if (bytes.length >= 900000)
                              throw new Exception("Cloud snapshot exceeds size limit");
                            if (!doc.exists() || !Snapshot.sameRecords(exchangeResult.cloud, remote))
                              tx.set(
                                  ref,
                                  new HashMap<>(
                                      Map.of(
                                          "schema",
                                          1,
                                          "payload",
                                          Blob.fromBytes(bytes),
                                          "updatedAt",
                                          FieldValue.serverTimestamp())));
                            return exchangeResult;
                          } catch (Exception e) {
                            throw new FirebaseFirestoreException(
                                e.getMessage(), FirebaseFirestoreException.Code.ABORTED, e);
                          }
                        }),
                    45,
                    TimeUnit.SECONDS);
            byte[] mergedBytes = Snapshot.encode(exchange.checkpoint);
            synchronized (this) {
              if (!owner.equals(uid)) throw new Exception("Account changed; result ignored.");
              // Edits made during the network operation remain queued locally.
              Map<String, String> next = Snapshot.merge(local, records, exchange.local);
              atomic(new File(directory, "snapshot-before-sync.json"), Snapshot.encode(records));
              atomic(new File(directory, "snapshot.json"), Snapshot.encode(next));
              records = next;
              atomic(new File(directory, "baseline.json"), mergedBytes);
              baseline = exchange.checkpoint;
              hasConflicts = !exchange.conflicts.isEmpty();
              lastSync = System.currentTimeMillis();
              context.getSharedPreferences("sync", 0).edit().putLong(uid, lastSync).apply();
            }
            if (!exchange.conflicts.isEmpty()) message = "Other changes synced. Both devices changed " + String.join(", ", exchange.conflicts) + "; choose a version for these records.";
            uploadJournal(db, uid, directory);
            syncAssets(db, uid, directory);
            success = true;
          } catch (Exception e) {
            message =
                "Sync incomplete: "
                    + (e.getCause() == null ? e.getMessage() : e.getCause().getMessage());
          }
          synchronized (this) {
            busy = false;
          }
          ScheduleWidget.refresh(context);
          callback.done(message, success);
        });
  }

  private void uploadJournal(FirebaseFirestore db, String uid, File dir) throws Exception {
    File log = new File(dir, "activity-log.json");
    if (!log.exists()) return;
    JSONArray entries = new JSONArray(new String(read(log), StandardCharsets.UTF_8));
    File ackFile = new File(dir, "activity-uploaded.json");
    JSONArray ack =
        ackFile.exists()
            ? new JSONArray(new String(read(ackFile), StandardCharsets.UTF_8))
            : new JSONArray();
    Set<String> uploaded = new HashSet<>();
    for (int i = 0; i < ack.length(); i++) uploaded.add(ack.getString(i));
    for (int i = 0; i < entries.length(); i++) {
      JSONObject e = entries.getJSONObject(i);
      String id = e.getString("id");
      if (uploaded.contains(id)) continue;
      Tasks.await(
          db.collection("users")
              .document(uid)
              .collection("activity")
              .document(id)
              .set(
                  Map.of(
                      "payload",
                      Blob.fromBytes(e.toString().getBytes(StandardCharsets.UTF_8)),
                      "committedAt",
                      FieldValue.serverTimestamp())),
          20,
          TimeUnit.SECONDS);
      ack.put(id);
      atomic(ackFile, ack.toString().getBytes(StandardCharsets.UTF_8));
    }
  }

  public synchronized File assetsDir() throws Exception {
    requireAccount();
    File d = new File(folder, "assets");
    if (!d.exists() && !d.mkdirs()) throw new IOException("Cannot save notebooks");
    return d;
  }

  public synchronized JSONObject assetIndex() throws Exception {
    File f = new File(assetsDir(), "index.json");
    return f.exists()
        ? new JSONObject(new String(read(f), StandardCharsets.UTF_8))
        : new JSONObject();
  }

  public synchronized JSONObject asset(String id) throws Exception {
    if (!id.matches("[A-Za-z0-9_-]+")) throw new Exception("Invalid notebook ID");
    return new JSONObject(
        new String(read(new File(assetsDir(), id + ".json")), StandardCharsets.UTF_8));
  }

  public synchronized void saveAsset(
      String id, String kind, String title, String subject, JSONObject data) throws Exception {
    JSONObject index = assetIndex(), old = index.optJSONObject(id);
    String revision = UUID.randomUUID().toString().toUpperCase(Locale.ROOT);
    JSONObject metadata =
        new JSONObject()
            .put("id", id)
            .put("kind", kind)
            .put("title", title)
            .put("subject", subject)
            .put("semesterID", object("study:semesters").optString("current"))
            .put("revision", revision)
            .put("modifiedAt", Snapshot.swiftNow())
            .put("pending", true);
    if (old != null && old.has("baseRevision"))
      metadata.put("baseRevision", old.get("baseRevision"));
    atomic(new File(assetsDir(), id + ".json"), data.toString().getBytes(StandardCharsets.UTF_8));
    index.put(id, metadata);
    atomic(new File(assetsDir(), "index.json"), index.toString().getBytes(StandardCharsets.UTF_8));
  }

  private void syncAssets(FirebaseFirestore db, String uid, File dir) throws Exception {
    CollectionReference collection = db.collection("users").document(uid).collection("studyAssets");
    JSONObject outgoing;
    synchronized (this) {
      outgoing = assetIndex();
    }
    Iterator<String> keys = outgoing.keys();
    while (keys.hasNext()) {
      String id = keys.next();
      JSONObject meta = outgoing.getJSONObject(id);
      if (!meta.optBoolean("pending")) continue;
      String rev = meta.getString("revision"), base = meta.optString("baseRevision", "");
      byte[] data;
      synchronized (this) {
        data = read(new File(assetsDir(), id + ".json"));
      }
      DocumentReference ref = collection.document(id);
      DocumentSnapshot head = Tasks.await(ref.get(Source.SERVER), 20, TimeUnit.SECONDS);
      if (head.exists()
          && !Objects.equals(head.getString("revision"), base)
          && !Objects.equals(head.getString("revision"), rev))
        throw new Exception(
            "Notebook conflict: "
                + meta.optString("title")
                + ". Both copies retained; no overwrite performed.");
      int count = (data.length + 399999) / 400000;
      for (int i = 0; i < count; i++)
        Tasks.await(
            ref.collection("versions")
                .document(rev)
                .collection("chunks")
                .document("" + i)
                .set(
                    Map.of(
                        "bytes",
                        Blob.fromBytes(
                            Arrays.copyOfRange(
                                data, i * 400000, Math.min(data.length, (i + 1) * 400000))))),
            20,
            TimeUnit.SECONDS);
      Tasks.await(
          db.runTransaction(
              tx -> {
                DocumentSnapshot current = tx.get(ref);
                String revision = current.getString("revision");
                if (current.exists()
                    && !Objects.equals(revision, base)
                    && !Objects.equals(revision, rev))
                  throw new FirebaseFirestoreException(
                      "Notebook changed elsewhere", FirebaseFirestoreException.Code.ABORTED);
                tx.set(
                    ref,
                    Map.of(
                        "revision",
                        rev,
                        "metadata",
                        Blob.fromBytes(meta.toString().getBytes(StandardCharsets.UTF_8)),
                        "chunks",
                        count,
                        "committedAt",
                        FieldValue.serverTimestamp()));
                return true;
              }),
          30,
          TimeUnit.SECONDS);
      synchronized (this) {
        JSONObject index = assetIndex(), now = index.optJSONObject(id);
        if (now != null) {
          now.put("baseRevision", rev);
          if (rev.equals(now.optString("revision"))) now.put("pending", false);
          index.put(id, now);
          atomic(
              new File(assetsDir(), "index.json"),
              index.toString().getBytes(StandardCharsets.UTF_8));
        }
      }
    }
    QuerySnapshot remote = Tasks.await(collection.get(Source.SERVER), 30, TimeUnit.SECONDS);
    for (DocumentSnapshot doc : remote) {
      String id = doc.getId(), revision = doc.getString("revision");
      Blob metadata = doc.getBlob("metadata");
      Long count = doc.getLong("chunks");
      if (!id.matches("[A-Za-z0-9_-]+")
          || revision == null
          || metadata == null
          || count == null
          || count < 1
          || count >= 200) throw new Exception("Invalid cloud notebook");
      synchronized (this) {
        JSONObject old = assetIndex().optJSONObject(id);
        if (old != null
            && (revision.equals(old.optString("revision")) || old.optBoolean("pending"))) continue;
      }
      ByteArrayOutputStream bytes = new ByteArrayOutputStream();
      for (int i = 0; i < count; i++) {
        Blob chunk =
            Tasks.await(
                    doc.getReference()
                        .collection("versions")
                        .document(revision)
                        .collection("chunks")
                        .document("" + i)
                        .get(Source.SERVER),
                    20,
                    TimeUnit.SECONDS)
                .getBlob("bytes");
        if (chunk == null) throw new Exception("Notebook page download incomplete");
        bytes.write(chunk.toBytes());
      }
      JSONObject m = new JSONObject(new String(metadata.toBytes(), StandardCharsets.UTF_8));
      new JSONObject(bytes.toString(StandardCharsets.UTF_8.name()));
      synchronized (this) {
        JSONObject index = assetIndex(), old = index.optJSONObject(id);
        if (old != null && old.optBoolean("pending")) continue;
        atomic(new File(assetsDir(), id + ".json"), bytes.toByteArray());
        m.put("pending", false).put("baseRevision", revision);
        index.put(id, m);
        atomic(
            new File(assetsDir(), "index.json"), index.toString().getBytes(StandardCharsets.UTF_8));
      }
    }
  }

  public synchronized void signOut() throws Exception {
    if (busy) throw new Exception("Wait for sync to finish before signing out");
    FirebaseAuth.getInstance().signOut();
    owner = "";
    folder = null;
    records.clear();
    baseline.clear();
    lastSync = 0;
  }

  private void requireAccount() throws Exception {
    if (folder == null || owner.isEmpty())
      throw new Exception("Sign in with your personal Google account first");
  }

  private static byte[] read(File file) throws Exception {
    try (FileInputStream in = new FileInputStream(file)) {
      return IO.read(in, 80000000);
    }
  }

  static void atomic(File file, byte[] bytes) throws Exception {
    AtomicFile atomic = new AtomicFile(file);
    FileOutputStream out = null;
    try {
      out = atomic.startWrite();
      out.write(bytes);
      atomic.finishWrite(out);
    } catch (Exception e) {
      if (out != null) atomic.failWrite(out);
      throw e;
    }
  }
}
