package com.karandeep.sathi;

import static org.junit.Assert.*;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.*;
import org.json.*;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Device-only checks; never reads or writes an account's saved files or cloud. */
@RunWith(AndroidJUnit4.class)
public class AndroidRuntimeTest {
  @Test public void nativeAppOpensAndCanCaptureOnboarding()throws Exception {
    android.app.Instrumentation instrumentation=InstrumentationRegistry.getInstrumentation();
    android.content.Context context=instrumentation.getTargetContext();
    android.content.Intent intent=new android.content.Intent(context,MainActivity.class).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
    android.app.Activity activity=instrumentation.startActivitySync(intent);
    instrumentation.waitForIdleSync();
    assertNotNull(activity.findViewById(android.R.id.content));
    // Render only SATHI's own laid-out view; do not capture other phone content.
    instrumentation.runOnMainSync(()->{
      android.view.View view=activity.findViewById(android.R.id.content);
      assertTrue(view.getWidth()>0&&view.getHeight()>0);
      android.graphics.Bitmap screenshot=android.graphics.Bitmap.createBitmap(view.getWidth(),view.getHeight(),android.graphics.Bitmap.Config.ARGB_8888);
      view.draw(new android.graphics.Canvas(screenshot));
      try(FileOutputStream out=new FileOutputStream(new File(context.getExternalFilesDir(null),"sathi-onboarding.png"))){assertTrue(screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,out));}
      catch(Exception e){throw new RuntimeException(e);}
    });
    instrumentation.runOnMainSync(activity::finish);
  }
  @Test public void xmlParserAndSwiftSnapshotWorkOnAndroid() throws Exception {
    Map<String,String> files=new LinkedHashMap<>();
    files.put("xl/workbook.xml","<workbook xmlns:r='urn:relationships'><sheets><sheet name='Section A' r:id='rId1'/></sheets></workbook>");
    files.put("xl/_rels/workbook.xml.rels","<Relationships><Relationship Id='rId1' Target='worksheets/sheet1.xml'/></Relationships>");
    files.put("xl/worksheets/sheet1.xml","<worksheet><sheetData><row r='1'><c r='A1' t='inlineStr'><is><t>Date</t></is></c><c r='B1' t='inlineStr'><is><t>Day</t></is></c><c r='C1' t='inlineStr'><is><t>09:00-10:00</t></is></c></row><row r='2'><c r='A2' t='inlineStr'><is><t>2026-10-27</t></is></c><c r='C2' t='inlineStr'><is><t>Course (Sec A)</t></is></c></row><row r='3'><c r='C3' t='inlineStr'><is><t>Prof. Example</t></is></c></row></sheetData></worksheet>");
    ByteArrayOutputStream bytes=new ByteArrayOutputStream();
    try(ZipOutputStream zip=new ZipOutputStream(bytes)){for(String path:files.keySet()){zip.putNextEntry(new ZipEntry(path));zip.write(files.get(path).getBytes(StandardCharsets.UTF_8));zip.closeEntry();}}
    JSONObject report=ExcelImport.read(bytes.toByteArray(),"device-fixture.xlsx");
    assertEquals("Sheet1-C2-0",report.getJSONArray("sessions").getJSONObject(0).getString("id"));
    Map<String,String> records=Map.of("timetable",Snapshot.value(report));
    assertEquals(records,Snapshot.decode(Snapshot.encode(records)));
  }
  @Test public void atomicSaveAndBoundedReaderWork()throws Exception {
    File file=File.createTempFile("sathi-runtime-test", ".json",InstrumentationRegistry.getInstrumentation().getTargetContext().getCacheDir());
    try{Store.atomic(file,"{\"test\":true}".getBytes(StandardCharsets.UTF_8));assertTrue(new JSONObject(new String(IO.read(new FileInputStream(file),1000),StandardCharsets.UTF_8)).getBoolean("test"));}
    finally{assertTrue(file.delete());}
  }
}
