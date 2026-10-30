package com.karandeep.sathi;

import android.app.job.*;
import android.content.*;

public class RestoreReceiver extends BroadcastReceiver {
  public void onReceive(Context context, Intent intent) {
    JobScheduler jobs = (JobScheduler) context.getSystemService(Context.JOB_SCHEDULER_SERVICE);
    jobs.schedule(
        new JobInfo.Builder(7411, new ComponentName(context, SyncJob.class))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setOverrideDeadline(1000)
            .build());
    ScheduleWidget.refresh(context);
  }
}
