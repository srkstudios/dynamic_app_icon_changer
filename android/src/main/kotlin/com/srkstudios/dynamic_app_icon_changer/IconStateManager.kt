package com.srkstudios.dynamic_app_icon_changer

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

internal object IconStateManager {

    private const val TAG = "IconStateManager"
    private const val PREFS_NAME = "com.srkstudios.dynamic_app_icon_changer"
    private const val KEY_ACTIVE_ICON = "active_icon_name"
    private const val KEY_ALIAS_NAMES = "alias_short_names"
    private const val KEY_MAIN_ACTIVITY = "main_activity_class"
    private const val KEY_PROTECTED_COMPONENTS = "protected_components"
    private const val KEY_DEFAULT_ALIAS = "default_alias_short_name"

    // Schedule keys
    private const val KEY_SCHEDULE_ICON = "schedule_icon_name"
    private const val KEY_SCHEDULE_START = "schedule_start_millis"
    private const val KEY_SCHEDULE_END = "schedule_end_millis"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun stateName(state: Int): String = when (state) {
        PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> "DEFAULT"
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> "ENABLED"
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> "DISABLED"
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER -> "DISABLED_USER"
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED -> "DISABLED_UNTIL_USED"
        else -> "UNKNOWN($state)"
    }

    fun saveActiveIcon(context: Context, iconName: String?) {
        prefs(context).edit().apply {
            if (iconName == null) remove(KEY_ACTIVE_ICON) else putString(KEY_ACTIVE_ICON, iconName)
            apply()
        }
    }

    fun getActiveIcon(context: Context): String? =
        prefs(context).getString(KEY_ACTIVE_ICON, null)

    fun saveAliasNames(context: Context, names: List<String>) {
        prefs(context).edit()
            .putStringSet(KEY_ALIAS_NAMES, names.toSet())
            .apply()
    }

    fun getAliasNames(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_ALIAS_NAMES, emptySet()) ?: emptySet()

    fun saveMainActivity(context: Context, className: String) {
        prefs(context).edit()
            .putString(KEY_MAIN_ACTIVITY, className)
            .apply()
    }

    fun getMainActivity(context: Context): String? =
        prefs(context).getString(KEY_MAIN_ACTIVITY, null)

    /** Persist the short name of the manifest-default alias (the one with enabled="true"). */
    fun saveDefaultAlias(context: Context, shortName: String) {
        prefs(context).edit()
            .putString(KEY_DEFAULT_ALIAS, shortName)
            .apply()
    }

    /** Read the persisted default alias short name. */
    fun getDefaultAlias(context: Context): String? =
        prefs(context).getString(KEY_DEFAULT_ALIAS, null)

