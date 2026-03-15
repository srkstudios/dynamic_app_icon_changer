import 'dynamic_app_icon_changer.dart';
import 'dynamic_app_icon_changer_platform_interface.dart';

/// Stub implementation for platforms that don't support dynamic icon switching
/// (Windows, Linux, macOS, Web).
///
/// All methods return safe defaults so consuming apps don't need platform
/// checks. [supportsAlternateIcons] returns `false` — callers should check
/// this before attempting icon changes.
class DynamicAppIconChangerStub extends DynamicAppIconChangerPlatform {
  /// Registers this stub as the platform implementation.
  /// Called automatically by Flutter's plugin registration system.
  static void registerWith([Object? registrar]) {
    DynamicAppIconChangerPlatform.instance = DynamicAppIconChangerStub();
  }

  @override
  Future<bool> supportsAlternateIcons() => Future.value(false);

  @override
  Future<String?> getAlternateIconName() => Future.value(null);

  @override
  Future<void> setAlternateIconName(
    String? iconName, {
    List<String>? blacklistedBrands,
    bool relaunch = false,
  }) async {}

  @override
  Future<void> scheduleAlternateIcon(
    String iconName, {
    DateTime? startAt,
    required DateTime endAt,
    List<String>? blacklistedBrands,
  }) async {}

  @override
  Future<void> cancelScheduledIcon({bool resetToDefault = true}) async {}

  @override
  Future<ScheduleInfo?> getActiveSchedule() => Future.value(null);

  @override
  Future<void> setBadgeNumber(int count) async {}

  @override
  Future<int> getBadgeNumber() => Future.value(0);

  @override
  Future<void> registerProtectedComponents(
    List<ProtectedComponent> components,
  ) async {}
}
