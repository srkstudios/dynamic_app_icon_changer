package com.srkstudios.dynamic_app_icon_changer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** DynamicAppIconChangerPlugin */
class DynamicAppIconChangerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    companion object {
        private const val TAG = "DynamicAppIconChanger"
    }

    private lateinit var channel: MethodChannel
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding
    private var activity: android.app.Activity? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine: attaching plugin")
        binding = flutterPluginBinding
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "dynamic_app_icon_changer/methods")
        channel.setMethodCallHandler(this)

        try {
            val context = flutterPluginBinding.applicationContext
            Log.d(TAG, "onAttachedToEngine: persisting alias metadata if needed")
            persistAliasMetadataIfNeeded(context)
            Log.d(TAG, "onAttachedToEngine: starting icon state recovery")
            IconStateManager.recover(context)
            Log.d(TAG, "onAttachedToEngine: recovery complete")
        } catch (e: Exception) {
            Log.e(TAG, "Recovery on attach failed", e)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.d(TAG, "onMethodCall: method=${call.method}")
        when (call.method) {
            "supportsAlternateIcons" -> {
                // Alias-based icon switching works on all supported Android
                // versions; a missing manifest setup is reported as
                // NO_ALIASES_FOUND when an icon change is attempted.
                result.success(true)
            }
            "getAlternateIconName" -> {
                // The persisted state is the source of truth: PackageManager
                // queries return aliases in unspecified order and can report
                // two enabled aliases during the post-update recovery window.
                result.success(IconStateManager.getActiveIcon(binding.applicationContext))
            }
            "setAlternateIconName" -> {
                handleSetAlternateIconName(call, result)
            }
            "scheduleAlternateIcon" -> {
                handleScheduleAlternateIcon(call, result)
            }
            "cancelScheduledIcon" -> {
                handleCancelScheduledIcon(call, result)
            }
            "getActiveSchedule" -> {
                handleGetActiveSchedule(result)
            }
            "registerProtectedComponents" -> {
                handleRegisterProtectedComponents(call, result)
            }
            "setBadgeNumber" -> {
                result.success(null)
            }
            "getBadgeNumber" -> {
                result.success(0)
            }
            else -> {
                Log.w(TAG, "onMethodCall: unrecognized method '${call.method}'")
                result.notImplemented()
            }
        }
    }

    /** Returns true when the device manufacturer or model matches any entry. */
    private fun isDeviceBlacklisted(blacklistedBrands: List<String>?): Boolean {
        if (blacklistedBrands.isNullOrEmpty()) return false
        val manufacturer = Build.MANUFACTURER.lowercase()
        val model = Build.MODEL.lowercase()
        return blacklistedBrands.any { brand ->
            val b = brand.lowercase()
            manufacturer.contains(b) || model.contains(b)
        }
    }

    private fun handleSetAlternateIconName(call: MethodCall, result: Result) {
        try {
            val iconName = call.argument<String?>("iconName")
            val blacklistedBrands = call.argument<List<String>?>("blacklistedBrands")
            val relaunch = call.argument<Boolean>("relaunch") ?: false
            Log.d(TAG, "setAlternateIconName: target=${iconName ?: "default"}, relaunch=$relaunch, blacklist=${blacklistedBrands?.size ?: 0} brands")

            if (isDeviceBlacklisted(blacklistedBrands)) {
                Log.i(TAG, "setAlternateIconName: skipped — device brand is blacklisted")
                result.success(null)
                return
            }

            val context = binding.applicationContext
            val pm = context.packageManager
            val pkg = context.packageName

            val aliases = getLauncherAliases(pm, pkg)

            if (aliases.isEmpty()) {
                Log.e(TAG, "setAlternateIconName: no activity-alias entries found in manifest")
                result.error(
                    "NO_ALIASES_FOUND",
                    "No activity-alias entries with MAIN+LAUNCHER were found. " +
                    "Make sure you have added <activity-alias> entries to your AndroidManifest.xml " +
                    "and that MainActivity does NOT have the LAUNCHER intent-filter.",
                    null
                )
                return
            }

            var enabledComponent: ComponentName? = null

            if (iconName == null) {
                Log.d(TAG, "setAlternateIconName: resetting all ${aliases.size} aliases to DEFAULT")
                for (activityInfo in aliases) {
                    IconStateManager.normalizeComponentState(
                        pm,
                        ComponentName(pkg, activityInfo.name),
                        PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
                    )
                }
            } else {
                val targetFullName = "$pkg.$iconName"
                val targetInfo = aliases.firstOrNull { it.name == targetFullName }
                if (targetInfo == null) {
                    Log.e(TAG, "setAlternateIconName: alias '$iconName' not found among ${aliases.size} aliases")
                    result.error(
                        "ICON_NOT_FOUND",
                        "No activity-alias named '$iconName' was found. " +
                        "Ensure the alias is declared in AndroidManifest.xml as " +
                        "<activity-alias android:name=\".$iconName\" ...>.",
                        null
                    )
                    return
                }

                Log.d(TAG, "setAlternateIconName: enabling '$iconName', disabling ${aliases.size - 1} others")
                for (activityInfo in aliases) {
                    val componentName = ComponentName(pkg, activityInfo.name)
                    if (activityInfo.name == targetFullName) {
                        IconStateManager.normalizeComponentState(
                            pm, componentName,
                            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                        )
                        enabledComponent = componentName
                    } else {
                        IconStateManager.normalizeComponentState(
                            pm, componentName,
                            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                        )
                    }
                }
            }

            ensureMainActivityEnabled(pm, pkg, aliases)
            persistAliasMetadata(context, pkg, aliases)
            IconStateManager.saveActiveIcon(context, iconName)

            // Restore protected components after icon change
            IconStateManager.restoreProtectedComponents(context)

            Log.i(TAG, "setAlternateIconName: icon changed to ${iconName ?: "default"}")

            // Relaunch the app if requested
            if (relaunch) {
                relaunchApp(context, enabledComponent)
            }

            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "setAlternateIconName: failed", e)
            result.error("ICON_CHANGE_FAILED", e.message, null)
        }
    }

    // ── Schedule methods ─────────────────────────────────────────────

    private fun handleScheduleAlternateIcon(call: MethodCall, result: Result) {
        try {
            val iconName = call.argument<String>("iconName")
            val startAtMillis = call.argument<Number?>("startAtMillis")?.toLong()
            val endAtMillis = call.argument<Number?>("endAtMillis")?.toLong()
            val blacklistedBrands = call.argument<List<String>?>("blacklistedBrands")

            if (iconName == null || endAtMillis == null) {
                result.error("INVALID_ARGUMENTS", "iconName and endAtMillis are required", null)
                return
            }

            Log.d(TAG, "scheduleAlternateIcon: icon=$iconName, start=$startAtMillis, end=$endAtMillis")

            if (isDeviceBlacklisted(blacklistedBrands)) {
                Log.i(TAG, "scheduleAlternateIcon: skipped — device brand is blacklisted")
                result.success(null)
                return
            }

            val context = binding.applicationContext
            val pm = context.packageManager
            val pkg = context.packageName

            // Validate the icon exists
            val aliases = getLauncherAliases(pm, pkg)
            val targetFullName = "$pkg.$iconName"
            if (aliases.none { it.name == targetFullName }) {
                result.error(
                    "ICON_NOT_FOUND",
                    "No activity-alias named '$iconName' was found.",
                    null
                )
                return
            }

            val now = System.currentTimeMillis()
            val effectiveStart = startAtMillis ?: 0L

            // Cancel any existing schedule alarms
            cancelScheduleAlarms(context)

            // Persist the schedule
            IconStateManager.saveSchedule(context, iconName, effectiveStart, endAtMillis)

            // If start is now or in the past, apply immediately
            if (effectiveStart == 0L || now >= effectiveStart) {
                Log.d(TAG, "scheduleAlternateIcon: start is now/past, applying immediately")
                IconStateManager.applyIcon(context, iconName)
                persistAliasMetadata(context, pkg, aliases)
            } else {
                // Schedule the start alarm
                Log.d(TAG, "scheduleAlternateIcon: scheduling start alarm for $effectiveStart")
                scheduleAlarm(
                    context,
                    ScheduledIconReceiver.ACTION_SCHEDULE_START,
                    ScheduledIconReceiver.REQUEST_CODE_START,
                    effectiveStart
                )
            }

            // Always schedule the end alarm
            Log.d(TAG, "scheduleAlternateIcon: scheduling end alarm for $endAtMillis")
            scheduleAlarm(
                context,
                ScheduledIconReceiver.ACTION_SCHEDULE_END,
                ScheduledIconReceiver.REQUEST_CODE_END,
                endAtMillis
            )

            Log.i(TAG, "scheduleAlternateIcon: scheduled icon=$iconName, start=$effectiveStart, end=$endAtMillis")
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "scheduleAlternateIcon: failed", e)
            result.error("SCHEDULE_FAILED", e.message, null)
        }
    }

    private fun handleCancelScheduledIcon(call: MethodCall, result: Result) {
        try {
            val resetToDefault = call.argument<Boolean>("resetToDefault") ?: true
            Log.d(TAG, "cancelScheduledIcon: resetToDefault=$resetToDefault")

            val context = binding.applicationContext
            cancelScheduleAlarms(context)
            IconStateManager.clearSchedule(context)

            if (resetToDefault) {
                IconStateManager.resetToDefault(context)
            }

            Log.i(TAG, "cancelScheduledIcon: done")
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "cancelScheduledIcon: failed", e)
            result.error("CANCEL_SCHEDULE_FAILED", e.message, null)
        }
    }

    private fun handleGetActiveSchedule(result: Result) {
        try {
            val context = binding.applicationContext
            // Self-heal first: if the end alarm was missed (e.g. the app was
            // force-stopped, which cancels alarms), this resets the icon and
            // clears the expired schedule instead of reporting stale state.
            IconStateManager.checkAndApplySchedule(context)
            val schedule = IconStateManager.getSchedule(context)

            if (schedule == null) {
                result.success(null)
                return
            }

            val (iconName, startMillis, endMillis) = schedule
            val now = System.currentTimeMillis()
            val isActive = (startMillis == 0L || now >= startMillis) && now < endMillis

            val map = hashMapOf<String, Any?>(
                "iconName" to iconName,
                "startAtMillis" to if (startMillis == 0L) null else startMillis,
                "endAtMillis" to endMillis,
                "isActive" to isActive
            )
            result.success(map)
        } catch (e: Exception) {
            Log.e(TAG, "getActiveSchedule: failed", e)
            result.error("GET_SCHEDULE_FAILED", e.message, null)
        }
    }

    // ── Alarm helpers ────────────────────────────────────────────────

    private fun scheduleAlarm(context: Context, action: String, requestCode: Int, triggerAtMillis: Long) {
        val intent = Intent(context, ScheduledIconReceiver::class.java).apply {
            this.action = action
        }
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val pendingIntent = PendingIntent.getBroadcast(context, requestCode, intent, flags)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            // Fall back to inexact alarm if exact alarm permission not granted
            Log.w(TAG, "scheduleAlarm: exact alarms not permitted, using inexact for $action")
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }
        Log.d(TAG, "scheduleAlarm: set alarm for $action at $triggerAtMillis")
    }

    private fun cancelScheduleAlarms(context: Context) {
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val startIntent = Intent(context, ScheduledIconReceiver::class.java).apply {
            action = ScheduledIconReceiver.ACTION_SCHEDULE_START
        }
        PendingIntent.getBroadcast(context, ScheduledIconReceiver.REQUEST_CODE_START, startIntent, flags)?.let {
            alarmManager.cancel(it)
            Log.d(TAG, "cancelScheduleAlarms: cancelled START alarm")
        }

        val endIntent = Intent(context, ScheduledIconReceiver::class.java).apply {
            action = ScheduledIconReceiver.ACTION_SCHEDULE_END
        }
        PendingIntent.getBroadcast(context, ScheduledIconReceiver.REQUEST_CODE_END, endIntent, flags)?.let {
            alarmManager.cancel(it)
            Log.d(TAG, "cancelScheduleAlarms: cancelled END alarm")
        }
    }

    // ── Relaunch ─────────────────────────────────────────────────────

    private fun relaunchApp(context: Context, enabledComponent: ComponentName?) {
        val currentActivity = activity
        if (currentActivity == null) {
            Log.w(TAG, "relaunchApp: no activity reference, cannot relaunch")
            return
        }

        val pm = context.packageManager
        val pkg = context.packageName
        val intent = pm.getLaunchIntentForPackage(pkg)
        if (intent == null) {
            Log.w(TAG, "relaunchApp: no launch intent found for $pkg")
            return
        }

        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        if (enabledComponent != null) {
            intent.component = enabledComponent
        }

        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val launchTime = System.currentTimeMillis() + 500

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            alarmManager.set(AlarmManager.RTC, launchTime, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC, launchTime, pendingIntent)
        }

        Log.i(TAG, "relaunchApp: scheduled relaunch in 500ms, finishing current activity")
        currentActivity.finish()
    }

    // ── Protected components ─────────────────────────────────────────

    private fun handleRegisterProtectedComponents(call: MethodCall, result: Result) {
        try {
            val context = binding.applicationContext
            val componentsList = call.argument<List<Map<String, Any>>>("components")

            if (componentsList == null) {
                Log.e(TAG, "registerProtectedComponents: 'components' argument is null")
                result.error(
                    "INVALID_ARGUMENTS",
                    "Expected a list of component maps under key 'components'.",
                    null
                )
                return
            }

            Log.d(TAG, "registerProtectedComponents: registering ${componentsList.size} components")
            IconStateManager.saveProtectedComponents(context, componentsList)

            // Immediately restore them so they are in the correct state now
            IconStateManager.restoreProtectedComponents(context)

            Log.i(TAG, "registerProtectedComponents: ${componentsList.size} components registered and restored")
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "registerProtectedComponents: failed", e)
            result.error("REGISTER_COMPONENTS_FAILED", e.message, null)
        }
    }

    // ── Alias helpers ────────────────────────────────────────────────

    private fun getLauncherAliases(
        pm: PackageManager,
        pkg: String
    ): List<android.content.pm.ActivityInfo> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
            setPackage(pkg)
        }

        @Suppress("DEPRECATION")
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            PackageManager.MATCH_DISABLED_COMPONENTS
        } else {
            PackageManager.GET_DISABLED_COMPONENTS
        }

        val aliases = pm.queryIntentActivities(launcherIntent, flags)
            .map { it.activityInfo }
            .filter { it.targetActivity != null }

        Log.d(TAG, "getLauncherAliases: found ${aliases.size} aliases for $pkg")
        return aliases
    }

    private fun ensureMainActivityEnabled(
        pm: PackageManager,
        pkg: String,
        aliases: List<android.content.pm.ActivityInfo>
    ) {
        val mainActivityClass = aliases.firstOrNull()?.targetActivity ?: return
        Log.d(TAG, "ensureMainActivityEnabled: ensuring $mainActivityClass is enabled")
        val component = ComponentName(pkg, mainActivityClass)
        IconStateManager.normalizeComponentState(
            pm, component,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        )
    }

    private fun persistAliasMetadata(
        context: android.content.Context,
        pkg: String,
        aliases: List<android.content.pm.ActivityInfo>
    ) {
        val shortNames = aliases.map { it.name.removePrefix("$pkg.") }
        IconStateManager.saveAliasNames(context, shortNames)

        val mainActivityClass = aliases.firstOrNull()?.targetActivity
        if (mainActivityClass != null) {
            IconStateManager.saveMainActivity(context, mainActivityClass)
        }

        // Persist the default alias (the one with enabled="true" in manifest).
        val defaultAlias = aliases.firstOrNull { it.enabled }
        if (defaultAlias != null) {
            val shortName = defaultAlias.name.removePrefix("$pkg.")
            IconStateManager.saveDefaultAlias(context, shortName)
            Log.d(TAG, "persistAliasMetadata: default alias is '$shortName'")
        }
    }

    private fun persistAliasMetadataIfNeeded(context: android.content.Context) {
        if (IconStateManager.getAliasNames(context).isNotEmpty()) {
            Log.d(TAG, "persistAliasMetadataIfNeeded: alias metadata already persisted, skipping")
            return
        }

        val pm = context.packageManager
        val pkg = context.packageName
        val aliases = getLauncherAliases(pm, pkg)
        if (aliases.isNotEmpty()) {
            Log.i(TAG, "persistAliasMetadataIfNeeded: first-run — persisting ${aliases.size} aliases")
            persistAliasMetadata(context, pkg, aliases)
        } else {
            Log.w(TAG, "persistAliasMetadataIfNeeded: first-run but no aliases found")
        }
    }

    // ── Lifecycle ────────────────────────────────────────────────────

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine: detaching plugin")
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        Log.d(TAG, "onAttachedToActivity: activity=${binding.activity.localClassName}")
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
