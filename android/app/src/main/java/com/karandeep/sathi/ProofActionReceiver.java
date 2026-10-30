package com.karandeep.sathi;

import android.app.job.*;
import android.content.*;
import com.google.firebase.auth.FirebaseAuth;
import org.json.*;

public class ProofActionReceiver extends BroadcastReceiver {
  public void onReceive(Context context, Intent intent) {
    PendingResult pending = goAsync();
    Store.get(context)
        .io
        .execute(
            () -> {
              try {
                if (FirebaseAuth.getInstance().getCurrentUser() == null
                    || !FirebaseAuth.getInstance()
                        .getCurrentUser()
                        .getUid()
                        .equals(intent.getStringExtra("account"))) return;
                Store store = Store.get(context);
                store.activate();
                String id = intent.getStringExtra("id"), field = intent.getStringExtra("field");
                if (id == null
                    || !java.util.Set.of("fingerprint", "signedSheet", "attended").contains(field))
                  return;
                boolean exists = false;
                for (JSONObject row : Schedule.classes(store.copy()))
                  if (row.optString("id").equals(id)) exists = true;
                if (!exists && id.startsWith("custom-"))
                  exists = store.copy().containsKey("event:" + id.substring(7));
                if (!exists) return;
                JSONObject proof = store.object("study:proof:" + id);
                proof.put(field, true).put("updatedAt", Snapshot.swiftNow());
                if (proof.optBoolean("fingerprint")
                    && proof.optBoolean("signedSheet")
                    && (!proof.has("attended") || proof.optBoolean("attended")))
                  proof.put("attended", true);
                store.put("study:proof:" + id, ParityRules.normaliseProof(proof));
                JobScheduler jobs =
                    (JobScheduler) context.getSystemService(Context.JOB_SCHEDULER_SERVICE);
                jobs.schedule(
                    new JobInfo.Builder(7411, new ComponentName(context, SyncJob.class))
                        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                        .setOverrideDeadline(1000)
                        .build());
                ScheduleWidget.refresh(context);
              } catch (Exception ignored) {
              } finally {
                pending.finish();
              }
            });
  }
}
