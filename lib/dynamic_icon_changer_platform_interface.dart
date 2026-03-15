import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'dynamic_icon_changer.dart';
import 'dynamic_icon_changer_method_channel.dart';

/// Platform-agnostic interface for the dynamic_icon_changer plugin.
///
/// Platform-specific implementations should extend this class rather than
/// implement it directly, so that new methods can be added without breaking
/// existing implementations.  See [PlatformInterface] for details.
abstract class DynamicIconChangerPlatform extends PlatformInterface {
  DynamicIconChangerPlatform() : super(token: _token);

  static final Object _token = Object();

  static DynamicIconChangerPlatform _instance =
      MethodChannelDynamicIconChanger();

  /// The currently registered platform implementation.
  static DynamicIconChangerPlatform get instance => _instance;

  /// Registers a new platform implementation.
  ///
  /// Must be called before any plugin method is used (usually in the
  /// platform-specific plugin class).
  static set instance(DynamicIconChangerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Whether alternate icons are supported on this platform.
  Future<bool> supportsAlternateIcons();

  /// Returns the name of the currently active alternate icon, or `null`
  /// if the default icon is active.
  Future<String?> getAlternateIconName();

  /// Changes the launcher icon.
  ///
  /// Pass `null` for [iconName] to revert to the default icon.
  /// [blacklistedBrands] (Android-only) silently skips the change on
  /// matching manufacturers/models.
  Future<void> setAlternateIconName(
    String? iconName, {
    List<String>? blacklistedBrands,
  });

  /// Sets the app badge number (iOS only; no-op on Android).
  Future<void> setBadgeNumber(int count);

  /// Returns the current badge number (always 0 on Android).
  Future<int> getBadgeNumber();

  /// Registers Android components that should be protected during icon
  /// switches. No-op on iOS.
  Future<void> registerProtectedComponents(List<ProtectedComponent> components);
}
