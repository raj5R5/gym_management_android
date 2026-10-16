package com.it_nomads.fluttersecurestorage;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;
import java.nio.charset.StandardCharsets;
import java.io.FileInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Real framework SharedPreferences, NOT Robolectric/proxies. This fault-injection
 * failure suite requires API 24 because it accesses API-24 internals. Other API
 * levels run disk and coordination smoke tests. Cold reconstruction
 * reloads actual XML; it is not a process-kill test. This SDK-only runner needs
 * no optional android.test library or additional dependencies.
 */
public class OnboardingPlatformDurabilityTest extends Instrumentation {
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }

    interface Test { void run() throws Exception; }

    @Override public void onStart() {
        int passed = 0;
        Bundle result = new Bundle();
        Test[] tests = Build.VERSION.SDK_INT == 24 ? new Test[] {
            this::testWholeMapReplacementOnDisk,
            this::testQueuedWritersPreserveWholeMapOnDisk,
            this::testFailedConfirmationUnchangedShortcutAndFixedBarrier,
            this::testIdenticalWriteCannotUseUnchangedShortcut,
            this::testWrappedKeyInitializationFailureCannotPassBarrier,
            this::testCipherConfigurationInitializationFailureCannotPassBarrier,
            this::testFailedLastRecordDeleteKeepsEmptyCacheBlocked,
        } : new Test[] { this::testWholeMapReplacementOnDisk, this::testQueuedWritersPreserveWholeMapOnDisk };
        try {
            for (Test test : tests) {
                setUp();
                try { test.run(); passed++; }
                finally { tearDown(); }
            }
            result.putString("stream", "Passed " + passed + " real-framework tests on API "
                + Build.VERSION.SDK_INT + (Build.VERSION.SDK_INT == 24 ? "" :
                "; API-24 fault injection NOT RUN (requires API 24)") + "\n");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable failure) {
            result.putString("stream", "FAILED after " + passed + " tests: " + failure + "\n");
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private static void assertTrue(boolean value) { if (!value) throw new AssertionError("Expected true"); }
    private static void assertFalse(boolean value) { if (value) throw new AssertionError("Expected false"); }
    private static void assertNull(Object value) { if (value != null) throw new AssertionError("Expected null"); }
    private static void assertEquals(Object expected, Object actual) {
        if (!java.util.Objects.equals(expected, actual)) throw new AssertionError("Expected " + expected + ", got " + actual);
    }
    private static void fail(String message) { throw new AssertionError(message); }

    private SharedPreferences preferences;
    private File file;
    private Field backupField;
    private Object originalBackup;

    private void setUp() throws Exception {
        backupField = null;
        Context context = getTargetContext();
        String name = "onboarding_durability_test_" + UUID.randomUUID();
        preferences = context.getSharedPreferences(name, Context.MODE_PRIVATE);
        assertEquals("android.app.SharedPreferencesImpl", preferences.getClass().getName());
        file = new File(context.getApplicationInfo().dataDir, "shared_prefs/" + name + ".xml");
        if (Build.VERSION.SDK_INT == 24) {
            backupField = preferences.getClass().getDeclaredField("mBackupFile");
            backupField.setAccessible(true);
            originalBackup = backupField.get(preferences);
        }
    }

    private void failRename() throws Exception {
        // Existing XML cannot rename into a nonexistent directory. API 24 keeps
        // the old file and returns false after already changing its cached map.
        backupField.set(preferences, new File(file.getParentFile(),
            "missing_" + UUID.randomUUID() + "/" + file.getName() + ".bak"));
    }

    private SharedPreferences coldRead() throws Exception {
        Constructor<?> constructor = preferences.getClass().getDeclaredConstructor(File.class, int.class);
        constructor.setAccessible(true);
        return (SharedPreferences) constructor.newInstance(file, Context.MODE_PRIVATE);
    }

    private void requireBarrierFailure() throws Exception {
        try { OnboardingDurability.flush(preferences); fail("volatile cache acknowledged"); }
        catch (IOException expected) { }
    }

    private String readXml() throws Exception {
        try (FileInputStream stream = new FileInputStream(file);
             ByteArrayOutputStream bytes = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[1024]; int count;
            while ((count = stream.read(buffer)) != -1) bytes.write(buffer, 0, count);
            return new String(bytes.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    public void testWholeMapReplacementOnDisk() throws Exception {
        OnboardingDurability.put(preferences, "record", "frozen-body-and-key");
        assertTrue(preferences.edit().putString("auth", "synthetic").commit());
        OnboardingDurability.flush(preferences);
        // Read the actual XML file, not SharedPreferences' same-process cache.
        String xml = readXml();
        assertTrue(xml.contains("frozen-body-and-key"));
        assertTrue(xml.contains("synthetic"));
        OnboardingDurability.put(preferences, "record", "confirmed");
        xml = readXml();
        assertTrue(xml.contains("confirmed"));
        assertFalse(xml.contains("frozen-body-and-key"));
        assertTrue(xml.contains("synthetic"));
    }

    public void testQueuedWritersPreserveWholeMapOnDisk() throws Exception {
        ExecutorService executor = Executors.newSingleThreadExecutor();
        StorageOperationQueue queue = new StorageOperationQueue(executor);
        AtomicReference<Runnable> release = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();
        CountDownLatch entered = new CountDownLatch(1), done = new CountDownLatch(1);
        try {
            OnboardingDurability.put(preferences, "scope-a", "frozen-a");
            assertTrue(preferences.edit().putString("auth", "old").putString("obsolete", "old").commit());
            queue.submit(complete -> {
                release.set(() -> {
                    try { OnboardingDurability.flush(preferences); }
                    catch (Throwable error) { failure.set(error); }
                    finally { complete.run(); }
                });
                entered.countDown(); // Simulate asynchronous ownership by engine A.
            });
            assertTrue(entered.await(10, TimeUnit.SECONDS));
            queue.submit(complete -> {
                try {
                    // Normal auth remains apply(); the next checked barrier flushes it.
                    preferences.edit().putString("auth", "rotated").remove("obsolete").apply();
                    OnboardingDurability.put(preferences, "scope-b", "frozen-b");
                } catch (Throwable error) { failure.set(error); }
                finally { complete.run(); done.countDown(); }
            });
            assertEquals("old", preferences.getString("auth", null));
            assertNull(preferences.getString("scope-b", null));
            release.getAndSet(null).run();
            assertTrue(done.await(10, TimeUnit.SECONDS));
            if (failure.get() != null) throw new AssertionError(failure.get());
            String xml = readXml();
            assertTrue(xml.contains("rotated")); assertFalse(xml.contains("obsolete"));
            assertTrue(xml.contains("frozen-a")); assertTrue(xml.contains("frozen-b"));
        } finally {
            // The test owns its executor; production's process-wide queue is never
            // stopped by engine detach. Let all submitted work finish before cleanup.
            Runnable pendingRelease = release.getAndSet(null);
            if (pendingRelease != null) pendingRelease.run();
            executor.shutdown(); assertTrue(executor.awaitTermination(10, TimeUnit.SECONDS));
        }
    }

    public void testFailedConfirmationUnchangedShortcutAndFixedBarrier() throws Exception {
        assertTrue(preferences.edit().putString("record", "unconfirmed").putString("auth", "synthetic").commit());
        failRename();
        assertFalse(preferences.edit().putString("record", "confirmed").commit());
        assertEquals("confirmed", preferences.getString("record", null));
        assertTrue(preferences.edit().putString("record", "confirmed").commit());
        assertEquals("unconfirmed", coldRead().getString("record", null));
        requireBarrierFailure();
        assertEquals("unconfirmed", coldRead().getString("record", null));
        backupField.set(preferences, originalBackup);
        OnboardingDurability.flush(preferences);
        assertEquals("confirmed", coldRead().getString("record", null));
        assertEquals("synthetic", coldRead().getString("auth", null));
    }

    public void testIdenticalWriteCannotUseUnchangedShortcut() throws Exception {
        assertTrue(preferences.edit().putString("record", "frozen").commit());
        failRename();
        try { OnboardingDurability.put(preferences, "record", "frozen"); fail("unchanged write acknowledged"); }
        catch (IOException expected) { }
        assertEquals("frozen", coldRead().getString("record", null));
    }

    public void testWrappedKeyInitializationFailureCannotPassBarrier() throws Exception {
        assertTrue(preferences.edit().putString("existing", "old").commit());
        failRename();
        assertFalse(preferences.edit().putString("wrapped-key", "new-key").commit());
        assertTrue(preferences.edit().putString("wrapped-key", "new-key").commit());
        requireBarrierFailure();
        assertNull(coldRead().getString("wrapped-key", null));
    }

    public void testCipherConfigurationInitializationFailureCannotPassBarrier() throws Exception {
        assertTrue(preferences.edit().putString("existing", "old").commit());
        failRename();
        assertFalse(preferences.edit().putString("cipher", "GCM").commit());
        assertTrue(preferences.edit().putString("cipher", "GCM").commit());
        requireBarrierFailure();
        assertNull(coldRead().getString("cipher", null));
    }

    public void testFailedLastRecordDeleteKeepsEmptyCacheBlocked() throws Exception {
        assertTrue(preferences.edit().putString("record", "confirmed").commit());
        failRename();
        try { OnboardingDurability.remove(preferences, "record"); fail("delete acknowledged"); }
        catch (IOException expected) { }
        assertNull(preferences.getString("record", null));
        assertTrue(preferences.edit().commit()); // the exact API-24 false-success case
        requireBarrierFailure();
        assertEquals("confirmed", coldRead().getString("record", null));
    }

    private void tearDown() throws Exception {
        if (backupField != null) backupField.set(preferences, originalBackup);
        if (file != null) { file.delete(); new File(file.getPath() + ".bak").delete(); }

    }
}
