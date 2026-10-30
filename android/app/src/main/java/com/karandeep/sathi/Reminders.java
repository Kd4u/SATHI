package com.karandeep.sathi;

import android.app.*;
import android.content.*;
import android.net.Uri;
import android.os.*;
import com.google.firebase.auth.FirebaseAuth;
import java.util.*;
import org.json.*;

/** OS-owned alarms and countdown notifications; no permanently running foreground service. */
public class Reminders extends android.content.BroadcastReceiver {
  static String uid() {
    return FirebaseAuth.getInstance().getCurrentUser() == null
        ? ""
        : FirebaseAuth.getInstance().getCurrentUser().getUid();
  }

  static PendingIntent alarm(Context c, int code, Intent intent) {
    return PendingIntent.getBroadcast(
        c, code, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }

  static void schedule(Context c) {
    try {
      AlarmManager manager = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
      android.content.SharedPreferences saved = c.getSharedPreferences("scheduled-reminders", 0);
      for (String action : saved.getStringSet("actions", Set.of()))
        manager.cancel(
            alarm(c, action.hashCode(), new Intent(c, Reminders.class).setAction(action)));
      for (int i = 0; i < 100; i++) manager.cancel(alarm(c, i, new Intent(c, Reminders.class)));
      Store store = Store.get(c);
      store.activate();
      Map<String, String> data = store.copy();
      JSONObject preferences = Snapshot.object(data, "study:preferences");
      Set<String> actions = new HashSet<>();
      long now = System.currentTimeMillis();
      boolean remind = preferences.optBoolean("reminders"),
          live = preferences.optBoolean("liveActivities");
      if (!uid().isEmpty() && (remind || live)) {
        for (JSONObject session : Schedule.classes(data)) {
          long start = Schedule.instant(session, false), end = Schedule.instant(session, true);
          if (end <= now || start > now + 3 * 86400000L) continue;
          if (remind) {
            enqueue(
                c,
                manager,
                actions,
                session,
                start - preferences.optInt("fingerprintLeadMinutes", 15) * 60000L,
                0,
                false);
            enqueue(
                c,
                manager,
                actions,
                session,
                start + preferences.optInt("sheetReminderMinutes", 40) * 60000L,
                1,
                false);
          }
          if (live) {
            enqueue(
                c,
                manager,
                actions,
                session,
                Math.max(
                    now + 1000, start - preferences.optInt("fingerprintLeadMinutes", 15) * 60000L),
                2,
                false);
            enqueue(c, manager, actions, session, start, 3, false);
            enqueue(c, manager, actions, session, end, 4, false);
          }
        }
        if (remind)
          for (int offset = 0; offset < 3; offset++)
            for (JSONObject event :
                Schedule.events(data, Schedule.today().plusDays(offset).toString())) {
              if (event.optString("time").equals("All day")) continue;
              enqueue(
                  c,
                  manager,
                  actions,
                  event,
                  Schedule.instant(event, false)
                      - preferences.optInt("fingerprintLeadMinutes", 15) * 60000L,
                  5,
                  true);
            }
      }
      saved.edit().putStringSet("actions", actions).apply();
    } catch (Exception ignored) {
    }
  }

  static void enqueue(
      Context c,
      AlarmManager manager,
      Set<String> actions,
      JSONObject session,
      long when,
      int kind,
      boolean activity)
      throws Exception {
    if (when <= System.currentTimeMillis()) return;
    String id = session.optString("id"), action = "SATHI-" + id + "-" + kind;
    Intent intent =
        new Intent(c, Reminders.class)
            .setAction(action)
            .putExtra("account", uid())
            .putExtra("session", session.toString())
            .putExtra("kind", kind)
            .putExtra("activity", activity);
    manager.setAndAllowWhileIdle(
        AlarmManager.RTC_WAKEUP, when, alarm(c, action.hashCode(), intent));
    actions.add(action);
  }

  public void onReceive(Context c, Intent intent) {
    PendingResult pending = goAsync();
    Store.get(c)
        .io
        .execute(
            () -> {
              try {
                Store store = Store.get(c);
                store.activate();
                if (!uid().equals(intent.getStringExtra("account"))) return;
                JSONObject session = new JSONObject(intent.getStringExtra("session"));
                boolean activity = intent.getBooleanExtra("activity", false);
                JSONObject current = null;
                List<JSONObject> candidates =
                    activity
                        ? Schedule.events(store.copy(), session.optString("date"))
                        : Schedule.classes(store.copy());
                for (JSONObject item : candidates)
                  if (item.optString("id").equals(session.optString("id"))
                      && item.optString("date").equals(session.optString("date"))
                      && item.optString("time").equals(session.optString("time"))) current = item;
                if (current != null) publish(c, current, intent.getIntExtra("kind", 0), activity);
              } catch (Exception ignored) {
              } finally {
                pending.finish();
              }
            });
  }

  static void publish(Context c, JSONObject session, int kind, boolean activity) throws Exception {
    NotificationManager manager =
        (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
    JSONObject prefs = Store.get(c).object("study:preferences");
    String id = session.optString("id");
    int liveID = (id + "-live").hashCode();
    if (kind == 4) {
      manager.cancel(liveID);
      return;
    }
    boolean live = kind == 2 || kind == 3;
    if (live && !prefs.optBoolean("liveActivities") || !live && !prefs.optBoolean("reminders"))
      return;
    if (Build.VERSION.SDK_INT >= 33
        && c.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
            != android.content.pm.PackageManager.PERMISSION_GRANTED) return;
    String title = session.optString("subject", session.optString("title", "SATHI"));
    long start = Schedule.instant(session, false),
        end = Schedule.instant(session, true),
        now = System.currentTimeMillis();
    if (live && end <= now) return;
    String sound = prefs.optString("notificationSound", "default"),
        channel =
            (live ? "countdown" : "reminder")
                + "-"
                + prefs.optBoolean("sounds", true)
                + "-"
                + prefs.optBoolean("haptics", true)
                + "-"
                + sound;
    NotificationChannel ch =
        new NotificationChannel(
            channel,
            live ? "Live class countdown" : "Class and activity reminders",
            live ? NotificationManager.IMPORTANCE_LOW : NotificationManager.IMPORTANCE_DEFAULT);
    if (live || !prefs.optBoolean("sounds", true)) ch.setSound(null, null);
    else if (sound.equals("sathi"))
      ch.setSound(
          Uri.parse("android.resource://" + c.getPackageName() + "/raw/sathi_chime"),
          new android.media.AudioAttributes.Builder()
              .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
              .build());
    ch.enableVibration(!live && prefs.optBoolean("haptics", true));
    manager.createNotificationChannel(ch);
    Intent openIntent =
        new Intent(c, MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("date", session.optString("date"))
            .putExtra("classID", id)
            .putExtra("account", uid());
    PendingIntent open =
        PendingIntent.getActivity(
            c,
            id.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    String message =
        activity
            ? "Activity starts soon · " + session.optString("time")
            : kind == 1
                ? "Has the attendance sheet arrived?"
                : live
                    ? (now < start
                        ? "Class starts soon · fingerprint before attendance"
                        : "Class in progress")
                    : "Remember your fingerprint before class.";
    Notification.Builder builder =
        new Notification.Builder(c, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(
                new Notification.BigTextStyle().bigText(message + "\n" + session.optString("time")))
            .setContentIntent(open)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(!live)
            .setOnlyAlertOnce(live)
            .setCategory(Notification.CATEGORY_REMINDER);
    if (live)
      builder
          .setOngoing(true)
          .setWhen(now < start ? start : end)
          .setUsesChronometer(true)
          .setChronometerCountDown(true)
          .setTimeoutAfter(Math.max(1000, end - now));
    String proofID = activity && !id.startsWith("excel-") ? "custom-" + id : id;
    if (!activity) {
      builder.addAction(
          new Notification.Action.Builder(
                  null, "Fingerprint done", proofAction(c, proofID, "fingerprint"))
              .build());
      builder.addAction(
          new Notification.Action.Builder(
                  null, "Sheet signed", proofAction(c, proofID, "signedSheet"))
              .build());
    } else
      builder.addAction(
          new Notification.Action.Builder(null, "Attended", proofAction(c, proofID, "attended"))
              .build());
    manager.notify(live ? liveID : (id + "-" + kind).hashCode(), builder.build());
  }

  static PendingIntent proofAction(Context c, String id, String field) {
    return PendingIntent.getBroadcast(
        c,
        (id + field).hashCode(),
        new Intent(c, ProofActionReceiver.class)
            .setAction("proof-" + id + field)
            .putExtra("account", uid())
            .putExtra("id", id)
            .putExtra("field", field),
        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }
}
