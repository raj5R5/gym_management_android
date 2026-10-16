package com.it_nomads.fluttersecurestorage;

import android.content.SharedPreferences;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;

/**
 * Onboarding only. Production callers must retain process-wide
 * StorageOperationQueue ownership for snapshot capture through commit. All
 * plugin calls (including auth and initialization) use that same queue.
 */
final class OnboardingDurability {
    private OnboardingDurability() {}

    // An unsuccessful delete can leave an empty cache and an old disk record.
    // Empty editors cannot force a rewrite on API 24. Refuse that cache until
    // process reconstruction loads disk again; never fabricate a marker key.
    private static final Map<SharedPreferences, Boolean> uncertainEmpty = new WeakHashMap<>();

    static void checkedCommit(SharedPreferences.Editor editor) throws IOException {
        if (!editor.commit()) {
            throw new IOException("Onboarding persistence could not be verified");
        }
    }

    static void put(SharedPreferences preferences, String key, String value) throws IOException {
        Map<String, Object> snapshot = new HashMap<>(preferences.getAll());
        snapshot.put(key, value);
        replace(preferences, snapshot);
    }

    static void remove(SharedPreferences preferences, String key) throws IOException {
        Map<String, Object> snapshot = new HashMap<>(preferences.getAll());
        snapshot.remove(key);
        replace(preferences, snapshot);
    }

    /**
     * One atomic clear + exact reinsertion + checked commit, never clear().commit()
     * followed by another commit. A nonempty snapshot forces changesMade on API
     * 24 and a new memory generation on newer Android, even for identical values.
     * The platform writes the ENTIRE map, not a separate durability marker.
     */
    static void flush(SharedPreferences preferences) throws IOException {
        replace(preferences, new HashMap<>(preferences.getAll()));
    }

    @SuppressWarnings("unchecked")
    private static void replace(SharedPreferences preferences, Map<String, Object> snapshot)
            throws IOException {
        if (uncertainEmpty.containsKey(preferences)) {
            throw new IOException("Empty onboarding persistence requires process reconstruction");
        }
        SharedPreferences.Editor editor = preferences.edit().clear();
        for (Map.Entry<String, Object> entry : snapshot.entrySet()) {
            String key = entry.getKey();
            Object value = entry.getValue();
            if (value instanceof String) editor.putString(key, (String) value);
            else if (value instanceof Boolean) editor.putBoolean(key, (Boolean) value);
            else if (value instanceof Integer) editor.putInt(key, (Integer) value);
            else if (value instanceof Long) editor.putLong(key, (Long) value);
            else if (value instanceof Float) editor.putFloat(key, (Float) value);
            else if (value instanceof Set) editor.putStringSet(key, (Set<String>) value);
            else throw new IOException("Unsupported onboarding persistence metadata");
        }
        try {
            checkedCommit(editor);
            uncertainEmpty.remove(preferences);
        } catch (IOException | RuntimeException | Error failure) {
            if (snapshot.isEmpty()) uncertainEmpty.put(preferences, true);
            throw failure;
        }
        // An empty snapshot with no preceding failed emptying operation holds no
        // record or encryption dependency to certify. All send/confirmation paths
        // require nonempty wrapped-key/configuration/record snapshots.
    }

    static void metadataThenRecord(
            SharedPreferences keys, SharedPreferences configuration,
            SharedPreferences legacyConfiguration, SharedPreferences records,
            String key, String encryptedValue) throws IOException {
        flush(keys);
        flush(configuration);
        flush(legacyConfiguration);
        put(records, key, encryptedValue);
    }
}
