package com.karandeep.sathi;

import android.app.*;
import android.content.*;
import android.content.res.Configuration;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import androidx.credentials.*;
import androidx.credentials.exceptions.*;
import com.google.android.libraries.identity.googleid.*;
import com.google.firebase.auth.*;
import java.io.*;
import java.time.*;
import java.time.format.*;
import java.util.*;
import org.json.*;

/** Native Android screens; all network and workbook work runs outside the UI thread. */
public class MainActivity extends Activity {
  Store store;
  LinearLayout root, body, header;
  TextView statusView;
  int tabIndex = 0;
  LocalDate selectedDate = Schedule.today();
  boolean dark;
  int bg, card, ink, secondary, accent;
  String status = "Saved on this device";
  Handler handler = new Handler(Looper.getMainLooper());
  private Dialog editor;
  private Runnable saveDraft;
  private boolean authBusy;
  private final Runnable hourly =
      new Runnable() {
        public void run() {
          if (FirebaseAuth.getInstance().getCurrentUser() != null
              && System.currentTimeMillis() - store.lastSync() >= 3600000) sync(false);
          handler.postDelayed(this, 60000);
        }
      };

  public void onCreate(Bundle saved) {
    String initialMode = getSharedPreferences("appearance", 0).getString("mode", "system");
    boolean initialDark =
        initialMode.equals("dark")
            || (initialMode.equals("system")
                && (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                    == Configuration.UI_MODE_NIGHT_YES);
    setTheme(
        initialDark
            ? android.R.style.Theme_Material_NoActionBar
            : android.R.style.Theme_Material_Light_NoActionBar);
    super.onCreate(saved);
    if (!SathiApp.configured) {
      LinearLayout setup = new LinearLayout(this);
      setup.setOrientation(LinearLayout.VERTICAL);
      setup.setGravity(Gravity.CENTER);
      setup.setPadding(48, 48, 48, 48);
      TextView message = new TextView(this);
      message.setText("SATHI developer setup\n\nConfigure your own Firebase project before using sign-in and cloud sync. See docs/SETUP.md and run scripts/configure_android.py with your google-services.json.");
      message.setTextSize(18);
      setup.addView(message);
      setContentView(setup);
      return;
    }
    store = Store.get(this);
    try {
      store.activate();
    } catch (Exception e) {
      status = e.getMessage();
    }
    if (saved != null) {
      tabIndex = saved.getInt("tab");
      selectedDate = LocalDate.parse(saved.getString("date", Schedule.today().toString()));
    }
    render();
    if (FirebaseAuth.getInstance().getCurrentUser() != null) sync(false);
    handler.postDelayed(hourly, 60000);
  }

  public void onSaveInstanceState(Bundle out) {
    super.onSaveInstanceState(out);
    out.putInt("tab", tabIndex);
    out.putString("date", selectedDate.toString());
  }

  private void startLiveUpdates() {
    if (store == null) return;
    store.startLiveUpdates((message, changed) -> runOnUiThread(() -> {
      if (changed) sync(false);
      else { status = message; if (editor == null) render(); }
    }));
  }

  public void onResume() {
    super.onResume();
    if (store != null && FirebaseAuth.getInstance().getCurrentUser() != null) { startLiveUpdates(); sync(false); }
  }

  public void onPause() {
    if (store != null) store.stopLiveUpdates();
    flushDraft();
    super.onPause();
  }

  public void onDestroy() {
    handler.removeCallbacks(hourly);
    flushDraft();
    super.onDestroy();
  }

  int dp(float n) {
    return Math.round(n * getResources().getDisplayMetrics().density);
  }

  void appearance() {
    String mode = getSharedPreferences("appearance", 0).getString("mode", "system");
    dark =
        mode.equals("dark")
            || (mode.equals("system")
                && (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                    == Configuration.UI_MODE_NIGHT_YES);
    bg = Color.parseColor(dark ? "#0B1018" : "#F3F6FA");
    card = Color.parseColor(dark ? "#16202E" : "#FFFFFF");
    ink = Color.parseColor(dark ? "#F1F5FB" : "#17253B");
    secondary = Color.parseColor(dark ? "#A7B3C5" : "#64748B");
    String color = store.object("study:preferences").optString("accent", "blue");
    String[] accentNames = {"blue", "purple", "green", "teal", "indigo", "pink", "orange", "mint", "cyan", "red", "brown", "yellow"};
    String[] accentValues = {"#448AFF", "#9B7DE8", "#35A583", "#26A69A", "#7986CB", "#EC7AAB", "#EF9950", "#55BDA5", "#4DB6D1", "#E66B70", "#AE8B75", "#D2AA45"};
    accent = Color.parseColor(dark ? "#72B9F7" : "#1679C8");
    for (int i = 0; i < accentNames.length; i++) if (accentNames[i].equals(color)) accent = Color.parseColor(accentValues[i]);
    if (android.os.Build.VERSION.SDK_INT >= 31 && getSharedPreferences("appearance", 0).getBoolean("systemAccent", true)) {
      accent = getColor(dark ? android.R.color.system_accent1_200 : android.R.color.system_accent1_500);
    }
    getWindow().setStatusBarColor(bg);
    getWindow().setNavigationBarColor(bg);
    getWindow()
        .getDecorView()
        .setSystemUiVisibility(
            dark
                ? 0
                : View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
  }

  TextView text(String value, int size, int color, boolean bold) {
    TextView v = new TextView(this);
    v.setText(value);
    v.setTextSize(size);
    v.setTextColor(color);
    v.setFontFeatureSettings("kern");
    if (bold) v.setTypeface(null, Typeface.BOLD);
    v.setLineSpacing(dp(2), 1);
    return v;
  }

  LinearLayout vertical() {
    LinearLayout v = new LinearLayout(this);
    v.setOrientation(LinearLayout.VERTICAL);
    return v;
  }

  LinearLayout row() {
    LinearLayout r = new LinearLayout(this);
    r.setGravity(Gravity.CENTER_VERTICAL);
    return r;
  }

  GradientDrawable shape(int color, int radius) {
    GradientDrawable d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(radius));
    return d;
  }

  void gap(LinearLayout parent, int h) {
    View v = new View(this);
    parent.addView(v, new LinearLayout.LayoutParams(1, dp(h)));
  }

  void title(LinearLayout parent, String title, String subtitle) {
    parent.addView(text(title, 28, ink, true));
    if (!subtitle.isEmpty()) {
      gap(parent, 5);
      parent.addView(text(subtitle, 14, secondary, false));
    }
    gap(parent, 22);
  }

  LinearLayout panel(LinearLayout parent) {
    LinearLayout p = vertical();
    p.setPadding(dp(18), dp(18), dp(18), dp(18));
    p.setBackground(shape(card, 22));
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
    lp.bottomMargin = dp(12);
    parent.addView(p, lp);
    return p;
  }

  Button button(String label, Runnable action) {
    Button b = new Button(this);
    b.setText(label);
    b.setAllCaps(false);
    b.setTextSize(14);
    b.setTextColor(accent);
    b.setBackgroundTintList(android.content.res.ColorStateList.valueOf(card));
    b.setOnClickListener(v -> action.run());
    b.setMinHeight(dp(48));
    return b;
  }

  void action(LinearLayout p, String label, Runnable r) {
    p.addView(button(label, r), new LinearLayout.LayoutParams(-1, dp(52)));
    gap(p, 6);
  }

  void render() {
    appearance();
    root = vertical();
    root.setBackgroundColor(bg);
    root.setFitsSystemWindows(true);
    setContentView(root);
    if (Build.VERSION.SDK_INT >= 35) {
      root.setOnApplyWindowInsetsListener(
          (v, insets) -> {
            android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return insets;
          });
    }
    if (FirebaseAuth.getInstance().getCurrentUser() == null) {
      onboarding();
      return;
    }
    header = row();
    header.setPadding(dp(22), dp(8), dp(16), dp(6));
    TextView brand = text("SATHI", 18, ink, true);
    header.addView(brand, new LinearLayout.LayoutParams(0, dp(48), 1));
    brand.setGravity(Gravity.CENTER_VERTICAL);
    Button sync = button(store.busy() ? "Syncing…" : "↻  Sync", () -> sync(true));
    sync.setEnabled(!store.busy());
    header.addView(sync);
    root.addView(header);
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    body = vertical();
    body.setPadding(dp(22), dp(14), dp(22), dp(28));
    scroll.addView(body);
    root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    try {
      switch (tabIndex) {
        case 0:
          today();
          break;
        case 1:
          calendar();
          break;
        case 2:
          notebooks();
          break;
        case 3:
          dashboard();
          break;
        default:
          settings();
      }
    } catch (Exception e) {
      title(
          body,
          "Your saved data is safe",
          e.getMessage() == null ? "Sync to retrieve your timetable." : e.getMessage());
      action(body, "Sync", () -> sync(true));
    }
    LinearLayout nav = row();
    nav.setPadding(dp(6), dp(9), dp(6), dp(9));
    nav.setBackground(shape((card & 0x00FFFFFF) | 0xDD000000, 32));
    nav.setElevation(dp(10));
    String[] labels = {"Today", "Calendar", "Notebooks", "Progress", "Settings"};
    for (int i = 0; i < labels.length; i++) {
      final int index = i;
      LinearLayout item = vertical();
      item.setGravity(Gravity.CENTER);
      Icon icon = new Icon(this, i, accent);
      item.addView(icon, new LinearLayout.LayoutParams(dp(23), dp(23)));
      gap(item, 4);
      TextView label = text(labels[i], 10, i == tabIndex ? accent : secondary, i == tabIndex);
      label.setGravity(Gravity.CENTER);
      item.addView(label);
      if (i == tabIndex) item.setBackground(shape(dark ? 0xFF223B53 : 0xFFE5F1FC, 18));
      item.setPadding(0, dp(7), 0, dp(7));
      item.setContentDescription(labels[i]);
      item.setOnClickListener(
          v -> {
            tabIndex = index;
            if (index == 0) selectedDate = Schedule.today();
            render();
          });
      nav.addView(item, new LinearLayout.LayoutParams(0, dp(62), 1));
    }
    LinearLayout.LayoutParams navLayout = new LinearLayout.LayoutParams(-1, -2);
    navLayout.setMargins(dp(12), dp(4), dp(12), dp(12));
    root.addView(nav, navLayout);
  }

  void onboarding() {
    LinearLayout welcome = vertical();
    welcome.setGravity(Gravity.CENTER);
    welcome.setPadding(dp(30), dp(50), dp(30), dp(30));
    root.addView(welcome, new LinearLayout.LayoutParams(-1, -1));
    ImageView logo = new ImageView(this);
    logo.setImageResource(R.mipmap.ic_launcher);
    welcome.addView(logo, new LinearLayout.LayoutParams(dp(92), dp(92)));
    gap(welcome, 24);
    TextView h = text("Your day, organised.", 30, ink, true);
    h.setGravity(Gravity.CENTER);
    welcome.addView(h);
    gap(welcome, 16);
    TextView intro =
        text(
            "Your timetable, attendance and notes.\nOne account across your devices.",
            16,
            secondary,
            false);
    intro.setGravity(Gravity.CENTER);
    welcome.addView(intro);
    gap(welcome, 32);
    Button sign = button(authBusy ? "Signing in…" : "Continue with Google", this::signIn);
    sign.setEnabled(!authBusy);
    welcome.addView(sign, new LinearLayout.LayoutParams(-1, dp(54)));
    gap(welcome, 16);
    TextView hint =
        text(
            "Use your personal Google account, rather than a college or work account. SATHI"
                + " remembers your sign-in on this phone.",
            13,
            secondary,
            false);
    hint.setGravity(Gravity.CENTER);
    welcome.addView(hint);
    gap(welcome, 20);
    TextView state = text(status, 12, secondary, false);
    state.setGravity(Gravity.CENTER);
    welcome.addView(state);
  }

  void signIn() {
    try {
      JSONObject config =
          new JSONObject(
              new String(
                  IO.read(getAssets().open("firebase.json"), 100000),
                  java.nio.charset.StandardCharsets.UTF_8));
      String client = config.getString("webClientId");
      GetGoogleIdOption google =
          new GetGoogleIdOption.Builder()
              .setServerClientId(client)
              .setFilterByAuthorizedAccounts(false)
              .setAutoSelectEnabled(true)
              .build();
      GetCredentialRequest request =
          new GetCredentialRequest.Builder().addCredentialOption(google).build();
      authBusy = true;
      render();
      CredentialManager.create(this)
          .getCredentialAsync(
              this,
              request,
              null,
              getMainExecutor(),
              new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                public void onResult(GetCredentialResponse response) {
                  try {
                    GoogleIdTokenCredential google =
                        GoogleIdTokenCredential.createFrom(response.getCredential().getData());
                    FirebaseAuth.getInstance()
                        .signInWithCredential(
                            GoogleAuthProvider.getCredential(google.getIdToken(), null))
                        .addOnCompleteListener(
                            task -> {
                              authBusy = false;
                              if (task.isSuccessful()) {
                                try {
                                  store.activate();
                                  store.journal("google_sign_in", new JSONObject());
                                  status = "Signed in. Loading your saved timetable…";
                                  render();
                                  startLiveUpdates();
                                  sync(false);
                                } catch (Exception e) {
                                  error(e);
                                }
                              } else {
                                status = "Sign-in failed: " + task.getException().getMessage();
                                render();
                              }
                            });
                  } catch (Exception e) {
                    authBusy = false;
                    error(e);
                    render();
                  }
                }

                public void onError(GetCredentialException e) {
                  authBusy = false;
                  status =
                      e instanceof NoCredentialException
                          ? "No Google account is available. Add your personal Google account in"
                                + " Android Settings, update Google Play services, then try again."
                          : e instanceof GetCredentialCancellationException
                              ? "Sign-in cancelled. Continue whenever you are ready."
                              : "Google sign-in: " + e.getMessage();
                  render();
                }
              });
    } catch (Exception e) {
      authBusy = false;
      error(e);
    }
  }

  private boolean pendingSync = false;

  void sync(boolean explicit) { sync(explicit, null); }

  void sync(boolean explicit, Boolean preferLocal) {
    flushDraft();
    if (store.busy()) { if (preferLocal == null) pendingSync = true; return; }
    status = "Syncing in the background…";
    if (tabIndex == 4) render();
    store.sync(
        (message, ok) ->
            runOnUiThread(
                () -> {
                  status = message;
                  if (pendingSync) { pendingSync = false; handler.post(() -> sync(false)); }
                  if (editor == null) render();
                  if (explicit) {
                    Toast.makeText(this, message, Toast.LENGTH_LONG).show();
                    if (store.hasConflicts() || (!ok && message.contains("Both devices changed"))) {
                      new AlertDialog.Builder(this)
                        .setTitle("Choose a version for conflicting records")
                        .setMessage("Both versions will be backed up on this device first. Timetable conflicts also use that version’s semester, subjects and study preferences. Other independent edits are kept. If your Mac has the correct timetable, sync it there first, then choose cloud here.")
                        .setPositiveButton("Use cloud", (d, w) -> sync(true, false))
                        .setNegativeButton("Use this device", (d, w) -> sync(true, true))
                        .setNeutralButton("Cancel", null).show();
                    }
                  }
                }), preferLocal);
  }

  void dateRow(LinearLayout parent) {
    LinearLayout r = row();
    r.addView(
        button(
            "‹",
            () -> {
              selectedDate = selectedDate.minusDays(1);
              render();
            }),
        new LinearLayout.LayoutParams(dp(48), dp(48)));
    TextView date =
        text(selectedDate.format(DateTimeFormatter.ofPattern("EEE, d MMM yyyy")), 16, ink, true);
    date.setGravity(Gravity.CENTER);
    date.setOnClickListener(v -> pickDate());
    r.addView(date, new LinearLayout.LayoutParams(0, dp(48), 1));
    r.addView(
        button(
            "›",
            () -> {
              selectedDate = selectedDate.plusDays(1);
              render();
            }),
        new LinearLayout.LayoutParams(dp(48), dp(48)));
    parent.addView(r);
    gap(parent, 16);
  }

  void pickDate() {
    new DatePickerDialog(
            this,
            (v, y, m, d) -> {
              selectedDate = LocalDate.of(y, m + 1, d);
              render();
            },
            selectedDate.getYear(),
            selectedDate.getMonthValue() - 1,
            selectedDate.getDayOfMonth())
        .show();
  }

  void empty() {
    LinearLayout p = panel(body);
    p.addView(text("Your timetable belongs here", 22, ink, true));
    gap(p, 10);
    p.addView(
        text(
            "Use Sync to retrieve your saved schedule from your other devices. For a new account,"
                + " import an Excel timetable.",
            14,
            secondary,
            false));
    gap(p, 16);
    action(p, "Sync saved timetable", () -> sync(true));
    action(p, "Import Excel or SATHI JSON", this::chooseImport);
  }

  void today() throws Exception {
    title(body, "Today", "A little clarity for your day.");
    if (!store.hasTimetable()) {
      empty();
      return;
    }
    dateRow(body);
    scheduleRows(selectedDate);
  }

  void calendar() throws Exception {
    title(body, "Calendar", "Your classes, events and semester dates.");
    CalendarView calendar = new CalendarView(this);
    calendar.setDate(selectedDate.atStartOfDay(Schedule.ZONE).toInstant().toEpochMilli());
    calendar.setOnDateChangeListener(
        (v, y, m, d) -> {
          selectedDate = LocalDate.of(y, m + 1, d);
          render();
        });
    body.addView(calendar, new LinearLayout.LayoutParams(-1, dp(320)));
    gap(body, 16);
    scheduleRows(selectedDate);
  }

  void scheduleRows(LocalDate date) throws Exception {
    Map<String, String> records = store.copy();
    List<JSONObject> classes = Schedule.classes(records);
    Set<String> penalties = Schedule.penalties(classes, records);
    int count = 0;
    long now = System.currentTimeMillis();
    for (JSONObject s : classes) {
      if (!date.toString().equals(s.optString("date"))) continue;
      count++;
      LinearLayout p = panel(body);
      LinearLayout top = row();
      TextView time = text(s.optString("time"), 13, accent, true);
      top.addView(time, new LinearLayout.LayoutParams(0, -2, 1));
      String state = Schedule.status(s, records, penalties);
      top.addView(text(state, 12, state.equals("Missed") ? 0xFFE77171 : secondary, false));
      p.addView(top);
      gap(p, 10);
      p.addView(text(s.optString("subject"), 20, ink, true));
      gap(p, 5);
      p.addView(
          text(
              s.optString("teacher")
                  + (s.optString("section").isEmpty() ? "" : " · Sec " + s.optString("section")),
              13,
              secondary,
              false));
      long start = Schedule.instant(s, false), end = Schedule.instant(s, true);
      if (start > now && start - now < 3600000) {
        gap(p, 12);
        long minutes = Math.max(0, (long) Math.ceil((start - now) / 60000.0) - 1);
        p.addView(text(minutes + " min until fingerprint target", 13, accent, true));
      } else if (start <= now && now < end) {
        gap(p, 12);
        p.addView(
            text(
                "In class · " + Math.max(0, (end - now + 59999) / 60000) + " min remaining",
                13,
                accent,
                true));
        JSONObject proof = Snapshot.object(records, "study:proof:" + s.optString("id"));
        if (proof.has("fingerprint") && !proof.optBoolean("fingerprint"))
          p.addView(
              text(
                  "Fingerprint missed: do not sign the sheet as a proxy. Review your attendance"
                      + " after class.",
                  13,
                  0xFFE77171,
                  true));
      }
      p.setOnClickListener(v -> attendance(s));
      p.setContentDescription(
          s.optString("subject")
              + ", "
              + s.optString("time")
              + ", "
              + state
              + ". Tap to record attendance.");
    }
    List<JSONObject> events = Schedule.events(records, date.toString());
    for (JSONObject e : events) {
      LinearLayout p = panel(body);
      p.addView(text(e.optString("time"), 12, accent, true));
      gap(p, 7);
      p.addView(text(e.optString("title"), 18, ink, true));
      if (!e.optString("notes").isEmpty()) {
        gap(p, 8);
        p.addView(text(e.optString("notes"), 13, secondary, false));
      }
      if (e.has("id"))
        p.setOnLongClickListener(
            v -> {
              new AlertDialog.Builder(this)
                  .setTitle("Remove this custom event?")
                  .setMessage(
                      "This action is not available in this first Android build. Edit it in the"
                          + " Apple app, then Sync here.")
                  .setPositiveButton("OK", null)
                  .show();
              return true;
            });
    }
    if (count == 0 && events.isEmpty()) {
      LinearLayout p = panel(body);
      p.addView(text("A clear day", 22, ink, true));
      gap(p, 8);
      p.addView(text("No classes or events scheduled.", 14, secondary, false));
    }
    gap(body, 8);
    action(body, "＋ Add an event", this::addEvent);
  }

  void attendance(JSONObject session) {
    try {
      String key = "study:proof:" + session.getString("id");
      JSONObject proof = store.object(key);
      LinearLayout form = vertical();
      form.setPadding(dp(22), dp(10), dp(22), dp(10));
      String[] names = {
        "Attended class",
        "Fingerprint recorded",
        "Attendance sheet signed",
        "Official duty (counts as present)"
      };
      String[] keys = {"attended", "fingerprint", "signedSheet", "officialDuty"};
      Spinner[] choices = new Spinner[4];
      for (int i = 0; i < 4; i++) {
        form.addView(text(names[i], 14, ink, true));
        Spinner choice = new Spinner(this);
        String[] values =
            i == 3 ? new String[] {"No", "Yes"} : new String[] {"Not recorded", "Yes", "No"};
        ArrayAdapter<String> adapter =
            new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, values);
        choice.setAdapter(adapter);
        choice.setSelection(
            i == 3
                ? (proof.optBoolean(keys[i]) ? 1 : 0)
                : proof.has(keys[i]) ? (proof.optBoolean(keys[i]) ? 1 : 2) : 0);
        form.addView(choice, new LinearLayout.LayoutParams(-1, dp(48)));
        choices[i] = choice;
      }
      form.addView(
          text(
              "Only record what happened. A mismatch between fingerprint and sheet marks this class"
                  + " and the next three classes as missed under your attendance rule. Unmarked"
                  + " classes are not assumed present.",
              12,
              secondary,
              false));
      new AlertDialog.Builder(this)
          .setTitle(session.optString("subject"))
          .setView(form)
          .setNegativeButton("Cancel", null)
          .setPositiveButton(
              "Save",
              (d, w) -> {
                try {
                  for (int i = 0; i < 4; i++) {
                    int value = choices[i].getSelectedItemPosition();
                    if (i == 3) proof.put(keys[i], value == 1);
                    else if (value == 0) proof.remove(keys[i]);
                    else proof.put(keys[i], value == 1);
                  }
                  proof.put("updatedAt", Snapshot.swiftNow());
                  store.put(key, proof);
                  status = "Attendance saved locally";
                  ScheduleWidget.refresh(this);
                  render();
                } catch (Exception e) {
                  error(e);
                }
              })
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  EditText field(LinearLayout form, String hint, String initial) {
    EditText e = new EditText(this);
    e.setHint(hint);
    e.setText(initial);
    e.setTextColor(ink);
    e.setHintTextColor(secondary);
    e.setTextSize(16);
    form.addView(e, new LinearLayout.LayoutParams(-1, -2));
    return e;
  }

  void addEvent() {
    LinearLayout form = vertical();
    form.setPadding(dp(20), 0, dp(20), 0);
    EditText name = field(form, "Event title", "");
    Spinner eventType = new Spinner(this);
    String[] types = {"Quiz", "Guest lecture", "Presentation", "Placement", "Workshop", "Meeting", "Other"};
    eventType.setAdapter(new ArrayAdapter<String>(this, android.R.layout.simple_spinner_dropdown_item, types));
    form.addView(eventType);
    EditText date = field(form, "Date YYYY-MM-DD", selectedDate.toString());
    EditText start = field(form, "Starts HH:mm", "09:00"),
        end = field(form, "Ends HH:mm", "10:00"),
        notes = field(form, "Notes", "");
    AlertDialog dialog =
        new AlertDialog.Builder(this)
            .setTitle("New event")
            .setView(form)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Save", null)
            .create();
    dialog.setOnShowListener(
        d ->
            dialog
                .getButton(-1)
                .setOnClickListener(
                    v -> {
                      try {
                        LocalDate.parse(date.getText());
                        if (!LocalTime.parse(end.getText())
                            .isAfter(LocalTime.parse(start.getText())))
                          throw new Exception("End time must follow start time");
                        if (name.getText().toString().trim().isEmpty())
                          throw new Exception("Enter an event title");
                        String id = UUID.randomUUID().toString().toUpperCase(Locale.ROOT);
                        store.put(
                            "event:" + id,
                            new JSONObject()
                                .put("id", id)
                                .put("date", date.getText())
                                .put("start", start.getText())
                                .put("end", end.getText())
                                .put("title", name.getText())
                                .put("type", types[eventType.getSelectedItemPosition()])
                                .put("subject", "")
                                .put("notes", notes.getText()));
                        dialog.dismiss();
                        ScheduleWidget.refresh(this);
                        render();
                      } catch (Exception e) {
                        error(e);
                      }
                    }));
    dialog.show();
  }

  void dashboard() throws Exception {
    title(body, "Your progress", "An honest view of the semester.");
    if (!store.hasTimetable()) {
      empty();
      return;
    }
    Map<String, String> records = store.copy();
    List<JSONObject> classes = Schedule.classes(records);
    Set<String> penalties = Schedule.penalties(classes, records);
    int present = 0, missed = 0, unmarked = 0, past = 0;
    Map<String, int[]> subjects = new TreeMap<>();
    for (JSONObject s : classes) {
      int[] counts = subjects.computeIfAbsent(s.optString("subject"), k -> new int[4]);
      counts[3]++;
      if (Schedule.instant(s, true) > System.currentTimeMillis()) continue;
      past++;
      String state = Schedule.status(s, records, penalties);
      if (state.equals("Attended") || state.equals("OD")) {
        present++;
        counts[0]++;
      } else if (state.equals("Missed")) {
        missed++;
        counts[1]++;
      } else {
        unmarked++;
        counts[2]++;
      }
    }
    LinearLayout hero = panel(body);
    hero.addView(
        text(
            present + missed == 0 ? "—" : Math.round(present * 100f / (present + missed)) + "%",
            48,
            accent,
            true));
    hero.addView(text("Recorded attendance", 16, ink, true));
    gap(hero, 10);
    hero.addView(
        text(
            present + " present · " + missed + " missed · " + unmarked + " unmarked",
            13,
            secondary,
            false));
    gap(hero, 8);
    hero.addView(text("Unmarked classes do not count as present or missed.", 12, secondary, false));
    LinearLayout overview = panel(body);
    overview.addView(text(past + " / " + classes.size() + " classes completed", 18, ink, true));
    gap(overview, 7);
    overview.addView(
        text(
            subjects.size()
                + " subjects · Semester "
                + store.object("selection").optInt("semester", 1),
            14,
            secondary,
            false));
    gap(body, 12);
    body.addView(text("Subjects", 21, ink, true));
    gap(body, 12);
    int target = store.object("selection").optInt("minimumAttendance", 80);
    for (String name : subjects.keySet()) {
      int[] c = subjects.get(name);
      LinearLayout p = panel(body);
      p.addView(text(name, 17, ink, true));
      gap(p, 9);
      p.addView(
          text(
              c[0] + c[1] == 0
                  ? "No confirmed attendance"
                  : Math.round(c[0] * 100f / (c[0] + c[1])) + "% recorded attendance",
              14,
              accent,
              true));
      gap(p, 7);
      p.addView(
          text(
              c[0] + " present · " + c[1] + " missed · " + c[2] + " unmarked",
              12,
              secondary,
              false));
      int needed =
          (int)
              Math.ceil(
                  Math.max(0, (target / 100.0 * (c[0] + c[1]) - c[0]) / (1 - target / 100.0)));
      if (needed > 0)
        p.addView(
            text(
                "Attend the next " + needed + " confirmed classes to reach " + target + "%",
                12,
                secondary,
                false));
    }
  }

  void settings() throws Exception {
    title(body, "Settings", "Make SATHI yours.");
    FirebaseUser user = FirebaseAuth.getInstance().getCurrentUser();
    LinearLayout account = panel(body);
    account.addView(
        text(
            user.getDisplayName() == null ? "Your account" : user.getDisplayName(), 20, ink, true));
    gap(account, 6);
    account.addView(text(user.getEmail(), 14, secondary, false));
    gap(account, 12);
    account.addView(text(status, 13, accent, false));
    if (store.lastSync() > 0)
      account.addView(
          text(
              "Last sync: "
                  + Instant.ofEpochMilli(store.lastSync())
                      .atZone(Schedule.ZONE)
                      .format(DateTimeFormatter.ofPattern("d MMM, h:mm a")),
              12,
              secondary,
              false));
    gap(account, 8);
    account.addView(
        text(
            "Changes save on this phone immediately. Sync sends changes to other open devices automatically. Background sync runs hourly, or"
                + " when you tap Sync. Background timing can be delayed by battery optimisation.",
            13,
            secondary,
            false));
    action(account, "Sync now", () -> sync(true));
    action(body, "Student profile", () -> studentProfile());
    LinearLayout appearance = panel(body);
    appearance.addView(text("Appearance", 18, ink, true));
    action(
        appearance,
        "Theme",
        () ->
            new AlertDialog.Builder(this)
                .setTitle("Appearance")
                .setItems(
                    new String[] {"System", "Light", "Dark"},
                    (d, i) -> {
                      getSharedPreferences("appearance", 0)
                          .edit()
                          .putString("mode", new String[] {"system", "light", "dark"}[i])
                          .apply();
                      recreate();
                    })
                .show());
    action(
        appearance,
        "Accent colour",
        () ->
            new AlertDialog.Builder(this)
                .setTitle("Accent colour")
                .setItems(
                    new String[] {"System wallpaper", "Blue", "Purple", "Green", "Teal", "Indigo", "Pink", "Orange", "Mint", "Cyan", "Red", "Brown", "Yellow"},
                    (d, i) -> {
                      getSharedPreferences("appearance", 0).edit().putBoolean("systemAccent", i == 0).apply();
                      if (i > 0) preference("accent", new String[] {"blue", "purple", "green", "teal", "indigo", "pink", "orange", "mint", "cyan", "red", "brown", "yellow"}[i - 1]);
                      else { render(); }
                    })
                .show());
    LinearLayout reminders = panel(body);
    reminders.addView(text("Notifications", 18, ink, true));
    toggle(reminders, "Fingerprint and sheet crosscheck", "proofCrosscheck", false);
    toggle(reminders, "Class and attendance reminders", "reminders", false);
    toggle(reminders, "Notification sounds", "sounds", true);
    toggle(reminders, "Vibration", "haptics", true);
    reminders.addView(
        text(
            "Fingerprint reminder: 15 minutes before class. Sheet reminder: 40 minutes after the"
                + " start. Android may delay reminders; they do not mark attendance automatically.",
            12,
            secondary,
            false));
    LinearLayout schedule = panel(body);
    schedule.addView(text("Timetable", 18, ink, true));
    action(schedule, "Subjects and section", this::selection);
    action(schedule, "Import Excel or JSON", this::chooseImport);
    action(
        schedule,
        "Export account backup",
        () -> {
          Intent intent =
              new Intent(Intent.ACTION_CREATE_DOCUMENT)
                  .setType("application/json")
                  .addCategory(Intent.CATEGORY_OPENABLE)
                  .putExtra(Intent.EXTRA_TITLE, "SATHI-Android-backup.json");
          startActivityForResult(intent, 32);
        });
    action(schedule, "Semester history", this::semesterHistory);
    action(
        schedule,
        "Android Home Screen widget",
        () ->
            new AlertDialog.Builder(this)
                .setTitle("Add the SATHI widget")
                .setMessage(
                    "Touch and hold an empty area of your Home Screen, choose Widgets, then SATHI."
                        + " Resize it taller to show the next three days. Widgets read your local"
                        + " saved copy.")
                .setPositiveButton("OK", null)
                .show());
    action(
        body,
        "Sign out",
        () ->
            new AlertDialog.Builder(this)
                .setTitle("Sign out?")
                .setMessage(
                    "Your saved copy stays private on this device. Sync first to send any changes"
                        + " to your other devices.")
                .setNegativeButton("Cancel", null)
                .setPositiveButton(
                    "Sign out",
                    (d, w) -> {
                      try {
                        store.signOut();
                        ScheduleWidget.refresh(this);
                        render();
                      } catch (Exception e) {
                        error(e);
                      }
                    })
                .show());
    body.addView(
        text(
            "SATHI Android 1.0 · Android 10+\n"
                + "Apple Pencil handwriting remains in its original format. Android can edit typed"
                + " notebook text; Apple-only drawing and Live Activity features are not included.",
            12,
            secondary,
            false));
  }

  void toggle(LinearLayout p, String label, String key, boolean defaultValue) {
    Switch sw = new Switch(this);
    sw.setText(label);
    sw.setTextColor(ink);
    sw.setPadding(0, dp(12), 0, dp(12));
    sw.setChecked(store.object("study:preferences").optBoolean(key, defaultValue));
    sw.setOnCheckedChangeListener(
        (v, checked) -> {
          if (key.equals("reminders")
              && checked
              && Build.VERSION.SDK_INT >= 33
              && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                  != android.content.pm.PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[] {android.Manifest.permission.POST_NOTIFICATIONS}, 90);
          preference(key, checked);
        });
    p.addView(sw, new LinearLayout.LayoutParams(-1, dp(56)));
  }

  void preference(String key, Object value) {
    try {
      JSONObject p = store.object("study:preferences");
      defaults(p);
      p.put(key, value);
      store.put("study:preferences", p);
      ScheduleWidget.refresh(this);
      render();
    } catch (Exception e) {
      error(e);
    }
  }

  static void defaults(JSONObject p) throws Exception {
    JSONObject defaults =
        new JSONObject(
            "{\"didCustomizeAppearance\":false,\"accent\":\"blue\",\"glassOpacity\":0.75,\"fontScale\":1,\"sounds\":true,\"notificationSound\":\"default\",\"haptics\":true,\"reminders\":false,\"classCountdown\":true,\"liveActivities\":false,\"fingerprintLeadMinutes\":15,\"fingerprintTargetMinutes\":1,\"reminderGraceMinutes\":5,\"sheetReminderMinutes\":40,\"firstYearSection\":\"\",\"programme\":\"MBA\"}");
    Iterator<String> keys = defaults.keys();
    while (keys.hasNext()) {
      String k = keys.next();
      if (!p.has(k)) p.put(k, defaults.get(k));
    }
  }

  void studentProfile() {
    JSONObject prefs = store.object("study:preferences");
    int semester = store.object("selection").optInt("semester", 1);
    LinearLayout form = vertical(); form.setPadding(dp(18), 0, dp(18), 0);
    EditText name = field(form, "Your name", prefs.optString("studentName", ""));
    Spinner course = new Spinner(this);
    String[] courses = {"MBA", "DBM", "DBAI", "HHM"};
    course.setAdapter(new ArrayAdapter<String>(this, android.R.layout.simple_spinner_dropdown_item, courses));
    for (int i = 0; i < courses.length; i++) if (courses[i].equals(prefs.optString("programme", "MBA"))) course.setSelection(i);
    form.addView(course); form.addView(text("Semester " + semester + " · Year " + (semester <= 3 ? "1" : "2"), 13, secondary, false));
    EditText section = field(form, "Section A, B, C or D", prefs.optString("firstYearSection", ""));
    if (semester >= 4) section.setVisibility(View.GONE);
    new AlertDialog.Builder(this).setTitle("Student profile").setView(form).setNegativeButton("Cancel", null)
      .setPositiveButton("Save", (dialog, which) -> {
        try {
          defaults(prefs); prefs.put("studentName", name.getText().toString().trim()).put("programme", courses[course.getSelectedItemPosition()]).put("studentSemester", semester);
          if (semester <= 3) prefs.put("firstYearSection", section.getText().toString().trim().toUpperCase(Locale.ROOT));
          store.put("study:preferences", prefs); ScheduleWidget.refresh(this); render();
        } catch (Exception error) { error(error); }
      }).show();
  }

  void selection() {
    try {
      JSONObject report = store.object("timetable"), sel = store.object("selection");
      JSONArray subjects = report.optJSONArray("subjects");
      if (subjects == null) {
        empty();
        return;
      }
      LinearLayout form = vertical();
      form.setPadding(dp(18), 0, dp(18), 0);
      EditText section =
          field(
              form,
              "First-year section (A, B, C…)",
              store.object("study:preferences").optString("firstYearSection"));
      if (sel.optInt("semester", 1) >= 4) section.setVisibility(View.GONE);
      JSONArray selected = sel.optJSONArray("keys");
      Set<String> old = new HashSet<>();
      if (selected != null)
        for (int i = 0; i < selected.length(); i++) old.add(selected.getString(i));
      List<CheckBox> boxes = new ArrayList<>();
      for (int i = 0; i < subjects.length(); i++) {
        JSONObject s = subjects.getJSONObject(i);
        CheckBox b = new CheckBox(this);
        b.setText(s.optString("name"));
        b.setTextColor(ink);
        b.setTag(s.getString("key"));
        b.setChecked(old.contains(s.getString("key")));
        form.addView(b);
        boxes.add(b);
      }
      ScrollView scroll = new ScrollView(this);
      scroll.addView(form);
      new AlertDialog.Builder(this)
          .setTitle("Your subjects")
          .setView(scroll)
          .setNegativeButton("Cancel", null)
          .setPositiveButton(
              "Save",
              (d, w) -> {
                try {
                  JSONArray keys = new JSONArray();
                  for (CheckBox b : boxes) if (b.isChecked()) keys.put(b.getTag().toString());
                  sel.put("keys", keys);
                  store.put("selection", sel);
                  JSONObject p = store.object("study:preferences");
                  defaults(p);
                  p.put(
                      "firstYearSection",
                      section.getText().toString().trim().toUpperCase(Locale.ROOT));
                  store.put("study:preferences", p);
                  sync(false);
                  ScheduleWidget.refresh(this);
                  render();
                } catch (Exception e) {
                  error(e);
                }
              })
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  void semesterHistory() {
    try {
      JSONArray semesters = store.object("study:semesters").optJSONArray("semesters");
      StringBuilder summary = new StringBuilder();
      if (semesters != null)
        for (int i = 0; i < semesters.length(); i++) {
          JSONObject s = semesters.getJSONObject(i);
          summary
              .append(s.optString("title"))
              .append("\n")
              .append(s.optString("start"))
              .append(" → ")
              .append(s.optString("end"))
              .append("\n\n");
        }
      summary.append(
          "Archived semester files remain preserved in your cloud account. Full archive viewing and"
              + " semester replacement are currently available in the Apple app.");
      new AlertDialog.Builder(this)
          .setTitle("Semester history")
          .setMessage(summary)
          .setPositiveButton("OK", null)
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  void chooseImport() {
    if (store.hasTimetable()) {
      new AlertDialog.Builder(this)
          .setTitle("Timetable already saved")
          .setMessage(
              "To preserve previous attendance and notes, archive and import the next semester in"
                  + " your Apple app, then tap Sync here.")
          .setPositiveButton("OK", null)
          .show();
      return;
    }
    Intent intent =
        new Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(
                Intent.EXTRA_MIME_TYPES,
                new String[] {
                  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                  "application/json"
                });
    startActivityForResult(intent, 31);
  }

  public void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (result != RESULT_OK || data == null || data.getData() == null) return;
    Uri uri = data.getData();
    if (request == 32) {
      store.io.execute(
          () -> {
            try (OutputStream out = getContentResolver().openOutputStream(uri)) {
              out.write(Snapshot.encode(store.copy()));
              runOnUiThread(
                  () -> Toast.makeText(this, "Account backup exported", Toast.LENGTH_SHORT).show());
            } catch (Exception e) {
              runOnUiThread(() -> error(e));
            }
          });
      return;
    }
    if (request == 31) {
      status = "Reading timetable…";
      render();
      store.io.execute(
          () -> {
            try (InputStream in = getContentResolver().openInputStream(uri)) {
              byte[] bytes = readLimited(in, 20000000);
              JSONObject report;
              if (bytes.length > 2 && bytes[0] == 'P' && bytes[1] == 'K')
                report = ExcelImport.read(bytes, "Imported timetable.xlsx");
              else
                report = new JSONObject(new String(bytes, java.nio.charset.StandardCharsets.UTF_8));
              JSONArray subjects = report.getJSONArray("subjects");
              report.getJSONArray("sessions");
              report.getJSONArray("events");
              runOnUiThread(() -> confirmImport(report, subjects));
            } catch (Exception e) {
              runOnUiThread(() -> error(e));
            }
          });
    }
  }

  void confirmImport(JSONObject report, JSONArray subjects) {
    try {
      LinearLayout form = vertical();
      form.setPadding(dp(20), 0, dp(20), 0);
      form.addView(
          text(
              report.getJSONArray("sessions").length()
                  + " classes · "
                  + subjects.length()
                  + " subjects found. Review the semester before saving.",
              14,
              ink,
              false));
      EditText semester = field(form, "Semester number", "1");
      semester.setInputType(2);
      new AlertDialog.Builder(this)
          .setTitle("Import timetable")
          .setView(form)
          .setNegativeButton("Cancel", null)
          .setPositiveButton(
              "Save",
              (d, w) -> {
                try {
                  int number = Integer.parseInt(semester.getText().toString());
                  if (number < 1 || number > 20)
                    throw new Exception("Enter a semester between 1 and 20");
                  JSONArray keys = new JSONArray();
                  for (int i = 0; i < subjects.length(); i++)
                    keys.put(subjects.getJSONObject(i).getString("key"));
                  store.importReport(report, keys, number);
                  sync(false);
                  status = "Timetable saved. Choose your subjects and section in Settings.";
                  ScheduleWidget.refresh(this);
                  render();
                  selection();
                } catch (Exception e) {
                  error(e);
                }
              })
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  static byte[] readLimited(InputStream in, int limit) throws Exception {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    byte[] buffer = new byte[8192];
    int n;
    while ((n = in.read(buffer)) != -1) {
      if (out.size() + n > limit) throw new IOException("File is too large");
      out.write(buffer, 0, n);
    }
    return out.toByteArray();
  }

  void notebooks() throws Exception {
    title(body, "Notebooks", "A place for every thought.");
    action(body, "＋ New quick note", () -> newNote(""));
    JSONObject index = store.assetIndex();
    List<JSONObject> books = new ArrayList<>();
    Iterator<String> ids = index.keys();
    while (ids.hasNext()) {
      JSONObject m = index.getJSONObject(ids.next());
      String kind = m.optString("kind");
      if (kind.equals("notebook") || kind.equals("note")) books.add(m);
    }
    books.sort(Comparator.comparing(m -> m.optString("title")));
    for (JSONObject m : books) {
      JSONObject data = store.asset(m.getString("id"));
      if (data.has("deletedAt")) continue;
      LinearLayout p = panel(body);
      p.addView(text(m.optString("title", "Notebook"), 20, ink, true));
      gap(p, 8);
      p.addView(
          text(
              m.optString("kind").equals("note")
                  ? "Quick note"
                  : data.optJSONArray("pageIDs") == null
                      ? "Notebook"
                      : data.getJSONArray("pageIDs").length() + " pages",
              13,
              accent,
              false));
      p.setOnClickListener(
          v -> {
            if (m.optString("kind").equals("note")) editNote(m);
            else openBook(m);
          });
    }
    if (books.isEmpty()) {
      LinearLayout p = panel(body);
      p.addView(text("Start something worth keeping", 21, ink, true));
      gap(p, 10);
      p.addView(
          text(
              "Sync to download your notebooks, or create a quick note. Typed text syncs across"
                  + " devices. Apple handwriting is preserved but cannot be displayed or edited on"
                  + " Android yet.",
              14,
              secondary,
              false));
    }
    JSONArray subjects = store.object("timetable").optJSONArray("subjects");
    if (subjects != null) {
      gap(body, 16);
      body.addView(text("Subject quick notes", 20, ink, true));
      for (int i = 0; i < subjects.length(); i++) {
        String name = subjects.getJSONObject(i).optString("name");
        action(body, name, () -> newNote(name));
      }
    }
  }

  void newNote(String subject) {
    LinearLayout form = vertical();
    form.setPadding(dp(20), 0, dp(20), 0);
    EditText name = field(form, "Note title", subject.isEmpty() ? "Quick note" : subject);
    new AlertDialog.Builder(this)
        .setTitle("New note")
        .setView(form)
        .setNegativeButton("Cancel", null)
        .setPositiveButton(
            "Create",
            (d, w) -> {
              try {
                String id = UUID.randomUUID().toString().toUpperCase(Locale.ROOT);
                store.saveAsset(
                    id,
                    "note",
                    name.getText().toString().trim(),
                    subject,
                    new JSONObject().put("text", "").put("drawing", ""));
                editNote(store.assetIndex().getJSONObject(id));
              } catch (Exception e) {
                error(e);
              }
            })
        .show();
  }

  void openBook(JSONObject book) {
    try {
      JSONObject manifest = store.asset(book.getString("id"));
      JSONArray pages = manifest.optJSONArray("pageIDs");
      String[] labels = new String[(pages == null ? 0 : pages.length())];
      for (int i = 0; i < labels.length; i++) labels[i] = "Page " + (i + 1);
      if (labels.length == 0) {
        new AlertDialog.Builder(this)
            .setTitle(book.optString("title"))
            .setMessage(
                "This notebook has no saved pages. You can add pages in the Apple app, then Sync"
                    + " here, or create a quick note on Android.")
            .setPositiveButton("OK", null)
            .show();
        return;
      }
      new AlertDialog.Builder(this)
          .setTitle(book.optString("title"))
          .setItems(
              labels,
              (d, i) -> {
                try {
                  editNote(store.assetIndex().getJSONObject(pages.getString(i)));
                } catch (Exception e) {
                  error(e);
                }
              })
          .setNegativeButton("Close", null)
          .show();
    } catch (Exception e) {
      error(e);
    }
  }

  void editNote(JSONObject meta) {
    try {
      String id = meta.getString("id");
      JSONObject document = store.asset(id);
      boolean page = meta.optString("kind").equals("notebookPage");
      editor = new Dialog(this, android.R.style.Theme_Material_Light_NoActionBar);
      LinearLayout sheet = vertical();
      sheet.setBackgroundColor(0xFFF9F6EE);
      sheet.setPadding(dp(18), dp(16), dp(18), dp(18));
      LinearLayout bar = row();
      Button done =
          button(
              "Done",
              () -> {
                flushDraft();
                editor.dismiss();
              });
      bar.addView(done);
      TextView label = text(meta.optString("title", "Notebook"), 17, 0xFF17253B, true);
      label.setPadding(dp(12), 0, 0, 0);
      bar.addView(label, new LinearLayout.LayoutParams(0, -2, 1));
      sheet.addView(bar);
      ScrollView scroll = new ScrollView(this);
      LinearLayout paper = vertical();
      paper.setPadding(dp(12), dp(12), dp(12), dp(40));
      paper.setBackground(new PaperDrawable());
      scroll.addView(paper);
      sheet.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
      if (!document.optString("drawing").isEmpty()) {
        TextView warning =
            text(
                "Apple handwriting is preserved in this page. View it on your Apple device; typed"
                    + " text below remains editable here.",
                12,
                0xFF64748B,
                false);
        paper.addView(warning);
        gap(paper, 16);
      }
      List<EditText> fields = new ArrayList<>();
      JSONArray boxes = page ? document.optJSONArray("textObjects") : null;
      if (page && (boxes == null || boxes.length() == 0)) {
        boxes =
            new JSONArray()
                .put(
                    new JSONObject()
                        .put("id", UUID.randomUUID().toString().toUpperCase(Locale.ROOT))
                        .put("text", "")
                        .put("x", 48)
                        .put("y", 70)
                        .put("width", 490)
                        .put("height", 160)
                        .put("fontSize", 18)
                        .put("bold", false)
                        .put("italic", false)
                        .put("underline", false)
                        .put("alignment", "left")
                        .put(
                            "color",
                            new JSONObject()
                                .put("red", 0.12)
                                .put("green", 0.16)
                                .put("blue", 0.21)));
        document.put("textObjects", boxes);
      }
      int count = page ? boxes.length() : 1;
      for (int i = 0; i < count; i++) {
        EditText edit = new EditText(this);
        edit.setText(page ? boxes.getJSONObject(i).optString("text") : document.optString("text"));
        edit.setTextColor(0xFF17253B);
        edit.setTextSize(18);
        edit.setGravity(Gravity.TOP);
        edit.setMinLines(count == 1 ? 20 : 5);
        edit.setBackgroundColor(Color.TRANSPARENT);
        edit.setHint("Start writing…");
        edit.setHintTextColor(0xFF7A8797);
        edit.setLineSpacing(dp(10), 1);
        paper.addView(edit, new LinearLayout.LayoutParams(-1, -2));
        fields.add(edit);
      }
      final JSONArray textBoxes = boxes;
      Runnable save =
          () -> {
            try {
              for (int i = 0; i < fields.size(); i++) {
                if (page)
                  textBoxes.getJSONObject(i).put("text", fields.get(i).getText().toString());
                else document.put("text", fields.get(i).getText().toString());
              }
              if (page) document.put("modifiedAt", Snapshot.swiftNow());
              store.saveAsset(
                  id,
                  meta.getString("kind"),
                  meta.optString("title"),
                  meta.optString("subject"),
                  document);
            } catch (Exception e) {
              error(e);
            }
          };
      TextWatcher watcher =
          new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

            public void onTextChanged(CharSequence s, int start, int before, int count) {
              if (saveDraft != null) handler.removeCallbacks(saveDraft);
              saveDraft = save;
              handler.postDelayed(saveDraft, 600);
            }

            public void afterTextChanged(Editable e) {}
          };
      for (EditText edit : fields) edit.addTextChangedListener(watcher);
      editor.setContentView(sheet);
      editor.setOnDismissListener(
          d -> {
            flushDraft();
            editor = null;
            render();
          });
      editor.show();
      editor.getWindow().setLayout(-1, -1);
      editor.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    } catch (Exception e) {
      editor = null;
      error(e);
    }
  }

  void flushDraft() {
    if (saveDraft != null) {
      Runnable save = saveDraft;
      saveDraft = null;
      handler.removeCallbacks(save);
      save.run();
    }
  }

  void error(Exception e) {
    status = e.getMessage() == null ? "Could not complete this action" : e.getMessage();
    Toast.makeText(this, status, Toast.LENGTH_LONG).show();
  }

  static class PaperDrawable extends android.graphics.drawable.Drawable {
    Paint p = new Paint(3);

    public void draw(Canvas c) {
      c.drawColor(0xFFF9F6EE);
      p.setColor(0xFFD4DFE7);
      p.setStrokeWidth(1);
      for (int y = 48; y < getBounds().height(); y += 42)
        c.drawLine(0, y, getBounds().width(), y, p);
      p.setColor(0xFFE8B8B4);
      c.drawLine(18, 0, 18, getBounds().height(), p);
    }

    public void setAlpha(int a) {}

    public void setColorFilter(android.graphics.ColorFilter f) {}

    public int getOpacity() {
      return android.graphics.PixelFormat.OPAQUE;
    }
  }

  static class Icon extends View {
    Paint p = new Paint(3);
    int kind;

    Icon(Context c, int k, int color) {
      super(c);
      kind = k;
      p.setColor(color);
      p.setStrokeWidth(1.8f);
      p.setStyle(Paint.Style.STROKE);
      p.setStrokeCap(Paint.Cap.ROUND);
      p.setStrokeJoin(Paint.Join.ROUND);
    }

    protected void onDraw(Canvas canvas) {
      canvas.save();
      canvas.scale(getWidth() / 24f, getHeight() / 24f);
      switch (kind) {
        case 0:
          Path home = new Path();
          home.moveTo(3, 10);
          home.lineTo(12, 3);
          home.lineTo(21, 10);
          home.moveTo(5, 9);
          home.lineTo(5, 21);
          home.lineTo(19, 21);
          home.lineTo(19, 9);
          home.moveTo(9, 21);
          home.lineTo(9, 14);
          home.lineTo(15, 14);
          home.lineTo(15, 21);
          canvas.drawPath(home, p);
          break;
        case 1:
          canvas.drawRoundRect(3, 5, 21, 21, 3, 3, p);
          canvas.drawLine(3, 10, 21, 10, p);
          canvas.drawLine(8, 3, 8, 7, p);
          canvas.drawLine(16, 3, 16, 7, p);
          for (int y = 14; y <= 18; y += 4)
            for (int x = 7; x <= 17; x += 5) canvas.drawPoint(x, y, p);
          break;
        case 2:
          canvas.drawRoundRect(4, 3, 20, 21, 2, 2, p);
          canvas.drawLine(8, 3, 8, 21, p);
          canvas.drawLine(11, 8, 17, 8, p);
          canvas.drawLine(11, 12, 17, 12, p);
          break;
        case 3:
          canvas.drawLine(4, 21, 21, 21, p);
          canvas.drawRect(5, 13, 8, 20, p);
          canvas.drawRect(11, 8, 14, 20, p);
          canvas.drawRect(17, 3, 20, 20, p);
          break;
        default:
          canvas.drawCircle(12, 12, 7, p);
          canvas.drawCircle(12, 12, 2.5f, p);
          for (int i = 0; i < 8; i++) {
            double a = i * Math.PI / 4;
            canvas.drawLine(
                12 + (float) Math.cos(a) * 7,
                12 + (float) Math.sin(a) * 7,
                12 + (float) Math.cos(a) * 10,
                12 + (float) Math.sin(a) * 10,
                p);
          }
      }
      canvas.restore();
    }
  }
}
