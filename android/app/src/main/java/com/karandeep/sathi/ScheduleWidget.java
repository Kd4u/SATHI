package com.karandeep.sathi;

import android.app.*;
import android.appwidget.*;
import android.content.*;
import android.os.Bundle;
import android.widget.RemoteViews;
import java.time.*;
import java.time.format.*;
import java.util.*;
import org.json.*;

public class ScheduleWidget extends AppWidgetProvider {
  public void onUpdate(Context c, AppWidgetManager manager, int[] ids) {
    for (int id : ids) update(c, manager, id);
  }

  public void onAppWidgetOptionsChanged(Context c, AppWidgetManager m, int id, Bundle options) {
    update(c, m, id);
  }

  public static void refresh(Context c) {
    AppWidgetManager m = AppWidgetManager.getInstance(c);
    for (int id : m.getAppWidgetIds(new ComponentName(c, ScheduleWidget.class))) update(c, m, id);
    Reminders.schedule(c);
  }

  static void update(Context c, AppWidgetManager m, int id) {
    RemoteViews views = new RemoteViews(c.getPackageName(), R.layout.widget);
    StringBuilder text = new StringBuilder();
    try {
      Store store = Store.get(c);
      store.activate();
      Map<String, String> data = store.copy();
      if (!store.hasTimetable()) text.append("Open SATHI and sync your timetable");
      else {
        int days =
            m.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) > 200
                ? 3
                : 1;
        List<JSONObject> classes = Schedule.classes(data);
        for (int d = 0; d < days; d++) {
          String date = Schedule.today().plusDays(d).toString();
          text.append(
                  d == 0
                      ? "Today"
                      : Schedule.today()
                          .plusDays(d)
                          .format(DateTimeFormatter.ofPattern("EEE d MMM")))
              .append('\n');
          int count = 0;
          for (JSONObject s : classes)
            if (date.equals(s.optString("date"))) {
              text.append(s.optString("time"))
                  .append("  ")
                  .append(s.optString("subject"))
                  .append('\n');
              if (++count >= (days == 1 ? 5 : 3)) break;
            }
          for (JSONObject e : Schedule.events(data, date)) {
            text.append(e.optString("time")).append("  ").append(e.optString("title")).append('\n');
            if (++count >= 5) break;
          }
          if (count == 0) text.append("No scheduled classes\n");
          if (d < days - 1) text.append('\n');
        }
      }
    } catch (Exception e) {
      text.append("Open SATHI to view your saved schedule");
    }
    views.setTextViewText(R.id.widget_text, text.toString().trim());
    views.setOnClickPendingIntent(
        R.id.widget_text,
        PendingIntent.getActivity(
            c,
            0,
            new Intent(c, MainActivity.class),
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
    m.updateAppWidget(id, views);
  }
}
