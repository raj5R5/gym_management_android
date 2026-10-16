package com.it_nomads.fluttersecurestorage;

import android.content.SharedPreferences;
import java.io.IOException;
import java.lang.reflect.Proxy;
import java.util.*;
import org.junit.Test;
import static org.junit.Assert.*;

public class OnboardingDurabilityTest {
    private final List<String> events = new ArrayList<>();
    final class Prefs {
        final Map<String, Object> cache = new HashMap<>(), disk = new HashMap<>();
        final String name;
        boolean fail, throwAfter, diskFileExists;
        int shortcuts, diskWrites;
        private SharedPreferences instance;
        int applies, removes;
        Runnable afterSnapshot;
        Prefs(String name) { this.name = name; }
        SharedPreferences preferences() {
            if (instance != null) return instance;
            instance = (SharedPreferences) Proxy.newProxyInstance(getClass().getClassLoader(),
                new Class[]{SharedPreferences.class}, (proxy, method, args) -> {
                switch (method.getName()) {
                    case "hashCode": return System.identityHashCode(proxy);
                    case "equals": return proxy == args[0];
                    case "getAll": {
                        Map<String, Object> snapshot = new HashMap<>(cache);
                        if (afterSnapshot != null) afterSnapshot.run();
                        return snapshot;
                    }
                    case "getString": return cache.getOrDefault(args[0], args[1]);
                    case "edit": return editor();
                    default: throw new AssertionError(method.getName());
                }
            });
            return instance;
        }
        SharedPreferences.Editor editor() {
            final Map<String, Object> changes = new HashMap<>();
            final boolean[] clear = {false};
            return (SharedPreferences.Editor) Proxy.newProxyInstance(getClass().getClassLoader(),
                new Class[]{SharedPreferences.Editor.class}, (proxy, method, args) -> {
                String action = method.getName();
                if (action.equals("clear")) { clear[0] = true; return proxy; }
                if (action.startsWith("put")) { changes.put((String) args[0], args[1]); return proxy; }
                if (action.equals("remove")) { removes++; changes.put((String) args[0], null); return proxy; }
                if (action.equals("commit") || action.equals("apply")) {
                    // API 24 commitToMemory: clear BEFORE staged puts, and compare
                    // each put with the map after clear (not the final whole map).
                    boolean changed = clear[0] && !cache.isEmpty();
                    if (clear[0]) cache.clear();
                    for (Map.Entry<String, Object> entry : changes.entrySet()) {
                        String key = entry.getKey(); Object value = entry.getValue();
                        if (value == null) {
                            if (cache.containsKey(key)) { cache.remove(key); changed = true; }
                        } else if (!Objects.equals(cache.get(key), value)) {
                            cache.put(key, value); changed = true;
                        }
                    }
                    changes.clear(); clear[0] = false;
                    events.add(name + ":" + action);
                    if (action.equals("apply")) { applies++; return null; }
                    // API 24 writeToFile returns true BEFORE trying a write when
                    // an existing file and unchanged editor are present. A failed
                    // rename leaves that old file in place, even with a new cache.
                    if ((diskFileExists || !disk.isEmpty()) && !changed) { shortcuts++; return true; }
                    if (fail) return false;
                    diskWrites++; diskFileExists = true;
                    disk.clear(); disk.putAll(cache);
                    if (throwAfter) throw new IllegalStateException("synthetic commit then throw");
                    return true;
                }
                throw new AssertionError(action);
            });
        }
        void restart() { cache.clear(); cache.putAll(disk); instance = null; }
    }
    private void expectFailure(Throwing action) throws Exception {
        try { action.run(); fail("persistence acknowledged"); } catch (IOException expected) { }
    }
    interface Throwing { void run() throws Exception; }
    private void persist(Prefs keys, Prefs config, Prefs legacy, Prefs record) throws IOException {
        OnboardingDurability.metadataThenRecord(keys.preferences(), config.preferences(), legacy.preferences(), record.preferences(), "scope", "encrypted-new");
    }
    @Test public void metadataCommittedBeforeRecordWithoutApply() throws Exception {
        Prefs k=new Prefs("keys"), c=new Prefs("config"), l=new Prefs("legacy"), r=new Prefs("record");
        k.cache.put("wrapped", "encrypted-key"); c.cache.put("algorithm", "AES-GCM");
        persist(k,c,l,r);
        assertEquals(Arrays.asList("keys:commit","config:commit","legacy:commit","record:commit"), events);
        assertEquals(k.cache,k.disk); assertEquals(c.cache,c.disk); assertEquals(r.cache,r.disk);
        assertEquals(0,k.applies+c.applies+l.applies+r.applies);
    }
    @Test public void keyFailurePreventsRecordPersistence() throws Exception {
        Prefs k=new Prefs("keys"), c=new Prefs("config"), l=new Prefs("legacy"), r=new Prefs("record");k.fail=true;
        expectFailure(() -> persist(k,c,l,r)); assertEquals(Collections.singletonList("keys:commit"),events); assertTrue(r.cache.isEmpty());
    }
    @Test public void configurationFailurePreventsRecordPersistence() throws Exception {
        Prefs k=new Prefs("keys"), c=new Prefs("config"), l=new Prefs("legacy"), r=new Prefs("record");c.fail=true;
        expectFailure(() -> persist(k,c,l,r)); assertEquals(2,events.size()); assertTrue(r.cache.isEmpty());
    }
    @Test public void legacyConfigurationFailurePreventsRecordPersistence() throws Exception {
        Prefs k=new Prefs("keys"), c=new Prefs("config"), l=new Prefs("legacy"), r=new Prefs("record");l.fail=true;
        expectFailure(() -> persist(k,c,l,r)); assertEquals(3,events.size()); assertTrue(r.cache.isEmpty());
    }
    @Test public void failedRecordCommitCannotBeCertifiedByMatchingCache() throws Exception {
        Prefs k=new Prefs("keys"), c=new Prefs("config"), l=new Prefs("legacy"), r=new Prefs("record");
        r.cache.put("scope","old");r.disk.putAll(r.cache);r.fail=true;
        expectFailure(() -> persist(k,c,l,r));
        assertEquals("encrypted-new",r.cache.get("scope"));assertEquals("old",r.disk.get("scope"));
        expectFailure(() -> OnboardingDurability.flush(r.preferences()));
        assertEquals(0,r.removes);r.restart();assertEquals("old",r.cache.get("scope"));
    }
    @Test public void successfulBarrierAfterFailedCommitCertifiesSameSnapshot() throws Exception {
        Prefs r=new Prefs("record");r.cache.put("scope","frozen-key-and-body");r.fail=true;
        expectFailure(() -> OnboardingDurability.flush(r.preferences()));r.fail=false;
        OnboardingDurability.flush(r.preferences());r.restart();assertEquals("frozen-key-and-body",r.cache.get("scope"));
    }
    @Test public void commitThenThrowDoesNotAcknowledgeAndCanBeVerifiedLater() throws Exception {
        Prefs r=new Prefs("record");r.throwAfter=true;
        try { OnboardingDurability.put(r.preferences(),"scope","frozen");fail(); } catch (IllegalStateException expected) { }
        assertEquals("frozen",r.disk.get("scope"));r.throwAfter=false;
        OnboardingDurability.flush(r.preferences());r.restart();assertEquals("frozen",r.cache.get("scope"));
    }
    @Test public void unchangedSnapshotStillRequiresCheckedCommit() throws Exception {
        Prefs r=new Prefs("record");r.cache.put("scope","frozen");r.disk.putAll(r.cache);r.fail=true;
        expectFailure(() -> OnboardingDurability.flush(r.preferences()));assertEquals(Collections.singletonList("record:commit"),events);
    }
    @Test public void snapshotPreservesAllSupportedMetadataTypes() throws Exception {
        Prefs r=new Prefs("metadata");r.cache.put("s","x");r.cache.put("b",true);r.cache.put("i",1);r.cache.put("l",2L);r.cache.put("f",3f);r.cache.put("set",new HashSet<>(Arrays.asList("a","b")));
        OnboardingDurability.flush(r.preferences());assertEquals(r.cache,r.disk);
    }
    @Test public void failedExplicitDeleteIsReported() throws Exception {
        Prefs r=new Prefs("record");r.cache.put("scope","confirmed");r.disk.putAll(r.cache);r.fail=true;
        expectFailure(() -> OnboardingDurability.remove(r.preferences(),"scope"));r.restart();assertEquals("confirmed",r.cache.get("scope"));
    }
    @Test public void successfulRecordAndMetadataSurviveRestart() throws Exception {
        Prefs k=new Prefs("keys"), c=new Prefs("config"), l=new Prefs("legacy"), r=new Prefs("record");k.cache.put("wrapped","key");c.cache.put("algorithm","GCM");
        persist(k,c,l,r);k.restart();c.restart();r.restart();assertEquals("key",k.cache.get("wrapped"));assertEquals("GCM",c.cache.get("algorithm"));assertEquals("encrypted-new",r.cache.get("scope"));
    }

