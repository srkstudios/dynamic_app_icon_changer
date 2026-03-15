package com.srkstudios.dynamic_icon_changer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Listens for BOOT_COMPLETED and MY_PACKAGE_REPLACED broadcasts and
 * reconciles activity-alias enabled states.
 *
 * On BOOT_COMPLETED: runs full recovery to restore the correct single alias.
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
            IconStateManager.recover(context)

            if (action == Intent.ACTION_MY_PACKAGE_REPLACED) {
                // After app install/update, also enable the default alias so that
                // flutter run / adb am start can launch the app successfully.
                // The engine-attach recovery will narrow it back to the single
                // correct alias when the Flutter engine starts.
                IconStateManager.enableDefaultAlias(context)
            }

            Log.d(TAG, "Icon-state recovery completed successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Icon-state recovery failed", e)
        }
    }
}
