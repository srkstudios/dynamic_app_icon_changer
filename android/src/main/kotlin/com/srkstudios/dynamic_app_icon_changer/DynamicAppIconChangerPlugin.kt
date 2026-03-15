package com.srkstudios.dynamic_app_icon_changer

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** DynamicAppIconChangerPlugin */
class DynamicAppIconChangerPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        private const val TAG = "DynamicAppIconChanger"
    }

    private lateinit var channel: MethodChannel
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding

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
                result.success(true)
            }
            "getAlternateIconName" -> {
                result.success(getActiveAlternateIcon())
            }
            "setAlternateIconName" -> {
                handleSetAlternateIconName(call, result)
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

    private fun getActiveAlternateIcon(): String? {
        val context = binding.applicationContext
        val pm = context.packageManager
        val pkg = context.packageName

        val aliases = getLauncherAliases(pm, pkg)

        for (activityInfo in aliases) {
            val componentName = ComponentName(pkg, activityInfo.name)
            val state = pm.getComponentEnabledSetting(componentName)

            val effectivelyEnabled = when (state) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> activityInfo.enabled
                else -> false
            }

            if (effectivelyEnabled) {
                val activeIcon = if (activityInfo.enabled) {
                    null
                } else {
                    activityInfo.name.removePrefix("$pkg.")
                }
                Log.d(TAG, "getActiveAlternateIcon: result=${activeIcon ?: "default"}")
                return activeIcon
            }
        }

        Log.d(TAG, "getActiveAlternateIcon: no enabled alias found, returning null")
        return null
    }

    private fun handleSetAlternateIconName(call: MethodCall, result: Result) {
        try {
            val iconName = call.argument<String?>("iconName")
            val blacklistedBrands = call.argument<List<String>?>("blacklistedBrands")
            Log.d(TAG, "setAlternateIconName: target=${iconName ?: "default"}, blacklist=${blacklistedBrands?.size ?: 0} brands")

            if (!blacklistedBrands.isNullOrEmpty()) {
                val manufacturer = Build.MANUFACTURER.lowercase()
                val model = Build.MODEL.lowercase()
                for (brand in blacklistedBrands) {
                    val b = brand.lowercase()
                    if (manufacturer.contains(b) || model.contains(b)) {
                        Log.i(TAG, "setAlternateIconName: skipped — device brand '$b' is blacklisted (manufacturer=$manufacturer, model=$model)")
                        result.success(null)
                        return
                    }
                }
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
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "setAlternateIconName: failed", e)
            result.error("ICON_CHANGE_FAILED", e.message, null)
        }
    }

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
        // This is needed so the recovery receiver can re-enable it on
        // MY_PACKAGE_REPLACED, allowing flutter run / adb to launch the app.
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

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine: detaching plugin")
        channel.setMethodCallHandler(null)
    }
}
