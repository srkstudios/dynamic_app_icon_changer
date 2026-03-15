package com.srkstudios.dynamic_app_icon_changer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Listens for BOOT_COMPLETED and MY_PACKAGE_REPLACED broadcasts and
 * reconciles activity-alias enabled states.
 *
 * On BOOT_COMPLETED: runs full recovery to restore the correct single alias,
 * checks/applies any active schedule, and re-registers schedule alarms
 * (since alarms are lost on reboot).
 *
 * On MY_PACKAGE_REPLACED: runs full recovery AND additionally enables the
 * manifest-default alias. This is critical because `flutter run` and `adb am
 * start` resolve the launch component from the manifest at build time —
 * they always target the default alias (the one with `android:enabled="true"`).
 * If that alias was disabled at runtime (because the user switched icons),
 * the launch fails with "Activity class does not exist". By re-enabling the
 * default alias after every install, the launch command succeeds. The Flutter
 * engine-attach recovery immediately narrows it back to the correct single
 * active alias when the app starts, so the brief window of two enabled aliases
 * is invisible to the user.
 *
 * Has zero Flutter dependencies and runs before the engine starts.
 */
class IconStateRecoveryReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "DynIconRecovery"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }

        try {
            Log.d(TAG, "Running icon-state recovery (trigger=$action)")

            // Full recovery: restore the correct active alias + protected components
            // (this also calls checkAndApplySchedule internally)
            IconStateManager.recover(context)

            if (action == Intent.ACTION_MY_PACKAGE_REPLACED) {
                // After app install/update, also enable the default alias so that
                // flutter run / adb am start can launch the app successfully.
                IconStateManager.enableDefaultAlias(context)
            }

            if (action == Intent.ACTION_BOOT_COMPLETED) {
                // Alarms are lost on reboot — re-register any active schedule alarms
                reRegisterScheduleAlarms(context)
            }

            Log.d(TAG, "Icon-state recovery completed successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Icon-state recovery failed", e)
        }
    }

    /**
     * After a device reboot, AlarmManager alarms are cleared.
     * If there's an active schedule, re-register the start/end alarms.
     */
    private fun reRegisterScheduleAlarms(context: Context) {
        val schedule = IconStateManager.getSchedule(context) ?: return
        val (_, startMillis, endMillis) = schedule
        val now = System.currentTimeMillis()

        if (now >= endMillis) {
            // Schedule already expired during device off-time
            Log.i(TAG, "reRegisterScheduleAlarms: schedule expired during reboot, resetting")
            IconStateManager.clearSchedule(context)
            IconStateManager.resetToDefault(context)
            return
        }

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // Re-register start alarm if it hasn't fired yet
        if (startMillis > 0 && now < startMillis) {
            Log.d(TAG, "reRegisterScheduleAlarms: re-registering START alarm for $startMillis")
            setAlarm(context, alarmManager,
                ScheduledIconReceiver.ACTION_SCHEDULE_START,
                ScheduledIconReceiver.REQUEST_CODE_START,
                startMillis)
        }

        // Always re-register end alarm
        Log.d(TAG, "reRegisterScheduleAlarms: re-registering END alarm for $endMillis")
        setAlarm(context, alarmManager,
            ScheduledIconReceiver.ACTION_SCHEDULE_END,
            ScheduledIconReceiver.REQUEST_CODE_END,
            endMillis)
    }

    private fun setAlarm(
        context: Context,
        alarmManager: AlarmManager,
        action: String,
        requestCode: Int,
        triggerAtMillis: Long
    ) {
        val intent = Intent(context, ScheduledIconReceiver::class.java).apply {
            this.action = action
        }
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val pendingIntent = PendingIntent.getBroadcast(context, requestCode, intent, flags)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }
    }
}
