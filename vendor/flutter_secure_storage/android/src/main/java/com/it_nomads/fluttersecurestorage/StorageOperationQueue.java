package com.it_nomads.fluttersecurestorage;

import java.util.ArrayDeque;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Serializes complete plugin operations, not just their initial synchronous work.
 * Ownership lasts through initialization, biometric/migration continuations and
 * the storage operation, until its terminal result. Never holds a monitor while
 * executing an operation or waiting for an asynchronous callback.
 */
final class StorageOperationQueue {
    interface Operation { void run(Runnable complete); }

    private final Executor executor;
    private final ArrayDeque<Operation> pending = new ArrayDeque<>();
    private boolean running;

    StorageOperationQueue(Executor executor) { this.executor = executor; }

    void submit(Operation operation) {
        synchronized (pending) { pending.addLast(operation); }
        scheduleNext();
    }

    private void scheduleNext() {
        final Operation operation;
        synchronized (pending) {
            if (running || pending.isEmpty()) return;
            running = true;
            operation = pending.removeFirst();
        }
        executor.execute(() -> {
            AtomicBoolean completed = new AtomicBoolean();
            Runnable complete = () -> {
                if (!completed.compareAndSet(false, true)) return;
                synchronized (pending) { running = false; }
                scheduleNext();
            };
            try {
                operation.run(complete);
            } catch (Throwable failure) {
                complete.run();
                throw failure;
            }
        });
    }
}
