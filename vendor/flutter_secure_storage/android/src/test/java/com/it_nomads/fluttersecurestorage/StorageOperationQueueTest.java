package com.it_nomads.fluttersecurestorage;

import java.io.IOException;
import java.util.ArrayDeque;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import static org.junit.Assert.*;

/** JVM simulations; preferences are the API-24 cache/disk fixture, not Android IO. */
public class StorageOperationQueueTest {
    static final class Worker implements Executor {
        final ArrayDeque<Runnable> tasks = new ArrayDeque<>();
        @Override public void execute(Runnable task) { tasks.addLast(task); }
        void runNext() { tasks.removeFirst().run(); }
        void drain() { while (!tasks.isEmpty()) runNext(); }
    }
    final Worker worker = new Worker();
    final StorageOperationQueue queue = new StorageOperationQueue(worker);
    final OnboardingDurabilityTest fixture = new OnboardingDurabilityTest();
    final OnboardingDurabilityTest.Prefs records = fixture.new Prefs("records");

    private void queued(Runnable work) {
        queue.submit(complete -> { try { work.run(); } finally { complete.run(); } });
    }
    private void barrier() {
        try { OnboardingDurability.flush(records.preferences()); }
        catch (IOException failure) { throw new AssertionError(failure); }
    }
    private void interleave(Runnable writer) {
        records.afterSnapshot = () -> {
            records.afterSnapshot = null;
            queued(writer); // A different instance submits during snapshot capture.
            assertTrue(worker.tasks.isEmpty()); // It cannot reach preferences yet.
        };
        queued(this::barrier);
        worker.drain();
    }

