package com.karandeep.sathi;

import android.app.*;
import android.content.*;
import android.os.*;
import java.util.*;
import org.json.*;

public class Reminders extends android.content.BroadcastReceiver {
  static PendingIntent alarm(Context c, int index, Intent intent) {
    return PendingIntent.getBroadcast(
        c, index, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }

  static void schedule(Context c) {
    AlarmManager alarms = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
    for (int i = 0; i < 100; i++) alarms.cancel(alarm(c, i, new Intent(c, Reminders.class)));
    try {
      Store store = Store.get(c);
      Map<String, String> data = store.copy();
      JSONObject p = Snapshot.object(data, "study:preferences");
      if (!p.optBoolean("reminders")) return;
      List<JSONObject> classes = Schedule.classes(data);
      int index = 0;
      long now = System.currentTimeMillis();
      for (JSONObject s : classes) {
        long start = Schedule.instant(s, false), end = Schedule.instant(s, true);
        if (end < now || start > now + 86400000L * 3) continue;
        long[] times = {
          start - p.optInt("fingerprintLeadMinutes", 15) * 60000L,
          start + p.optInt("sheetReminderMinutes", 40) * 60000L
        };
        for (int type = 0; type < 2; type++) {
          if (times[type] <= now || times[type] >= end || index >= 100) continue;
          Intent intent =
              new Intent(c, Reminders.class)
                  .putExtra("session", s.toString())
                  .putExtra("kind", type);
          alarms.setWindow(AlarmManager.RTC_WAKEUP, times[type], 600000, alarm(c, index++, intent));
        }
      }
    } catch (Exception ignored) {
    }
  }

  public void onReceive(Context c, Intent intent) {
    try {
      JSONObject s = new JSONObject(intent.getStringExtra("session"));
      Store store = Store.get(c);
      store.activate();
      boolean exists = false;
      for (JSONObject current : Schedule.classes(store.copy()))
        if (current.optString("id").equals(s.optString("id"))
            && current.optString("date").equals(s.optString("date"))) exists = true;
      if (!exists) return;
      JSONObject p = store.object("study:preferences");
      if (!p.optBoolean("reminders")) return;
      NotificationManager m =
          (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
      String channel =
          "class-" + p.optBoolean("sounds", true) + "-" + p.optBoolean("haptics", true);
      NotificationChannel ch =
          new NotificationChannel(
              channel, "Class reminders", NotificationManager.IMPORTANCE_DEFAULT);
      if (!p.optBoolean("sounds", true)) ch.setSound(null, null);
      ch.enableVibration(p.optBoolean("haptics", true));
      m.createNotificationChannel(ch);
      int kind = intent.getIntExtra("kind", 0);
      String message =
          kind == 0
              ? "Remember your fingerprint before class."
              : "Has the attendance sheet arrived? Record your attendance in SATHI.";
      PendingIntent open =
          PendingIntent.getActivity(
              c,
              0,
              new Intent(c, MainActivity.class),
              PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
      Notification.Builder n =
          new Notification.Builder(c, channel)
              .setSmallIcon(android.R.drawable.ic_dialog_info)
              .setContentTitle(s.getString("subject"))
              .setContentText(message)
              .setStyle(
                  new Notification.BigTextStyle().bigText(message + "\n" + s.optString("time")))
              .setContentIntent(open)
              .setAutoCancel(true);
      m.notify(s.optString("id").hashCode() + kind, n.build());
    } catch (Exception ignored) {
    }
  }
}
