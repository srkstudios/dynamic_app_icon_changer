import 'dynamic_app_icon_changer_platform_interface.dart';

/// Exception thrown when a dynamic-icon operation fails.
class DynamicIconException implements Exception {
  DynamicIconException(this.message, {this.code});

  /// Machine-readable error code (e.g. `ICON_NOT_FOUND`).
  final String? code;

  /// Human-readable description of the error.
  final String message;

  @override
  String toString() {
    if (code != null) {
      return 'DynamicIconException($code): $message';
    }
    return 'DynamicIconException: $message';
  }
}

/// The desired enabled state for a protected Android component.
enum ComponentState {
  /// The component should be explicitly enabled.
  enabled,

  /// The component should be explicitly disabled.
  disabled,

  /// The component should respect its manifest default value.
  defaultState,
}

/// Describes an Android component (activity, service, receiver) that should
/// be protected during icon switches.
///
/// When the plugin toggles activity-alias states to change the launcher icon,
/// it can inadvertently affect the enabled state of other components declared
/// in the manifest. Registering a component as "protected" tells the plugin
/// to restore it to [desiredState] after every icon change and during
/// boot/update recovery.
class ProtectedComponent {
  /// The fully-qualified class name of the component.
  ///
  /// Example: `'com.moengage.pushbase.activities.PushTracker'`
  final String className;

  /// The state the component should be restored to after icon changes.
  final ComponentState desiredState;

  const ProtectedComponent({
    required this.className,
    required this.desiredState,
  });

  /// Serialises this component to a map for platform channel transport.
  Map<String, dynamic> toMap() => {
        'className': className,
        'desiredState': desiredState.name,
      };
}

/// Information about an active scheduled icon change.
class ScheduleInfo {
  /// The icon name that is (or will be) active during the scheduled window.
  final String iconName;

  /// When the scheduled icon becomes active. `null` if it started immediately.
  final DateTime? startAt;

  /// When the icon automatically resets to default.
  final DateTime endAt;

  /// Whether the scheduled icon is currently active (within the time window).
  final bool isActive;

  const ScheduleInfo({
    required this.iconName,
    this.startAt,
    required this.endAt,
    required this.isActive,
  });

  factory ScheduleInfo.fromMap(Map<String, dynamic> map) {
    return ScheduleInfo(
      iconName: map['iconName'] as String,
      startAt: map['startAtMillis'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['startAtMillis'] as int)
          : null,
      endAt: DateTime.fromMillisecondsSinceEpoch(map['endAtMillis'] as int),
      isActive: map['isActive'] as bool,
    );
  }

  @override
  String toString() =>
      'ScheduleInfo(icon=$iconName, start=$startAt, end=$endAt, active=$isActive)';
}

/// Public API for changing app icons at runtime.
///
/// All methods are static and delegate to the registered platform
/// implementation ([DynamicAppIconChangerPlatform]).
class DynamicAppIconChanger {
  DynamicAppIconChanger._();

  /// Whether the current platform supports alternate icons.
  ///
  /// Returns `true` on iOS 10.3+ and all supported Android versions.
  static Future<bool> get supportsAlternateIcons {
    return DynamicAppIconChangerPlatform.instance.supportsAlternateIcons();
  }

  /// The name of the currently active alternate icon, or `null` when the
  /// default icon is in use.
  static Future<String?> get alternateIconName {
    return DynamicAppIconChangerPlatform.instance.getAlternateIconName();
  }

  /// Switches the launcher icon to [iconName], or reverts to the default
  /// icon when [iconName] is `null`.
  ///
  /// On **Android**, [iconName] must match an `<activity-alias>` entry
  /// declared in `AndroidManifest.xml` (without the leading dot).
  ///
  /// On **iOS**, [iconName] must match a key under
  /// `CFBundleAlternateIcons` in `Info.plist`.
  ///
  /// [blacklistedBrands] (Android-only) is an optional list of
  /// manufacturer or model substrings on which the icon change should
  /// be silently skipped (case-insensitive). Example: `['samsung']`.
  ///
  /// [relaunch] (Android-only) when `true`, the app will be killed and
  /// relaunched after ~500ms so the launcher immediately reflects the new
  /// icon. Defaults to `false`.
  ///
  /// Throws a [DynamicIconException] if the change fails.
  static Future<void> setAlternateIconName(
    String? iconName, {
    List<String>? blacklistedBrands,
    bool relaunch = false,
  }) async {
    try {
      await DynamicAppIconChangerPlatform.instance.setAlternateIconName(
        iconName,
        blacklistedBrands: blacklistedBrands,
        relaunch: relaunch,
      );
    } on Exception catch (e) {
      throw DynamicIconException(e.toString());
    }
  }