    @Test public void authCommitDuringSnapshotCannotBeRolledBack() {
        records.cache.put("auth", "old"); records.disk.putAll(records.cache);
        interleave(() -> assertTrue(records.preferences().edit().putString("auth", "rotated").commit()));
        assertEquals("rotated", records.cache.get("auth"));
        records.restart(); assertEquals("rotated", records.cache.get("auth"));
    }
    @Test public void authApplyRetainsSemanticsAndSurvivesNextBarrier() {
        records.cache.put("auth", "old");
        interleave(() -> records.preferences().edit().putString("auth", "rotated").apply());
        assertEquals(1, records.applies);
        queued(this::barrier); worker.drain();
        records.restart(); assertEquals("rotated", records.cache.get("auth"));
    }
    @Test public void anotherPendingOperationCannotBeErased() {
        records.cache.put("scope-a", "frozen-a");
        interleave(() -> {
            try { OnboardingDurability.put(records.preferences(), "scope-b", "frozen-b"); }
            catch (IOException failure) { throw new AssertionError(failure); }
        });
        records.restart();
        assertEquals("frozen-a", records.cache.get("scope-a"));
        assertEquals("frozen-b", records.cache.get("scope-b"));
    }
    @Test public void updateAndDeletionFromOtherInstancesAreNotUndone() {
        records.cache.put("auth", "old"); records.cache.put("obsolete", "value");
        interleave(() -> {
            assertTrue(records.preferences().edit().putString("auth", "new").commit());
            queued(() -> assertTrue(records.preferences().edit().remove("obsolete").commit()));
        });
        records.restart(); assertEquals("new", records.cache.get("auth"));
        assertFalse(records.cache.containsKey("obsolete"));
    }
    @Test public void editorStagedBeforeBarrierCommitsOnlyAfterBarrier() {
        records.cache.put("auth", "old");
        android.content.SharedPreferences.Editor staged = records.preferences().edit().putString("auth", "new");
        interleave(() -> assertTrue(staged.commit()));
        records.restart(); assertEquals("new", records.cache.get("auth"));
    }
    @Test public void asyncInitializationOwnsQueueUntilMetadataAndResultComplete() {
        OnboardingDurabilityTest.Prefs keys = fixture.new Prefs("keys");
        OnboardingDurabilityTest.Prefs config = fixture.new Prefs("config");
        OnboardingDurabilityTest.Prefs legacy = fixture.new Prefs("legacy");
        AtomicReference<Runnable> finish = new AtomicReference<>();
        queue.submit(finish::set); worker.runNext();
        queued(() -> {
            try { OnboardingDurability.metadataThenRecord(keys.preferences(), config.preferences(),
                    legacy.preferences(), records.preferences(), "scope", "frozen"); }
            catch (IOException failure) { throw new AssertionError(failure); }
        });
        assertTrue(worker.tasks.isEmpty()); assertTrue(records.cache.isEmpty());
        // Continuation on an arbitrary callback thread still owns the queue.
        keys.preferences().edit().putString("wrapped", "key").apply();
        config.preferences().edit().putString("algorithm", "GCM").apply();
        finish.get().run(); worker.drain();
        keys.restart(); config.restart(); records.restart();
        assertEquals("key", keys.cache.get("wrapped"));
        assertEquals("GCM", config.cache.get("algorithm"));
        assertEquals("frozen", records.cache.get("scope"));
    }
    @Test public void secondInitializationCannotRaceFirstWrappedKeyCreation() {
        OnboardingDurabilityTest.Prefs keys = fixture.new Prefs("keys");
        AtomicReference<Runnable> finish = new AtomicReference<>();
        queue.submit(finish::set); worker.runNext();
        queued(() -> {
            assertEquals("first-key", keys.preferences().getString("wrapped", null));
            assertEquals(1, keys.applies);
        });
        keys.preferences().edit().putString("wrapped", "first-key").apply();
        finish.get().run(); worker.drain();
    }
    @Test public void failureReleasesQueueWithoutAuthorizingBarrier() {
        records.cache.put("scope", "old"); records.disk.putAll(records.cache); records.fail = true;
        boolean[] accepted = {false};
        queued(() -> {
            try { OnboardingDurability.put(records.preferences(), "scope", "new"); accepted[0] = true; }
            catch (IOException expected) { }
        });
        queued(() -> assertEquals("old", records.disk.get("scope")));
        worker.drain(); assertFalse(accepted[0]);
    }
    @Test public void commitThenThrowReleasesQueueWithoutAcknowledgement() {
        records.throwAfter = true;
        boolean[] accepted = {false};
        queued(() -> {
            try { OnboardingDurability.put(records.preferences(), "scope", "frozen"); accepted[0] = true; }
            catch (IllegalStateException expected) { }
            catch (IOException unexpected) { throw new AssertionError(unexpected); }
        });
        queued(() -> assertEquals("frozen", records.disk.get("scope")));
        worker.drain(); assertFalse(accepted[0]);
    }
    @Test public void duplicateCompletionCannotReleaseAnotherAsyncOperation() {
        AtomicReference<Runnable> first = new AtomicReference<>(), second = new AtomicReference<>();
        queue.submit(first::set); queue.submit(second::set); worker.runNext();
        first.get().run(); worker.runNext(); first.get().run();
        boolean[] ran = {false}; queued(() -> ran[0] = true);
        assertTrue(worker.tasks.isEmpty()); assertFalse(ran[0]);
        second.get().run(); worker.drain(); assertTrue(ran[0]);
    }
    @Test public void throwingOperationDoesNotStrandFollowingCalls() {
        queue.submit(complete -> { throw new IllegalStateException("synthetic"); });
        boolean[] ran = {false}; queued(() -> ran[0] = true);
        try { worker.runNext(); fail(); } catch (IllegalStateException expected) { }
        worker.drain(); assertTrue(ran[0]);
    }
    @Test public void nestedSubmissionDoesNotExecuteReentrantly() {
        boolean[] innerRan = {false};
        queued(() -> { queued(() -> innerRan[0] = true); assertFalse(innerRan[0]); });
        worker.drain(); assertTrue(innerRan[0]);
    }
}
