import Flutter
import UIKit
import os.log

private let log = OSLog(subsystem: "com.srkstudios.dynamic_icon_changer", category: "DynamicIconChanger")

public class DynamicIconChangerPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "dynamic_icon_changer/methods",
            binaryMessenger: registrar.messenger()
        )
        let instance = DynamicIconChangerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
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
}