    /**
     * Ensures the manifest-default alias is enabled.
     *
     * This is called on MY_PACKAGE_REPLACED so that `flutter run` / `adb am start`
     * can always launch the app via the default alias resolved from the manifest.
     * The Flutter engine-attach recovery immediately narrows it back to the correct single
     * active alias when the app starts.
     */
    fun enableDefaultAlias(context: Context) {
        val defaultAlias = getDefaultAlias(context) ?: return
        val pkg = context.packageName
        val pm = context.packageManager
        val component = ComponentName(pkg, "$pkg.$defaultAlias")
        Log.d(TAG, "enableDefaultAlias: enabling $defaultAlias for flutter run / adb compatibility")
        normalizeComponentState(pm, component, PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
    }

    // ── Schedule ──────────────────────────────────────────────────────

    /**
     * Persists a scheduled icon change.
     *
     * @param iconName   The icon alias short name to activate.
     * @param startMillis Start time in epoch millis (0 = immediate).
     * @param endMillis   End time in epoch millis — icon resets to default after this.
     */
    fun saveSchedule(context: Context, iconName: String, startMillis: Long, endMillis: Long) {
        prefs(context).edit()
            .putString(KEY_SCHEDULE_ICON, iconName)
            .putLong(KEY_SCHEDULE_START, startMillis)
            .putLong(KEY_SCHEDULE_END, endMillis)
            .apply()
        Log.i(TAG, "saveSchedule: icon=$iconName, start=$startMillis, end=$endMillis")
    }

    /** Clears any persisted schedule. */
    fun clearSchedule(context: Context) {
        prefs(context).edit()
            .remove(KEY_SCHEDULE_ICON)
            .remove(KEY_SCHEDULE_START)
            .remove(KEY_SCHEDULE_END)
            .apply()
        Log.i(TAG, "clearSchedule: schedule cleared")
    }

    /** Returns (iconName, startMillis, endMillis) or null if no schedule exists. */
    fun getSchedule(context: Context): Triple<String, Long, Long>? {
        val p = prefs(context)
        val iconName = p.getString(KEY_SCHEDULE_ICON, null) ?: return null
        val startMillis = p.getLong(KEY_SCHEDULE_START, 0L)
        val endMillis = p.getLong(KEY_SCHEDULE_END, 0L)
        if (endMillis == 0L) return null
        return Triple(iconName, startMillis, endMillis)
    }

    /**
     * Checks if a schedule has expired and resets the icon to default if so.
     * Also, if a schedule's start time has arrived but the icon hasn't been
     * set yet, this method sets it.
     *
     * @return true if a schedule action was taken (set or reset).
     */
    fun checkAndApplySchedule(context: Context): Boolean {
        val schedule = getSchedule(context) ?: return false
        val (iconName, startMillis, endMillis) = schedule
        val now = System.currentTimeMillis()

        if (now >= endMillis) {
            // Schedule expired — reset to default
            Log.i(TAG, "checkAndApplySchedule: schedule expired, resetting to default")
            clearSchedule(context)
            // Reset icon to default (all aliases to DEFAULT state)
            resetToDefault(context)
            return true
        }

        if (startMillis == 0L || now >= startMillis) {
            // Within the active window — ensure the scheduled icon is set
            val currentIcon = getActiveIcon(context)
            if (currentIcon != iconName) {
                Log.i(TAG, "checkAndApplySchedule: activating scheduled icon '$iconName'")
                applyIcon(context, iconName)
                return true
            }
        }

        return false
    }

    /**
     * Applies a specific icon by enabling its alias and disabling all others.
     * This is used by the schedule system and recovery — it does NOT go through
     * the full plugin path (no blacklist check, no relaunch).
     */
    fun applyIcon(context: Context, iconName: String) {
        val pkg = context.packageName
        val pm = context.packageManager
        val aliasNames = getAliasNames(context)

        if (aliasNames.isEmpty()) {
            Log.w(TAG, "applyIcon: no aliases stored, cannot apply")
            return
        }

        val targetFullName = "$pkg.$iconName"
        for (shortName in aliasNames) {
            val fullName = "$pkg.$shortName"
            val component = ComponentName(pkg, fullName)
            if (fullName == targetFullName) {
                normalizeComponentState(pm, component, PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
            } else {
                normalizeComponentState(pm, component, PackageManager.COMPONENT_ENABLED_STATE_DISABLED)
            }
        }

        ensureMainActivityEnabled(context)
        saveActiveIcon(context, iconName)
        restoreProtectedComponents(context)
        Log.i(TAG, "applyIcon: applied icon '$iconName'")
    }

    /** Resets all aliases to DEFAULT state (manifest defaults). */
    fun resetToDefault(context: Context) {
        val pkg = context.packageName
        val pm = context.packageManager
        val aliasNames = getAliasNames(context)

        for (shortName in aliasNames) {
            val fullName = "$pkg.$shortName"
            val component = ComponentName(pkg, fullName)
            normalizeComponentState(pm, component, PackageManager.COMPONENT_ENABLED_STATE_DEFAULT)
        }

        ensureMainActivityEnabled(context)
        saveActiveIcon(context, null)
        restoreProtectedComponents(context)
        Log.i(TAG, "resetToDefault: all ${aliasNames.size} aliases reset to DEFAULT")
    }

    // ── Protected Components ──────────────────────────────────────────

    /**
     * Persists the list of protected components as a JSON string.
     *
     * Each entry in [components] is a map with keys `className` (String) and
     * `desiredState` (String: "enabled", "disabled", or "defaultState").
     */
    fun saveProtectedComponents(context: Context, components: List<Map<String, Any>>) {
        val jsonArray = JSONArray()
        for (component in components) {
            val obj = JSONObject()
            obj.put("className", component["className"] as String)
            obj.put("desiredState", component["desiredState"] as String)
            jsonArray.put(obj)
        }
        prefs(context).edit()
            .putString(KEY_PROTECTED_COMPONENTS, jsonArray.toString())
            .apply()
        Log.i(TAG, "saveProtectedComponents: saved ${components.size} protected components")
    }

    /**
     * Returns the persisted list of protected components, or an empty list
     * if none have been registered.
     */
    fun getProtectedComponents(context: Context): List<Pair<String, String>> {
        val json = prefs(context).getString(KEY_PROTECTED_COMPONENTS, null)
            ?: return emptyList()

        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                Pair(obj.getString("className"), obj.getString("desiredState"))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse protected components JSON", e)
            emptyList()
        }
    }

    /**
     * Restores every registered protected component to its desired enabled
     * state. Safe to call even if no components are registered (no-op).
     */
    fun restoreProtectedComponents(context: Context) {
        val components = getProtectedComponents(context)
        if (components.isEmpty()) return

        Log.d(TAG, "restoreProtectedComponents: restoring ${components.size} components")
        val pm = context.packageManager
        val pkg = context.packageName

        for ((className, desiredState) in components) {
            try {
                val component = ComponentName(pkg, className)
                val pmState = when (desiredState) {
                    "enabled" -> PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    "disabled" -> PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                    "defaultState" -> PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
                    else -> {
                        Log.w(TAG, "Unknown desiredState '$desiredState' for $className, skipping")
                        continue
                    }
                }
                normalizeComponentState(pm, component, pmState)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to restore protected component $className", e)
            }
        }
        Log.i(TAG, "restoreProtectedComponents: completed for ${components.size} components")
    }

    // ── Component State Helpers ───────────────────────────────────────

    fun normalizeComponentState(
        pm: PackageManager,
        componentName: ComponentName,
        desiredState: Int
    ) {
        val current = pm.getComponentEnabledSetting(componentName)
        if (current != desiredState) {
            Log.i(TAG, "normalizeComponentState: ${componentName.shortClassName} " +
                    "${stateName(current)} -> ${stateName(desiredState)}")
            pm.setComponentEnabledSetting(
                componentName,
                desiredState,
                PackageManager.DONT_KILL_APP
            )
        }
    }

    fun ensureMainActivityEnabled(context: Context) {
        val mainClass = getMainActivity(context) ?: return
        Log.d(TAG, "ensureMainActivityEnabled: ensuring $mainClass is enabled")
        val pm = context.packageManager
        val component = ComponentName(context.packageName, mainClass)
        normalizeComponentState(pm, component, PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
    }

    fun recover(context: Context) {
        val pkg = context.packageName
        val pm = context.packageManager
        val activeIcon = getActiveIcon(context)
        val aliasNames = getAliasNames(context)

        Log.d(TAG, "recover: activeIcon=${activeIcon ?: "default"}, aliasCount=${aliasNames.size}")

        if (aliasNames.isEmpty()) {
            Log.d(TAG, "recover: no aliases stored, nothing to recover")
            return
        }

        for (shortName in aliasNames) {
            val fullName = "$pkg.$shortName"
            val component = ComponentName(pkg, fullName)

            if (activeIcon == null) {
                normalizeComponentState(
                    pm, component,
                    PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
                )
            } else {
                if (shortName == activeIcon) {
                    normalizeComponentState(
                        pm, component,
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    )
                } else {
                    normalizeComponentState(
                        pm, component,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                    )
                }
            }
        }

        ensureMainActivityEnabled(context)

        // Also restore protected components during recovery
        restoreProtectedComponents(context)

        // Check if a schedule needs action (expired or needs activation)
        checkAndApplySchedule(context)

        Log.i(TAG, "recover: recovery completed for ${aliasNames.size} aliases")
    }
}
