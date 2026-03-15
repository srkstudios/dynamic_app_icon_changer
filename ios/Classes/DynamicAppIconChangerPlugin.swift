import Flutter
import UIKit
import os.log

private let log = OSLog(subsystem: "com.srkstudios.dynamic_app_icon_changer", category: "DynamicAppIconChanger")

public class DynamicAppIconChangerPlugin: NSObject, FlutterPlugin {

    private static let scheduleIconKey = "dic_schedule_icon_name"
    private static let scheduleStartKey = "dic_schedule_start_millis"
    private static let scheduleEndKey = "dic_schedule_end_millis"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "dynamic_app_icon_changer/methods",
            binaryMessenger: registrar.messenger()
        )
        let instance = DynamicAppIconChangerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Check schedule on foreground entry
        NotificationCenter.default.addObserver(
            instance,
            selector: #selector(checkScheduleOnForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        // Also check on registration (app launch)
        instance.checkScheduleOnForeground()

        os_log(.debug, log: log, "Plugin registered")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        os_log(.debug, log: log, "handle: method=%{public}@", call.method)

        switch call.method {
        case "supportsAlternateIcons":
            let supported = UIApplication.shared.supportsAlternateIcons
            os_log(.debug, log: log, "supportsAlternateIcons: %{public}@", supported ? "true" : "false")
            result(supported)

        case "getAlternateIconName":
            let iconName = UIApplication.shared.alternateIconName
            os_log(.debug, log: log, "getAlternateIconName: %{public}@", iconName ?? "default")
            result(iconName)

        case "setAlternateIconName":
            guard let args = call.arguments as? [String: Any?] else {
                os_log(.error, log: log, "setAlternateIconName: invalid arguments — expected a map with 'iconName'")
                result(FlutterError(code: "INVALID_ARGUMENTS",
                                    message: "Expected a map with 'iconName'.",
                                    details: nil))
                return
            }
            let iconName = args["iconName"] as? String
            // relaunch is Android-only, ignored on iOS
            os_log(.info, log: log, "setAlternateIconName: changing to %{public}@", iconName ?? "default")
            UIApplication.shared.setAlternateIconName(iconName) { error in
                if let error = error {
                    os_log(.error, log: log, "setAlternateIconName: failed — %{public}@", error.localizedDescription)
                    result(FlutterError(code: "ICON_CHANGE_FAILED",
                                        message: error.localizedDescription,
                                        details: nil))
                } else {
                    os_log(.info, log: log, "setAlternateIconName: changed to %{public}@", iconName ?? "default")
                    result(nil)
                }
            }

        case "scheduleAlternateIcon":
            handleScheduleAlternateIcon(call, result: result)

        case "cancelScheduledIcon":
            handleCancelScheduledIcon(call, result: result)

        case "getActiveSchedule":
            handleGetActiveSchedule(result: result)

        case "registerProtectedComponents":
            // No-op on iOS — this is an Android-only feature.
            os_log(.debug, log: log, "registerProtectedComponents: no-op on iOS")
            result(nil)

        case "setBadgeNumber":
            if let args = call.arguments as? [String: Any],
               let count = args["count"] as? Int {
                os_log(.debug, log: log, "setBadgeNumber: setting to %d", count)
                UIApplication.shared.applicationIconBadgeNumber = count
            }
            result(nil)

        case "getBadgeNumber":
            let badge = UIApplication.shared.applicationIconBadgeNumber
            os_log(.debug, log: log, "getBadgeNumber: %d", badge)
            result(badge)

        default:
            os_log(.fault, log: log, "handle: unrecognized method '%{public}@'", call.method)
            result(FlutterMethodNotImplemented)
        }
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

        // Save schedule to UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(iconName, forKey: DynamicAppIconChangerPlugin.scheduleIconKey)
        defaults.set(startAtMillis, forKey: DynamicAppIconChangerPlugin.scheduleStartKey)
        defaults.set(endAtMillis, forKey: DynamicAppIconChangerPlugin.scheduleEndKey)

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        if startAtMillis == 0 || now >= startAtMillis {
            // Apply immediately
            os_log(.debug, log: log, "scheduleAlternateIcon: applying immediately")
            UIApplication.shared.setAlternateIconName(iconName) { error in
                if let error = error {
                    os_log(.error, log: log, "scheduleAlternateIcon: failed to set icon — %{public}@", error.localizedDescription)
                    result(FlutterError(code: "SCHEDULE_FAILED",
                                        message: error.localizedDescription,
                                        details: nil))
                } else {
                    os_log(.info, log: log, "scheduleAlternateIcon: icon set to %{public}@", iconName)
                    result(nil)
                }
            }
        } else {
            // Start is in the future — will apply on next foreground check
            os_log(.debug, log: log, "scheduleAlternateIcon: start is in the future, will apply on foreground")
            result(nil)
        }
    }

    private func handleCancelScheduledIcon(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any?]
        let resetToDefault = (args?["resetToDefault"] as? Bool) ?? true

        os_log(.info, log: log, "cancelScheduledIcon: resetToDefault=%{public}@", resetToDefault ? "true" : "false")
        clearSchedule()

        if resetToDefault {
            UIApplication.shared.setAlternateIconName(nil) { error in
                if let error = error {
                    os_log(.error, log: log, "cancelScheduledIcon: failed to reset — %{public}@", error.localizedDescription)
                    result(FlutterError(code: "CANCEL_SCHEDULE_FAILED",
                                        message: error.localizedDescription,
                                        details: nil))
                } else {
                    os_log(.info, log: log, "cancelScheduledIcon: reset to default")
                    result(nil)
                }
            }
        } else {
            result(nil)
        }
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

    @objc private func checkScheduleOnForeground() {
        let defaults = UserDefaults.standard
        guard let iconName = defaults.string(forKey: DynamicAppIconChangerPlugin.scheduleIconKey) else {
            return
        }
        let startMillis = defaults.object(forKey: DynamicAppIconChangerPlugin.scheduleStartKey) as? Int64 ?? 0
        let endMillis = defaults.object(forKey: DynamicAppIconChangerPlugin.scheduleEndKey) as? Int64 ?? 0

        if endMillis == 0 { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        if now >= endMillis {
            // Schedule expired — reset to default
            os_log(.info, log: log, "checkScheduleOnForeground: schedule expired, resetting to default")
            clearSchedule()
            UIApplication.shared.setAlternateIconName(nil) { error in
                if let error = error {
                    os_log(.error, log: log, "checkScheduleOnForeground: reset failed — %{public}@", error.localizedDescription)
                }
            }
            return
        }

        if startMillis == 0 || now >= startMillis {
            // Within window — ensure the icon is set
            let currentIcon = UIApplication.shared.alternateIconName
            if currentIcon != iconName {
                os_log(.info, log: log, "checkScheduleOnForeground: activating scheduled icon '%{public}@'", iconName)
                UIApplication.shared.setAlternateIconName(iconName) { error in
                    if let error = error {
                        os_log(.error, log: log, "checkScheduleOnForeground: set failed — %{public}@", error.localizedDescription)
                    }
                }
            }
        }
    }

    private func clearSchedule() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DynamicAppIconChangerPlugin.scheduleIconKey)
        defaults.removeObject(forKey: DynamicAppIconChangerPlugin.scheduleStartKey)
        defaults.removeObject(forKey: DynamicAppIconChangerPlugin.scheduleEndKey)
        os_log(.debug, log: log, "clearSchedule: schedule cleared")
    }
}
