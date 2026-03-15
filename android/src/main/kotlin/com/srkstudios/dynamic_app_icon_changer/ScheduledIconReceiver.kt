package com.srkstudios.dynamic_app_icon_changer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Handles AlarmManager callbacks for scheduled icon changes.
 *
 * Two actions are supported:
 * - ACTION_SCHEDULE_START: activates the scheduled icon.
 * - ACTION_SCHEDULE_END: resets the icon to default and clears the schedule.
 *
 * Has zero Flutter dependencies and runs in the background.
 */
class ScheduledIconReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ScheduledIconReceiver"
        const val ACTION_SCHEDULE_START =
            "com.srkstudios.dynamic_app_icon_changer.ACTION_SCHEDULE_START"
        const val ACTION_SCHEDULE_END =
            "com.srkstudios.dynamic_app_icon_changer.ACTION_SCHEDULE_END"
        const val REQUEST_CODE_START = 9001
        const val REQUEST_CODE_END = 9002
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d(TAG, "onReceive: action=$action")

        when (action) {
            ACTION_SCHEDULE_START -> {
                val schedule = IconStateManager.getSchedule(context)
                if (schedule == null) {
                    Log.w(TAG, "onReceive: START alarm fired but no schedule found")
                    return
                }
                val (iconName, _, endMillis) = schedule
                val now = System.currentTimeMillis()

                if (now >= endMillis) {
                    // Schedule already expired before start alarm fired
                    Log.i(TAG, "onReceive: schedule already expired, resetting to default")
                    IconStateManager.clearSchedule(context)
                    IconStateManager.resetToDefault(context)
                    return
                }

                Log.i(TAG, "onReceive: activating scheduled icon '$iconName'")
                IconStateManager.applyIcon(context, iconName)
            }

            ACTION_SCHEDULE_END -> {
                Log.i(TAG, "onReceive: schedule ended, resetting to default")
                IconStateManager.clearSchedule(context)
                IconStateManager.resetToDefault(context)
            }

            else -> {
                Log.w(TAG, "onReceive: unknown action '$action'")
            }
        }
    }
}
