package com.it_nomads.fluttersecurestorage;

import android.content.Context;
import android.content.ContextWrapper;
import android.content.SharedPreferences;
import com.it_nomads.fluttersecurestorage.ciphers.StorageCipher;
import com.it_nomads.fluttersecurestorage.ciphers.StorageCipherImplementationGCM;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

/** Exercises the actual opt-in native bridge with an injected test cipher. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 24)
public class OnboardingNativeBridgeTest {
    final OnboardingDurabilityTest fixture = new OnboardingDurabilityTest();
    final OnboardingDurabilityTest.Prefs keys = fixture.new Prefs("keys");
    final OnboardingDurabilityTest.Prefs configuration = fixture.new Prefs("config");
    final OnboardingDurabilityTest.Prefs legacy = fixture.new Prefs("legacy");
    final OnboardingDurabilityTest.Prefs records = fixture.new Prefs("records");
    FlutterSecureStorage storage;
    final String key = "prefix_gym.onboarding.v1.test.pending";
    boolean acknowledged;
    Exception failure;
    String value;
    void field(String name, Object value) throws Exception {
        Field field=FlutterSecureStorage.class.getDeclaredField(name);field.setAccessible(true);field.set(storage,value);
    }
    @Before public void setUp() throws Exception {
        Context context = new ContextWrapper(RuntimeEnvironment.getApplication()) {
            @Override public Context getApplicationContext() { return this; }
            @Override public SharedPreferences getSharedPreferences(String name, int mode) {
                if (name.equals("FlutterSecureKeyStorage")) return keys.preferences();
                if (name.equals("FlutterSecureStorageConfiguration:FlutterSecureStorage")) return configuration.preferences();
                if (name.equals("FlutterSecureStorageConfiguration")) return legacy.preferences();
                throw new AssertionError(name);
            }
        };
        storage=new FlutterSecureStorage(context);
        Map<String,Object> options=new HashMap<>();options.put("resetOnError",false);
        field("config",new FlutterSecureStorageConfig(options));field("preferences",records.preferences());
        field("storageCipher",new StorageCipher() {
            @Override public byte[] encrypt(byte[] input) { return input; }
            @Override public byte[] decrypt(byte[] input) { return input; }
            @Override public void deleteKey(Context context) { fail("key deleted"); }
        });
        keys.cache.put(StorageCipherImplementationGCM.WRAPPED_KEY_PREF,"wrapped-synthetic-key");
        configuration.cache.put("FlutterSecureSAlgorithmKey","RSA_ECB_OAEPwithSHA_256andMGF1Padding");
        configuration.cache.put("FlutterSecureSAlgorithmStorage","AES_GCM_NoPadding");
    }
    void invoke(String method,String data) {
        acknowledged=false;failure=null;value=null;
        storage.onboarding(method,key,data,new SecurePreferencesCallback<String>() {
            @Override public void onSuccess(String result) { acknowledged=true;value=result; }
            @Override public void onError(Exception e) { failure=e; }
        });
    }
    @Test public void successfulWriteAcknowledgesOnlyCommittedRecordAndMetadata() {
        invoke("writeOnboarding","original-body-and-key");
        assertTrue(acknowledged);assertNull(failure);assertEquals("original-body-and-key",value);
        assertEquals(keys.cache,keys.disk);assertEquals(configuration.cache,configuration.disk);assertEquals(records.cache,records.disk);
        assertEquals(0,keys.applies+configuration.applies+legacy.applies+records.applies);
    }
    @Test public void failedKeyCommitDoesNotWriteOrAcknowledgeRecord() {
        keys.fail=true;invoke("writeOnboarding","frozen");assertFalse(acknowledged);assertNotNull(failure);assertTrue(records.cache.isEmpty());
    }
    @Test public void missingWrappedKeyFailsClosed() {
        keys.cache.clear();invoke("writeOnboarding","frozen");assertFalse(acknowledged);assertNotNull(failure);assertTrue(records.cache.isEmpty());
    }
    @Test public void failedConfigurationCommitDoesNotWriteRecord() {
        configuration.fail=true;invoke("writeOnboarding","frozen");assertFalse(acknowledged);assertNotNull(failure);assertTrue(records.cache.isEmpty());
    }
    @Test public void failedRecordCommitAndCachedReadCannotAcknowledge() {
        invoke("writeOnboarding","original");assertTrue(acknowledged);
        records.fail=true;invoke("writeOnboarding","replacement");assertFalse(acknowledged);assertNotNull(failure);
        invoke("readOnboarding",null);assertFalse(acknowledged);assertNotNull(failure);
        assertEquals(0,records.removes);records.restart();records.fail=false;
        invoke("readOnboarding",null);assertTrue(acknowledged);assertEquals("original",value);
    }
    @Test public void readCanCertifySameCandidateOnlyAfterNewSuccessfulCommit() {
        invoke("writeOnboarding","original");records.fail=true;
        invoke("writeOnboarding","frozen-replacement");assertFalse(acknowledged);
        records.fail=false;invoke("readOnboarding",null);assertTrue(acknowledged);assertEquals("frozen-replacement",value);
        records.restart();invoke("readOnboarding",null);assertEquals("frozen-replacement",value);
    }
    @Test public void writeThenThrowRequiresNewBarrierBeforeAcknowledgement() {
        records.throwAfter=true;invoke("writeOnboarding","frozen");assertFalse(acknowledged);assertNotNull(failure);
        records.throwAfter=false;invoke("readOnboarding",null);assertTrue(acknowledged);assertEquals("frozen",value);
    }

    @Test public void api24FailedConfirmationCannotExposeVolatileSuccess() {
        invoke("writeOnboarding", "dispatched-unconfirmed"); assertTrue(acknowledged);
        records.fail=true; invoke("writeOnboarding", "confirmed-result");
        assertFalse(acknowledged);
        // Reproduce the old verification implementation returning true while
        // disk still contains the original unresolved operation.
        assertTrue(records.preferences().edit().putString(key, (String) records.cache.get(key)).commit());
        assertEquals(1, records.shortcuts);
        invoke("readOnboarding", null); assertFalse(acknowledged); assertNotNull(failure);
        records.restart(); records.fail=false;
        invoke("readOnboarding", null); assertTrue(acknowledged);
        assertEquals("dispatched-unconfirmed", value);
    }
    @Test public void api24FailedDispatchMarkerAndUnchangedReadRemainBlocked() {
        invoke("writeOnboarding", "prepared-request-and-key"); assertTrue(acknowledged);
        records.fail=true; invoke("writeOnboarding", "dispatch-marker"); assertFalse(acknowledged);
        assertTrue(records.preferences().edit().putString(key, (String) records.cache.get(key)).commit());
        invoke("readOnboarding", null); assertFalse(acknowledged);
        records.restart(); records.fail=false;
        invoke("readOnboarding", null); assertEquals("prepared-request-and-key", value);
    }
    @Test public void api24WrappedKeyInitializationFailureBlocksRecordAndRecoveryRead() {
        keys.diskFileExists=true; keys.fail=true;
        // The upstream cipher's apply() exposes the new wrapped key in memory.
        keys.preferences().edit().putString(StorageCipherImplementationGCM.WRAPPED_KEY_PREF, "wrapped-synthetic-key").apply();
        invoke("writeOnboarding", "dispatch-marker"); assertFalse(acknowledged);
        invoke("readOnboarding", null); assertFalse(acknowledged);
        assertTrue(keys.disk.isEmpty()); assertTrue(records.disk.isEmpty());
    }
    @Test public void api24ConfigurationInitializationFailureBlocksConfirmation() {
        invoke("writeOnboarding", "dispatched-unconfirmed"); assertTrue(acknowledged);
        configuration.disk.clear(); configuration.diskFileExists=true; configuration.fail=true;
        invoke("writeOnboarding", "confirmed-result"); assertFalse(acknowledged);
        invoke("readOnboarding", null); assertFalse(acknowledged);
        assertEquals(records.disk, records.cache); // confirmation was never stored
    }

    @Test public void ordinaryAuthenticationWriteStillUsesUpstreamApply() {
        storage.write("prefix_authentication.refresh", "synthetic", new SecurePreferencesCallback<Void>() {
            @Override public void onSuccess(Void unused) { acknowledged=true; }
            @Override public void onError(Exception e) { failure=e; }
        });
        assertTrue(acknowledged); assertNull(failure);
        assertEquals(1, records.applies); assertEquals(0, records.diskWrites);
        assertTrue(records.disk.isEmpty()); assertFalse(records.cache.isEmpty());
    }
}
