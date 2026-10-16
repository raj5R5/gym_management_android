package com.it_nomads.fluttersecurestorage;

import android.content.Context;
import android.content.ContextWrapper;
import android.content.SharedPreferences;
import android.os.Looper;
import com.it_nomads.fluttersecurestorage.ciphers.StorageCipher;
import com.it_nomads.fluttersecurestorage.ciphers.StorageCipherImplementationGCM;
import com.it_nomads.fluttersecurestorage.ciphers.StorageCipherFactory;
import com.it_nomads.fluttersecurestorage.ciphers.KeyCipher;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.Arrays;
import java.security.Key;
import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

/** Actual MethodRunner/queue/storage with injected API-24 preferences and cipher. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 24)
public class StoragePluginCoordinationTest {
    final OnboardingDurabilityTest fixture = new OnboardingDurabilityTest();
    final OnboardingDurabilityTest.Prefs records = fixture.new Prefs("records");
    final OnboardingDurabilityTest.Prefs keys = fixture.new Prefs("keys");
    final OnboardingDurabilityTest.Prefs config = fixture.new Prefs("config");
    final OnboardingDurabilityTest.Prefs legacy = fixture.new Prefs("legacy");
    final Map<String, Object> options = new HashMap<>();
    final FlutterSecureStoragePlugin first = new FlutterSecureStoragePlugin();
    final FlutterSecureStoragePlugin second = new FlutterSecureStoragePlugin();
    TestStorage firstStorage, secondStorage;
    Context context;

    static void set(Object object, Class<?> type, String name, Object value) throws Exception {
        Field field = type.getDeclaredField(name); field.setAccessible(true); field.set(object, value);
    }
    final class TestStorage extends FlutterSecureStorage {
        final AtomicInteger initializations = new AtomicInteger();
        final CountDownLatch entered = new CountDownLatch(1);
        volatile boolean holdInitialization;
        volatile SecurePreferencesCallback<Void> continuation;
        TestStorage() throws Exception {
            super(context);
            set(this, FlutterSecureStorage.class, "config", new FlutterSecureStorageConfig(options));
            set(this, FlutterSecureStorage.class, "preferences", records.preferences());
            set(this, FlutterSecureStorage.class, "storageCipher", new StorageCipher() {
                @Override public byte[] encrypt(byte[] value) { return value; }
                @Override public byte[] decrypt(byte[] value) { return value; }
                @Override public void deleteKey(Context unused) { fail("unexpected key deletion"); }
            });
        }
        @Override public void initialize(FlutterSecureStorageConfig unused, SecurePreferencesCallback<Void> callback) {
            initializations.incrementAndGet(); continuation = callback; entered.countDown();
            if (!holdInitialization) callback.onSuccess(null);
        }
    }
    static final class Result implements MethodChannel.Result {
        volatile boolean done;
        Object value;
        String error;
        int terminals;
        @Override public void success(Object value) { this.value = value; terminals++; done = true; }
        @Override public void error(String code, String message, Object details) { error = code; terminals++; done = true; }
        @Override public void notImplemented() { error = "notImplemented"; terminals++; done = true; }
        void await() throws Exception {
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
            while (!done && System.nanoTime() < deadline) {
                Shadows.shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(5);
            }
            assertTrue("terminal callback missing", done); assertEquals(1, terminals);
        }
    }
    @SuppressWarnings("unchecked")
    void seed(FlutterSecureStoragePlugin plugin, TestStorage storage) throws Exception {
        set(plugin, FlutterSecureStoragePlugin.class, "applicationContext", context);
        Field field = FlutterSecureStoragePlugin.class.getDeclaredField("storagesBySharedPreferencesName");
        field.setAccessible(true);
        FlutterSecureStorageConfig configuration = new FlutterSecureStorageConfig(options);
        ((Map<String, FlutterSecureStorage>) field.get(plugin)).put(
                configuration.getSharedPreferencesName() + "|" + configuration.getSharedPreferencesKeyPrefix(), storage);
    }
    @Before public void setUp() throws Exception {
        options.put("resetOnError", false); options.put("preferencesKeyPrefix", "test");
        context = new ContextWrapper(RuntimeEnvironment.getApplication()) {
            @Override public Context getApplicationContext() { return this; }
            @Override public SharedPreferences getSharedPreferences(String name, int mode) {
                if (name.equals("FlutterSecureKeyStorage")) return keys.preferences();
                if (name.equals("FlutterSecureStorageConfiguration:FlutterSecureStorage")) return config.preferences();
                if (name.equals("FlutterSecureStorageConfiguration")) return legacy.preferences();
                throw new AssertionError(name);
            }
        };
        keys.cache.put(StorageCipherImplementationGCM.WRAPPED_KEY_PREF, "wrapped-key");
        config.cache.put("FlutterSecureSAlgorithmKey", "RSA_ECB_OAEPwithSHA_256andMGF1Padding");
        config.cache.put("FlutterSecureSAlgorithmStorage", "AES_GCM_NoPadding");
        firstStorage = new TestStorage(); secondStorage = new TestStorage();
        seed(first, firstStorage); seed(second, secondStorage);
    }
    Result call(FlutterSecureStoragePlugin plugin, String method, String key, String value) {
        Result result = new Result();
        Map<String, Object> arguments = new HashMap<>();
        arguments.put("options", options); arguments.put("key", key); arguments.put("value", value);
        plugin.onMethodCall(new MethodCall(method, arguments), result);
        return result;
    }
    String plaintext(String key) {
        return new String(android.util.Base64.decode((String) records.cache.get("test_" + key), 0), StandardCharsets.UTF_8);
    }

    @Test public void paymentRecoveryUsesExistingBarrierAndRejectsAuthenticationKeys() throws Exception {
        Result write = call(first, "writeOnboarding", "gym.payment.v1.test.pending", "frozen-payment");
        write.await(); assertNull(write.error);
        Result read = call(second, "readOnboarding", "gym.payment.v1.test.pending", null);
        read.await(); assertNull(read.error);
        assertEquals("frozen-payment", read.value);
        assertEquals("frozen-payment", plaintext("gym.payment.v1.test.pending"));
        Result denied = call(first, "writeOnboarding", "auth.refresh", "credential");
        denied.await(); assertNotNull(denied.error);
    }

    @Test public void anotherPluginAuthWriteWaitsUntilSnapshotCommitFinishes() throws Exception {
        Result initial = call(first, "write", "auth", "old"); initial.await();
        Result[] concurrent = new Result[1];
        records.afterSnapshot = () -> {
            records.afterSnapshot = null;
            concurrent[0] = call(second, "write", "auth", "rotated");
            assertEquals(0, secondStorage.initializations.get());
            assertEquals("old", plaintext("auth"));
        };
        Result barrier = call(first, "writeOnboarding", "gym.onboarding.v1.a.pending", "frozen-a");
        barrier.await(); concurrent[0].await();
        assertNull(barrier.error); assertNull(concurrent[0].error);
        Result flush = call(second, "readOnboarding", "gym.onboarding.v1.a.pending", null); flush.await();
        records.restart(); assertEquals("rotated", plaintext("auth"));
        assertEquals("frozen-a", plaintext("gym.onboarding.v1.a.pending"));
        assertEquals(2, records.applies); // Auth still uses apply(), not commit().
    }
    @Test public void anotherPluginPendingAddSurvivesBarrierAndRestart() throws Exception {
        Result[] concurrent = new Result[1];
        records.afterSnapshot = () -> {
            records.afterSnapshot = null;
            concurrent[0] = call(second, "writeOnboarding", "gym.onboarding.v1.b.pending", "frozen-b");
            assertEquals(0, secondStorage.initializations.get());
        };
        Result barrier = call(first, "writeOnboarding", "gym.onboarding.v1.a.pending", "frozen-a");
        barrier.await(); concurrent[0].await();
        assertNull(barrier.error); assertNull(concurrent[0].error);
        records.restart();
        assertEquals("frozen-a", plaintext("gym.onboarding.v1.a.pending"));
        assertEquals("frozen-b", plaintext("gym.onboarding.v1.b.pending"));
    }
    @Test public void anotherPluginDeleteCannotBeUndoneBySnapshot() throws Exception {
        call(first, "write", "auth", "old").await();
        Result[] deletion = new Result[1];
        records.afterSnapshot = () -> {
            records.afterSnapshot = null;
            deletion[0] = call(second, "delete", "auth", null);
            assertEquals(0, secondStorage.initializations.get());
        };
        Result barrier = call(first, "writeOnboarding", "gym.onboarding.v1.a.pending", "frozen");
        barrier.await(); deletion[0].await();
        assertNull(barrier.error); assertFalse(records.cache.containsKey("test_auth"));
        call(first, "readOnboarding", "gym.onboarding.v1.a.pending", null).await();
        records.restart(); assertFalse(records.cache.containsKey("test_auth"));
    }
    @Test public void asynchronousInitializationBlocksEveryOtherPluginUntilCompletion() throws Exception {
        firstStorage.holdInitialization = true;
        Result firstResult = call(first, "writeOnboarding", "gym.onboarding.v1.a.pending", "frozen");
        assertTrue(firstStorage.entered.await(10, TimeUnit.SECONDS));
        Result secondResult = call(second, "write", "auth", "rotated");
        assertEquals(0, secondStorage.initializations.get()); assertTrue(records.cache.isEmpty());
        Thread continuation = new Thread(() -> firstStorage.continuation.onSuccess(null));
        continuation.start(); continuation.join(10000); assertFalse(continuation.isAlive());
        firstResult.await(); secondResult.await();
        assertNull(firstResult.error); assertNull(secondResult.error);
        assertEquals("rotated", plaintext("auth"));
    }
    @Test public void detachedEngineDoesNotReleaseItsActiveOperationOrLoseCapturedContext() throws Exception {
        firstStorage.holdInitialization = true;
        Result active = call(first, "writeOnboarding", "gym.onboarding.v1.a.pending", "frozen");
        assertTrue(firstStorage.entered.await(10, TimeUnit.SECONDS));
        Result acceptedBeforeDetach = call(first, "write", "auth", "rotated");
        first.onDetachedFromEngine(null);
        Result otherEngine = call(second, "readOnboarding", "gym.onboarding.v1.a.pending", null);
        assertEquals(0, secondStorage.initializations.get());
        // Re-seed the test storage after the detach cleared its cache. The accepted
        // runner must still use its captured context, not the now-null plugin field.
        seed(first, firstStorage); set(first, FlutterSecureStoragePlugin.class, "applicationContext", null);
        firstStorage.holdInitialization = false;
        firstStorage.continuation.onSuccess(null);
        active.await(); acceptedBeforeDetach.await(); otherEngine.await();
        assertNull(active.error); assertNull(acceptedBeforeDetach.error); assertNull(otherEngine.error);
        assertEquals("rotated", plaintext("auth"));
        Result refused = call(first, "write", "auth", "wrong"); refused.await();
        assertEquals("storage_unavailable", refused.error); assertEquals("rotated", plaintext("auth"));
    }
    @Test public void failedCommitDoesNotAcknowledgeOrStrandOtherPlugin() throws Exception {
        records.fail = true;
        Result failed = call(first, "writeOnboarding", "gym.onboarding.v1.a.pending", "frozen");
        Result other = call(second, "write", "auth", "rotated");
        failed.await(); other.await();
        assertEquals("onboarding_persistence", failed.error); assertNull(other.error);
        assertEquals("rotated", plaintext("auth")); assertTrue(records.disk.isEmpty());
    }
    @Test public void commitThenThrowDoesNotAcknowledgeAndLaterBarrierRecovers() throws Exception {
        records.throwAfter = true;
        Result failed = call(first, "writeOnboarding", "gym.onboarding.v1.a.pending", "frozen"); failed.await();
        assertEquals("onboarding_persistence", failed.error); assertFalse(records.disk.isEmpty());
        records.throwAfter = false;
        Result recovered = call(second, "readOnboarding", "gym.onboarding.v1.a.pending", null); recovered.await();
        assertNull(recovered.error); assertEquals("frozen", recovered.value);
    }
    @Test public void terminalResultIsDeliveredOnlyOnce() throws Exception {
        Result raw = new Result(); AtomicInteger releases = new AtomicInteger();
        FlutterSecureStoragePlugin.MethodResultWrapper wrapper =
                new FlutterSecureStoragePlugin.MethodResultWrapper(raw, releases::incrementAndGet);
        wrapper.success("ok"); wrapper.error("late", "late", null); wrapper.notImplemented();
        raw.await(); assertEquals("ok", raw.value); assertEquals(1, releases.get());
    }
    @Test public void realFactoryAndWrappedKeyCreationAreSerializedAcrossInitializationContinuations() throws Exception {
        keys.cache.clear(); config.cache.clear();
        firstStorage.holdInitialization = true; secondStorage.holdInitialization = true;
        Result firstResult = call(first, "writeOnboarding", "gym.onboarding.v1.a.pending", "frozen-a");
        assertTrue(firstStorage.entered.await(10, TimeUnit.SECONDS));
        Result secondResult = call(second, "writeOnboarding", "gym.onboarding.v1.b.pending", "frozen-b");
        assertEquals(0, secondStorage.initializations.get());
        KeyCipher wrappingCipher = new KeyCipher() {
            @Override public Cipher getCipher(Context unused) { return null; }
            @Override public void deleteKey() { fail("unexpected key deletion"); }
            @Override public byte[] wrap(Key key) { return key.getEncoded(); }
            @Override public Key unwrap(byte[] wrapped, String algorithm) { return new SecretKeySpec(wrapped, algorithm); }
        };
        FlutterSecureStorageConfig configuration = new FlutterSecureStorageConfig(options);
        // Real production constructors run in the first operation's async continuation.
        StorageCipherFactory factory = new StorageCipherFactory(new NamespacedConfigSource(context,
                configuration.getEffectiveDataPrefsName()), configuration.getPrefOptionKeyCipherAlgorithm(),
                configuration.getPrefOptionStorageCipherAlgorithm(), configuration);
        assertFalse(factory.requiresReEncryption());
        StorageCipher firstCipher = new StorageCipherImplementationGCM(context, wrappingCipher, null, configuration);
        set(firstStorage, FlutterSecureStorage.class, "storageCipher", firstCipher);
        String wrapped = keys.preferences().getString(StorageCipherImplementationGCM.WRAPPED_KEY_PREF, null);
        assertNotNull(wrapped); assertEquals(0, secondStorage.initializations.get());
        firstStorage.continuation.onSuccess(null); firstResult.await();
        assertTrue(secondStorage.entered.await(10, TimeUnit.SECONDS));
        StorageCipherFactory secondFactory = new StorageCipherFactory(new NamespacedConfigSource(context,
                configuration.getEffectiveDataPrefsName()), configuration.getPrefOptionKeyCipherAlgorithm(),
                configuration.getPrefOptionStorageCipherAlgorithm(), configuration);
        assertFalse(secondFactory.requiresReEncryption());
        StorageCipher secondCipher = new StorageCipherImplementationGCM(context, wrappingCipher, null, configuration);
        assertEquals(wrapped, keys.preferences().getString(StorageCipherImplementationGCM.WRAPPED_KEY_PREF, null));
        assertEquals(1, keys.applies); assertEquals(1, config.applies);
        byte[] message = "same-key".getBytes(StandardCharsets.UTF_8);
        assertTrue(Arrays.equals(message, secondCipher.decrypt(firstCipher.encrypt(message))));
        set(secondStorage, FlutterSecureStorage.class, "storageCipher", secondCipher);
        secondStorage.continuation.onSuccess(null); secondResult.await();
        assertNull(firstResult.error); assertNull(secondResult.error);
        assertEquals(wrapped, keys.disk.get(StorageCipherImplementationGCM.WRAPPED_KEY_PREF));
        assertEquals(config.cache, config.disk); assertEquals(2, records.disk.size());
    }
}
