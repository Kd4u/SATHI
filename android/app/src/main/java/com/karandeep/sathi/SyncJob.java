package com.karandeep.sathi;

import android.app.job.*;

public class SyncJob extends JobService {
  public boolean onStartJob(JobParameters params) {
    Store.get(this)
        .sync(
            (message, ok) -> {
              ScheduleWidget.refresh(this);
              jobFinished(params, false);
            });
    return true;
  }

  public boolean onStopJob(JobParameters params) {
    return true;
  }
}
