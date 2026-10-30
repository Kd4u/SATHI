package com.karandeep.sathi;

import static org.junit.Assert.*;

import org.json.*;
import org.junit.Test;

public class ParityRulesTest {
  @Test
  public void firstProofTapHasSwiftRequiredFieldsAndPreservesUnknowns() throws Exception {
    JSONObject source = new JSONObject().put("fingerprint", true).put("futureField", "keep");
    JSONObject p = ParityRules.normaliseProof(source);
    assertTrue(p.getBoolean("fingerprint"));
    assertFalse(p.getBoolean("officialDuty"));
    assertTrue(p.getDouble("updatedAt") > 0);
    assertEquals("keep", p.getString("futureField"));
    assertFalse(source.has("officialDuty"));
  }

  @Test
  public void explicitOdAndTimestampSurviveNormalization() throws Exception {
    JSONObject p =
        ParityRules.normaliseProof(new JSONObject().put("officialDuty", true).put("updatedAt", 42));
    assertTrue(p.getBoolean("officialDuty"));
    assertEquals(42, p.getInt("updatedAt"));
  }

  @Test
  public void supplementCannotReplaceChangedOrMissingLecture() throws Exception {
    JSONObject row =
        new JSONObject()
            .put("id", "one")
            .put("date", "2026-11-01")
            .put("time", "09:00-10:30")
            .put("subject", "Course")
            .put("section", "A")
            .put("source", "A!C2");
    JSONObject prior = new JSONObject().put("sessions", new JSONArray().put(row));
    assertTrue(ParityRules.containsAll(new JSONObject(prior.toString()), prior));
    JSONObject changed = new JSONObject(prior.toString());
    changed.getJSONArray("sessions").getJSONObject(0).put("time", "10:00-11:30");
    assertFalse(ParityRules.containsAll(changed, prior));
    assertFalse(ParityRules.containsAll(new JSONObject().put("sessions", new JSONArray()), prior));
  }
}
