import Cocoa
import FlutterMacOS
import os.log

private let log = OSLog(subsystem: "com.srkstudios.dynamic_app_icon_changer", category: "DynamicAppIconChanger")

public class DynamicAppIconChangerPlugin: NSObject, FlutterPlugin {

    private static let scheduleIconKey = "dic_schedule_icon_name"
    private static let scheduleStartKey = "dic_schedule_start_millis"
    private static let scheduleEndKey = "dic_schedule_end_millis"
    private static let activeIconKey = "dic_active_icon_name"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "dynamic_app_icon_changer/methods",
            binaryMessenger: registrar.messenger
        )
        let instance = DynamicAppIconChangerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Check schedule when this app becomes active (equivalent to iOS
        // foreground). NSApplication.didBecomeActiveNotification only fires
        // for this app, unlike NSWorkspace.didActivateApplicationNotification
        // which fires for every app activation system-wide.
        NotificationCenter.default.addObserver(
            instance,
            selector: #selector(checkScheduleOnActivation),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        // Check schedule and restore the persisted icon on launch. The Dock
        // icon does not survive process restarts, so re-apply whatever icon
        // is recorded as active.
        instance.checkScheduleOnActivation()
        instance.restorePersistedIcon()

        os_log(.debug, log: log, "Plugin registered")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        os_log(.debug, log: log, "handle: method=%{public}@", call.method)

        switch call.method {
        case "supportsAlternateIcons":
            result(true)

        case "getAlternateIconName":
            let iconName = UserDefaults.standard.string(forKey: DynamicAppIconChangerPlugin.activeIconKey)
            os_log(.debug, log: log, "getAlternateIconName: %{public}@", iconName ?? "default")
            result(iconName)

        case "setAlternateIconName":
            handleSetAlternateIconName(call, result: result)

        case "scheduleAlternateIcon":
            handleScheduleAlternateIcon(call, result: result)

        case "cancelScheduledIcon":
            handleCancelScheduledIcon(call, result: result)

        case "getActiveSchedule":
            handleGetActiveSchedule(result: result)

        case "registerProtectedComponents":
            os_log(.debug, log: log, "registerProtectedComponents: no-op on macOS")
            result(nil)

        case "setBadgeNumber":
            if let args = call.arguments as? [String: Any],
               let count = args["count"] as? Int {
                os_log(.debug, log: log, "setBadgeNumber: setting to %d", count)
                if count == 0 {
                    NSApp.dockTile.badgeLabel = nil
                } else {
                    NSApp.dockTile.badgeLabel = "\(count)"
                }
            }
            result(nil)

        case "getBadgeNumber":
            let label = NSApp.dockTile.badgeLabel
            let badge = label != nil ? (Int(label!) ?? 0) : 0
            os_log(.debug, log: log, "getBadgeNumber: %d", badge)
            result(badge)

        default:
            os_log(.fault, log: log, "handle: unrecognized method '%{public}@'", call.method)
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Icon switching

    private func handleSetAlternateIconName(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any?] else {
            result(FlutterError(code: "INVALID_ARGUMENTS",
                                message: "Expected a map with 'iconName'.",
                                details: nil))
            return
        }

        let iconName = args["iconName"] as? String
        os_log(.info, log: log, "setAlternateIconName: changing to %{public}@", iconName ?? "default")

        if let iconName = iconName {
            // Try to load the icon from the app bundle
            guard let image = NSImage(named: iconName) ?? loadIconFromBundle(named: iconName) else {
                os_log(.error, log: log, "setAlternateIconName: icon '%{public}@' not found in bundle", iconName)
                result(FlutterError(code: "ICON_NOT_FOUND",
                                    message: "Icon '\(iconName)' was not found in the app bundle. "
                                        + "Add the image to Assets.xcassets or as a loose file in the macOS Runner.",
                                    details: nil))
                return
            }
            NSApp.applicationIconImage = image
            UserDefaults.standard.set(iconName, forKey: DynamicAppIconChangerPlugin.activeIconKey)
        } else {
            // Reset to default
            NSApp.applicationIconImage = nil
            UserDefaults.standard.removeObject(forKey: DynamicAppIconChangerPlugin.activeIconKey)
        }

        os_log(.info, log: log, "setAlternateIconName: changed to %{public}@", iconName ?? "default")
        result(nil)
    }

    private func loadIconFromBundle(named name: String) -> NSImage? {
        // Try common extensions
        for ext in ["png", "icns", "jpg", "jpeg", "tiff"] {
            if let path = Bundle.main.path(forResource: name, ofType: ext) {
                return NSImage(contentsOfFile: path)
            }
        }
        // Try in flutter_assets
        if let resourcePath = Bundle.main.resourcePath {
            let flutterAssetsPath = "\(resourcePath)/Frameworks/App.framework/Resources/flutter_assets"
            for ext in ["png", "icns", "jpg"] {
                let fullPath = "\(flutterAssetsPath)/assets/icons/\(name).\(ext)"
                if FileManager.default.fileExists(atPath: fullPath) {
                    return NSImage(contentsOfFile: fullPath)
                }
            }
        }
        return nil
    }

    // MARK: - Schedule

    private func handleScheduleAlternateIcon(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any?],
              let iconName = args["iconName"] as? String,
              let endAtMillis = args["endAtMillis"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGUMENTS",
                                message: "Expected iconName and endAtMillis.",
                                details: nil))
            return
        }

        let startAtMillis = args["startAtMillis"] as? Int64 ?? 0
        os_log(.info, log: log, "scheduleAlternateIcon: icon=%{public}@, start=%lld, end=%lld",
               iconName, startAtMillis, endAtMillis)

        let defaults = UserDefaults.standard
        defaults.set(iconName, forKey: DynamicAppIconChangerPlugin.scheduleIconKey)
        defaults.set(startAtMillis, forKey: DynamicAppIconChangerPlugin.scheduleStartKey)
        defaults.set(endAtMillis, forKey: DynamicAppIconChangerPlugin.scheduleEndKey)

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        if startAtMillis == 0 || now >= startAtMillis {
            os_log(.debug, log: log, "scheduleAlternateIcon: applying immediately")
            if let image = NSImage(named: iconName) ?? loadIconFromBundle(named: iconName) {
                NSApp.applicationIconImage = image
                defaults.set(iconName, forKey: DynamicAppIconChangerPlugin.activeIconKey)
                result(nil)
            } else {
                result(FlutterError(code: "ICON_NOT_FOUND",
                                    message: "Icon '\(iconName)' not found in bundle.",
                                    details: nil))
            }
        } else {
            os_log(.debug, log: log, "scheduleAlternateIcon: start is in the future")
            result(nil)
        }
    }

    private func handleCancelScheduledIcon(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any?]
        let resetToDefault = (args?["resetToDefault"] as? Bool) ?? true

        os_log(.info, log: log, "cancelScheduledIcon: resetToDefault=%{public}@",
               resetToDefault ? "true" : "false")
        clearSchedule()

        if resetToDefault {
            NSApp.applicationIconImage = nil
            UserDefaults.standard.removeObject(forKey: DynamicAppIconChangerPlugin.activeIconKey)
        }

        result(nil)
    }

    private func handleGetActiveSchedule(result: @escaping FlutterResult) {
        let defaults = UserDefaults.standard
        guard let iconName = defaults.string(forKey: DynamicAppIconChangerPlugin.scheduleIconKey) else {
            result(nil)
            return
        }
        let startMillis = defaults.object(forKey: DynamicAppIconChangerPlugin.scheduleStartKey) as? Int64 ?? 0
        let endMillis = defaults.object(forKey: DynamicAppIconChangerPlugin.scheduleEndKey) as? Int64 ?? 0

        if endMillis == 0 {
            result(nil)
            return
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let isActive = (startMillis == 0 || now >= startMillis) && now < endMillis

        let map: [String: Any?] = [
            "iconName": iconName,
            "startAtMillis": startMillis == 0 ? nil : startMillis,
            "endAtMillis": endMillis,
            "isActive": isActive
        ]
        result(map)
    }

    @objc private func checkScheduleOnActivation() {
        let defaults = UserDefaults.standard
        guard let iconName = defaults.string(forKey: DynamicAppIconChangerPlugin.scheduleIconKey) else {
            return
        }
        let startMillis = defaults.object(forKey: DynamicAppIconChangerPlugin.scheduleStartKey) as? Int64 ?? 0
        let endMillis = defaults.object(forKey: DynamicAppIconChangerPlugin.scheduleEndKey) as? Int64 ?? 0
        if endMillis == 0 { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        if now >= endMillis {
            os_log(.info, log: log, "checkScheduleOnActivation: schedule expired, resetting")
            clearSchedule()
            NSApp.applicationIconImage = nil
            defaults.removeObject(forKey: DynamicAppIconChangerPlugin.activeIconKey)
            return
        }

        if startMillis == 0 || now >= startMillis {
            let currentIcon = defaults.string(forKey: DynamicAppIconChangerPlugin.activeIconKey)
            if currentIcon != iconName {
                os_log(.info, log: log, "checkScheduleOnActivation: activating '%{public}@'", iconName)
                if let image = NSImage(named: iconName) ?? loadIconFromBundle(named: iconName) {
                    NSApp.applicationIconImage = image
                    defaults.set(iconName, forKey: DynamicAppIconChangerPlugin.activeIconKey)
                }
            }
        }
    }

    private func restorePersistedIcon() {
        guard let iconName = UserDefaults.standard.string(
            forKey: DynamicAppIconChangerPlugin.activeIconKey) else {
            return
        }
        if let image = NSImage(named: iconName) ?? loadIconFromBundle(named: iconName) {
            os_log(.info, log: log, "restorePersistedIcon: re-applying '%{public}@'", iconName)
            NSApp.applicationIconImage = image
        } else {
            os_log(.error, log: log,
                   "restorePersistedIcon: icon '%{public}@' no longer found in bundle", iconName)
        }
    }

    private func clearSchedule() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DynamicAppIconChangerPlugin.scheduleIconKey)
        defaults.removeObject(forKey: DynamicAppIconChangerPlugin.scheduleStartKey)
        defaults.removeObject(forKey: DynamicAppIconChangerPlugin.scheduleEndKey)
    }
}
