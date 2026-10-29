package com.karandeep.sathi;

import android.app.*;
import android.app.job.*;
import android.content.*;
import com.google.firebase.*;
import org.json.*;

public class SathiApp extends Application {
  public static boolean configured = false;
  public void onCreate() {
    super.onCreate();
    try {
      JSONObject config =
          new JSONObject(
              new String(
                  IO.read(getAssets().open("firebase.json"), 100000),
                  java.nio.charset.StandardCharsets.UTF_8));
      FirebaseOptions options =
          new FirebaseOptions.Builder()
              .setApiKey(config.getString("apiKey"))
              .setApplicationId(config.getString("appId"))
              .setProjectId(config.getString("projectId"))
              .setGcmSenderId(config.getString("senderId"))
              .build();
      if (FirebaseApp.getApps(this).isEmpty()) FirebaseApp.initializeApp(this, options);
      configured = true;
    } catch (Exception e) {
      android.util.Log.e("SATHI", "Firebase configuration missing or invalid");
    }
    if (!configured) return;
    ((JobScheduler) getSystemService(JOB_SCHEDULER_SERVICE))
        .schedule(
            new JobInfo.Builder(7410, new ComponentName(this, SyncJob.class))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .setPeriodic(3600000, 900000)
                .build());
  }
}