  /// Schedule an icon change that automatically resets to default.
  ///
  /// The icon will be set to [iconName] at [startAt] (or immediately if
  /// [startAt] is `null` or in the past) and will automatically revert to
  /// the default icon at [endAt].
  ///
  /// **Android**: Uses `AlarmManager` for reliable background scheduling.
  /// The schedule survives reboots and app updates.
  ///
  /// **iOS**: The icon is set immediately (if within window) and the reset
  /// is checked every time the app enters the foreground. If the app is not
  /// opened after [endAt], the reset happens on the next launch.
  ///
  /// Only one schedule can be active at a time. Calling this again replaces
  /// any existing schedule.
  ///
  /// [blacklistedBrands] (Android-only) same as [setAlternateIconName].
  ///
  /// Throws a [DynamicIconException] if the operation fails.
  ///
  /// Example — Christmas icon from Dec 20 to Dec 26:
  /// ```dart
  /// await DynamicAppIconChanger.scheduleAlternateIcon(
  ///   'IconChristmas',
  ///   startAt: DateTime(2026, 12, 20),
  ///   endAt: DateTime(2026, 12, 26, 23, 59, 59),
  /// );
  /// ```
  static Future<void> scheduleAlternateIcon(
    String iconName, {
    DateTime? startAt,
    required DateTime endAt,
    List<String>? blacklistedBrands,
  }) async {
    if (endAt.isBefore(DateTime.now())) {
      throw DynamicIconException(
        'endAt must be in the future',
        code: 'INVALID_SCHEDULE',
      );
    }
    if (startAt != null && endAt.isBefore(startAt)) {
      throw DynamicIconException(
        'endAt must be after startAt',
        code: 'INVALID_SCHEDULE',
      );
    }
    try {
      await DynamicAppIconChangerPlatform.instance.scheduleAlternateIcon(
        iconName,
        startAt: startAt,
        endAt: endAt,
        blacklistedBrands: blacklistedBrands,
      );
    } on Exception catch (e) {
      throw DynamicIconException(e.toString());
    }
  }

  /// Cancel any active scheduled icon change.
  ///
  /// If [resetToDefault] is `true` (the default), the icon is immediately
  /// reverted to the default. If `false`, the current icon stays but the
  /// scheduled reset is cancelled.
  static Future<void> cancelScheduledIcon({
    bool resetToDefault = true,
  }) async {
    try {
      await DynamicAppIconChangerPlatform.instance.cancelScheduledIcon(
        resetToDefault: resetToDefault,
      );
    } on Exception catch (e) {
      throw DynamicIconException(e.toString());
    }
  }

  /// Returns information about the current scheduled icon, or `null` if
  /// no schedule is active.
  static Future<ScheduleInfo?> get activeSchedule {
    return DynamicAppIconChangerPlatform.instance.getActiveSchedule();
  }

  /// Sets the app's badge number (iOS only).
  ///
  /// Pass `0` to clear the badge. On Android this is a no-op.
  static Future<void> setBadgeNumber(int count) {
    return DynamicAppIconChangerPlatform.instance.setBadgeNumber(count);
  }

  /// Returns the current badge number (iOS only).
  ///
  /// Always returns `0` on Android.
  static Future<int> get badgeNumber {
    return DynamicAppIconChangerPlatform.instance.getBadgeNumber();
  }

  /// Register Android components that should be protected during icon switches.
  ///
  /// After every icon change and on boot/update recovery, these components will
  /// be restored to their specified state.
  ///
  /// This is useful for third-party SDK components (e.g., notification handlers,
  /// push trackers) that get disrupted when activity-alias states change.
  ///
  /// Has no effect on iOS.
  ///
  /// Example:
  /// ```dart
  /// await DynamicAppIconChanger.registerProtectedComponents([
  ///   ProtectedComponent(
  ///     className: 'com.moengage.pushbase.activities.PushTracker',
  ///     desiredState: ComponentState.enabled,
  ///   ),
  /// ]);
  /// ```
  static Future<void> registerProtectedComponents(
    List<ProtectedComponent> components,
  ) {
    return DynamicAppIconChangerPlatform.instance
        .registerProtectedComponents(components);
  }
}