    @Test public void api24UnchangedCommitCanLieAfterFailedWrite() throws Exception {
        Prefs r = new Prefs("record");
        r.cache.put("scope", "unconfirmed"); r.disk.putAll(r.cache); r.fail = true;
        assertFalse(r.preferences().edit().putString("scope", "confirmed").commit());
        assertEquals("confirmed", r.cache.get("scope"));
        assertTrue(r.preferences().edit().putString("scope", "confirmed").commit());
        assertEquals(1, r.shortcuts);
        assertEquals("unconfirmed", r.disk.get("scope"));
        expectFailure(() -> OnboardingDurability.flush(r.preferences()));
        assertEquals(1, r.shortcuts); // replacement did not take the false-success path
        r.restart(); assertEquals("unconfirmed", r.cache.get("scope"));
    }
    @Test public void identicalPutUsesRealWriteInsteadOfApi24Shortcut() throws Exception {
        Prefs r = new Prefs("record"); r.cache.put("scope", "frozen"); r.disk.putAll(r.cache);
        OnboardingDurability.put(r.preferences(), "scope", "frozen");
        assertEquals(1, r.diskWrites); assertEquals(0, r.shortcuts);
        r.fail = true; expectFailure(() -> OnboardingDurability.put(r.preferences(), "scope", "frozen"));
    }
    @Test public void failedKeyInitializationCannotPassUnchangedBarrier() throws Exception {
        Prefs k=new Prefs("keys"), c=new Prefs("config"), l=new Prefs("legacy"), r=new Prefs("record");
        k.diskFileExists=true; k.fail=true;
        k.preferences().edit().putString("wrapped", "new-key").apply();
        assertTrue(k.preferences().edit().putString("wrapped", "new-key").commit());
        expectFailure(() -> persist(k,c,l,r));
        assertTrue(k.disk.isEmpty()); assertTrue(r.cache.isEmpty());
    }
    @Test public void failedConfigurationInitializationCannotPassUnchangedBarrier() throws Exception {
        Prefs k=new Prefs("keys"), c=new Prefs("config"), l=new Prefs("legacy"), r=new Prefs("record");
        k.cache.put("wrapped", "key"); c.diskFileExists=true; c.fail=true;
        c.preferences().edit().putString("algorithm", "GCM").apply();
        assertTrue(c.preferences().edit().putString("algorithm", "GCM").commit());
        expectFailure(() -> persist(k,c,l,r));
        assertEquals(k.cache,k.disk); assertTrue(c.disk.isEmpty()); assertTrue(r.cache.isEmpty());
    }
    @Test public void atomicReinsertionRetainsUnrelatedAuthEntriesWithoutIntermediateEmptyDisk() throws Exception {
        Prefs r=new Prefs("record"); r.cache.put("auth", "synthetic-refresh"); r.cache.put("scope", "original"); r.disk.putAll(r.cache);
        OnboardingDurability.put(r.preferences(), "scope", "confirmed");
        assertEquals(1, r.diskWrites); assertEquals("synthetic-refresh", r.disk.get("auth"));
        assertEquals("confirmed", r.disk.get("scope")); assertEquals(0, r.removes);
    }
    @Test public void failedLastItemDeleteCannotCertifyEmptyCache() throws Exception {
        Prefs r=new Prefs("record"); r.cache.put("scope", "confirmed"); r.disk.putAll(r.cache); r.fail=true;
        expectFailure(() -> OnboardingDurability.remove(r.preferences(), "scope"));
        assertTrue(r.cache.isEmpty()); assertEquals("confirmed", r.disk.get("scope"));
        // A bare empty editor would report true. The ambiguity fence refuses it.
        assertTrue(r.preferences().edit().commit());
        r.fail=false; expectFailure(() -> OnboardingDurability.flush(r.preferences()));
        expectFailure(() -> OnboardingDurability.put(r.preferences(), "scope", "new-operation"));
        r.restart(); assertEquals("confirmed",r.cache.get("scope"));
        OnboardingDurability.flush(r.preferences());
    }

    @Test public void deleteThenThrowKeepsEmptyCacheBlockedUntilRestart() throws Exception {
        Prefs r=new Prefs("record"); r.cache.put("scope", "confirmed"); r.disk.putAll(r.cache); r.throwAfter=true;
        try { OnboardingDurability.remove(r.preferences(), "scope"); fail(); }
        catch (IllegalStateException expected) { }
        assertTrue(r.disk.isEmpty()); r.throwAfter=false;
        expectFailure(() -> OnboardingDurability.flush(r.preferences()));
        // An ordinary auth write must not turn the fence into an absence claim.
        r.preferences().edit().putString("auth", "synthetic").apply();
        expectFailure(() -> OnboardingDurability.flush(r.preferences()));
        r.restart(); assertTrue(r.cache.isEmpty());
        OnboardingDurability.flush(r.preferences());
    }
}
