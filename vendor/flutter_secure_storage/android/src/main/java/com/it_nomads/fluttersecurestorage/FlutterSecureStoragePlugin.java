package com.it_nomads.fluttersecurestorage;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class FlutterSecureStoragePlugin implements MethodCallHandler, FlutterPlugin {

    private static final String TAG = "FlutterSecureStoragePlugin";
    private MethodChannel channel;
    private volatile Context applicationContext;
    private final Map<String, FlutterSecureStorage> storagesBySharedPreferencesName = new HashMap<>();
    // Shared by EVERY plugin instance/engine, including workers draining after
    // detachment. Initialization and asynchronous continuations retain queue
    // ownership until a terminal MethodChannel result; no engine can shut it down.
    private static final StorageOperationQueue OPERATIONS = new StorageOperationQueue(
            Executors.newSingleThreadExecutor(task -> {
                Thread worker = new Thread(task, "com.it_nomads.fluttersecurestorage.worker");
                worker.setDaemon(true);
                return worker;
            }));

    public void initInstance(BinaryMessenger messenger, Context context) {
        try {
            applicationContext = context.getApplicationContext();

            channel = new MethodChannel(messenger, "plugins.it_nomads.com/flutter_secure_storage");
            channel.setMethodCallHandler(this);
        } catch (Exception e) {
            Log.e(TAG, "Registration failed", e);
        }
    }

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        initInstance(binding.getBinaryMessenger(), binding.getApplicationContext());
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        synchronized (storagesBySharedPreferencesName) {
            storagesBySharedPreferencesName.clear();
        }
        applicationContext = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result rawResult) {
        final Context operationContext = applicationContext;
        if (operationContext == null) {
            new MethodResultWrapper(rawResult, () -> {}).error(
                    "storage_unavailable", "Storage plugin is detached", null);
            return;
        }
        OPERATIONS.submit(complete -> new MethodRunner(call,
                new MethodResultWrapper(rawResult, complete), operationContext).run());
    }

    @SuppressWarnings("unchecked")
    private static String getKeyFromCall(FlutterSecureStorage storage, MethodCall call) {
        Map<String, Object> arguments = (Map<String, Object>) call.arguments;
        String key = (String) arguments.get("key");
        return storage.addPrefixToKey(key);
    }

    @SuppressWarnings("unchecked")
    private static String getValueFromCall(MethodCall call) {
        Map<String, Object> arguments = (Map<String, Object>) call.arguments;
        return (String) arguments.get("value");
    }

    private FlutterSecureStorage getOrCreateStorage(FlutterSecureStorageConfig config, Context operationContext) {
        // Use "ns:" prefix for storageNamespace to avoid collisions with legacy
        // sharedPreferencesName keys in the map. The key prefix is included so two
        // configs sharing a namespace/name but using different key prefixes don't
        // reuse (and go stale on) the same FlutterSecureStorage instance.
        final String namespace = config.hasStorageNamespace()
                ? "ns:" + config.getStorageNamespace()
                : config.getSharedPreferencesName();
        final String name = namespace + "|" + config.getSharedPreferencesKeyPrefix();
        synchronized (storagesBySharedPreferencesName) {
            FlutterSecureStorage existing = storagesBySharedPreferencesName.get(name);
            if (existing != null) {
                return existing;
            }
            FlutterSecureStorage created = new FlutterSecureStorage(operationContext);
            storagesBySharedPreferencesName.put(name, created);
            return created;
        }
    }

    /**
     * MethodChannel.Result wrapper that responds on the platform thread.
     */
    static class MethodResultWrapper implements Result {

        private final Result methodResult;
        private final Runnable complete;
        private final AtomicBoolean terminal = new AtomicBoolean();
        private final Handler handler = new Handler(Looper.getMainLooper());

        MethodResultWrapper(Result methodResult, Runnable complete) {
            this.methodResult = methodResult;
            this.complete = complete;
        }

        @Override
        public void success(final Object result) {
            deliver(() -> methodResult.success(result));
        }

        @Override
        public void error(@NonNull final String errorCode, final String errorMessage, final Object errorDetails) {
            deliver(() -> methodResult.error(errorCode, errorMessage, errorDetails));
        }

        @Override
        public void notImplemented() {
            deliver(methodResult::notImplemented);
        }

        private void deliver(Runnable callback) {
            if (!terminal.compareAndSet(false, true)) return;
            try {
                handler.post(callback);
            } catch (RuntimeException failure) {
                // Never throw back into a storage callback after releasing queue
                // ownership: upstream error recovery could then mutate preferences.
                Log.e(TAG, "Storage result could not be posted");
            } finally {
                complete.run();
            }
        }
    }

    /**
     * Wraps the functionality of onMethodCall() in a Runnable for execution in the worker thread.
     */
    class MethodRunner implements Runnable {
        private final MethodCall call;
        private final Result result;
        private final Context operationContext;

        MethodRunner(MethodCall call, Result result, Context operationContext) {
            this.call = call;
            this.result = result;
            this.operationContext = operationContext;
        }

        @SuppressWarnings("unchecked")
        @Override
        public void run() {
            // Guard MethodChannel payload before initialize(); funnel unexpected exceptions to result.error.
            try {
                if (call == null || call.arguments == null) {
                    handleException(new IllegalArgumentException("Method call arguments are null"));
                    return;
                }
                if (!(call.arguments instanceof Map)) {
                    handleException(new IllegalArgumentException("Method call arguments must be a Map"));
                    return;
                }
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                Object rawOptions = args.get("options");
                Map<String, Object> options;
                if (rawOptions instanceof Map) {
                    options = (Map<String, Object>) rawOptions;
                } else {
                    options = new HashMap<>();
                }
                FlutterSecureStorageConfig config = new FlutterSecureStorageConfig(options);

                if ("checkUpgradeStatus".equals(call.method)) {
                    // Runs before initialize(), which is what would migrate or wipe.
                    result.success(UpgradeInspector.inspect(operationContext, config));
                    return;
                }

                final boolean onboarding = call.method.equals("writeOnboarding")
                        || call.method.equals("readOnboarding") || call.method.equals("deleteOnboarding");
                if (onboarding) {
                    // Fail closed instead of migrating namespaces/algorithms or
                    // enabling destructive recovery through caller options.
                    Object key = args.get("key");
                    if (!(key instanceof String) || (!((String) key).startsWith("gym.onboarding.v1.")
                            && !((String) key).startsWith("gym.payment.v1."))
                            || config.shouldDeleteOnFailure() || config.getStorageNamespace() != null
                            || !config.getPrefOptionKeyCipherAlgorithm().equals("RSA_ECB_OAEPwithSHA_256andMGF1Padding")
                            || !config.getPrefOptionStorageCipherAlgorithm().equals("AES_GCM_NoPadding")) {
                        result.error("onboarding_options", "Unsupported onboarding storage options", null);
                        return;
                    }
                }

                FlutterSecureStorage secureStorage = getOrCreateStorage(config, operationContext);

                secureStorage.initialize(config, new SecurePreferencesCallback<>() {
                @Override
                public void onSuccess(Void unused) {
                    try {
                        if (onboarding) {
                            String key = getKeyFromCall(secureStorage, call);
                            String value = getValueFromCall(call);
                            if (call.method.equals("writeOnboarding") && value == null) {
                                result.error("onboarding_value", "Onboarding writes require a value", null);
                                return;
                            }
                            secureStorage.onboarding(call.method, key, value, new SecurePreferencesCallback<>() {
                                @Override
                                public void onSuccess(String stored) { result.success(stored); }
                                @Override
                                public void onError(Exception e) {
                                    // Do not expose record keys, values or native exception details.
                                    result.error("onboarding_persistence", "Onboarding persistence could not be verified", null);
                                }
                            });
                            return;
                        }
                        switch (call.method) {
                            case "write": {
                                String key = getKeyFromCall(secureStorage, call);
                                String value = getValueFromCall(call);

                                if (value != null) {
                                    secureStorage.write(key, value, new SecurePreferencesCallback<>() {
                                        @Override
                                        public void onSuccess(Void unused) {
                                            result.success(null);
                                        }

                                        @Override
                                        public void onError(Exception e) {
                                            handleException(e);
                                        }
                                    });
                                } else {
                                    result.error("null", null, null);
                                }
                                break;
                            }
                            case "read": {
                                String key = getKeyFromCall(secureStorage, call);

                                if (secureStorage.containsKey(key)) {
                                    secureStorage.read(key, new SecurePreferencesCallback<>() {
                                        @Override
                                        public void onSuccess(String value) {
                                            result.success(value);
                                        }

                                        @Override
                                        public void onError(Exception e) {
                                            handleException(e);
                                        }
                                    });
                                } else {
                                    result.success(null);
                                }
                                break;
                            }
                            case "readAll": {
                                secureStorage.readAll(new SecurePreferencesCallback<>() {
                                    @Override
                                    public void onSuccess(Map<String, String> value) {
                                        result.success(value);
                                    }

                                    @Override
                                    public void onError(Exception e) {
                                        handleException(e);
                                    }
                                });
                                break;
                            }
                            case "containsKey": {
                                String key = getKeyFromCall(secureStorage, call);

                                boolean containsKey = secureStorage.containsKey(key);
                                result.success(containsKey);
                                break;
                            }
                            case "delete": {
                                String key = getKeyFromCall(secureStorage, call);

                                secureStorage.delete(key);
                                result.success(null);
                                break;
                            }
                            case "deleteAll": {
                                secureStorage.deleteAll();
                                result.success(null);
                                break;
                            }
                            case "isBiometricAvailable": {
                                boolean available = secureStorage.isBiometricAvailable();
                                result.success(available);
                                break;
                            }
                            case "isDeviceSecure": {
                                boolean secure = secureStorage.isDeviceSecure();
                                result.success(secure);
                                break;
                            }
                            default:
                                result.notImplemented();
                                break;
                        }
                    } catch (Throwable e) {
                        if (e instanceof VirtualMachineError) {
                            throw (VirtualMachineError) e;
                        }
                        if (config.shouldDeleteOnFailure()) {
                            try {
                                secureStorage.deleteAll();
                                result.success("Data has been reset");
                            } catch (Throwable ex) {
                                handleException(ex);
                            }
                        } else {
                            handleException(e);
                        }
                    }
                }

                @Override
                public void onError(Exception e) {
                    handleException(e);
                }
            });
            } catch (Throwable e) {
                // Catch Throwable, not just Exception: some OEM builds throw
                // java.lang.Error subclasses (e.g. NoSuchFieldError) from Android
                // Keystore framework code, and an uncaught Error on this
                // HandlerThread would crash the entire app process. Genuine VM
                // errors (OOM, StackOverflow) are rethrown instead of being
                // funneled through handleException/deleteAll, which would
                // allocate memory the JVM may no longer have.
                if (e instanceof VirtualMachineError) {
                    throw (VirtualMachineError) e;
                }
                handleException(e);
            }
        }


        private void handleException(Throwable e) {
            StringWriter stringWriter = new StringWriter();
            e.printStackTrace(new PrintWriter(stringWriter));
            // Send exception message as the message field so Flutter can parse it
            String errorMessage = e.getMessage() != null ? e.getMessage() : "Unknown error";
            result.error("Exception encountered", errorMessage, stringWriter.toString());
        }
    }
}
