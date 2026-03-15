import 'package:web/web.dart' as web;

import 'dynamic_app_icon_changer.dart';
import 'dynamic_app_icon_changer_platform_interface.dart';

/// Web implementation of [DynamicAppIconChangerPlatform].
///
/// Changes the page favicon to switch "app icons" on the web.
/// Schedule and icon state are persisted in `localStorage`.
class DynamicAppIconChangerWeb extends DynamicAppIconChangerPlatform {
  /// Called by Flutter's plugin registrant.
  static void registerWith([Object? registrar]) {
    DynamicAppIconChangerPlatform.instance = DynamicAppIconChangerWeb();
    // Check schedule on registration
    (DynamicAppIconChangerPlatform.instance as DynamicAppIconChangerWeb)
        ._checkSchedule();
  }

  static const _activeIconKey = 'dic_active_icon_name';
  static const _scheduleIconKey = 'dic_schedule_icon_name';
  static const _scheduleStartKey = 'dic_schedule_start_millis';
  static const _scheduleEndKey = 'dic_schedule_end_millis';

  /// The base path where icon files are located (relative to web root).
  /// Users should place favicon files at `web/icons/<iconName>.png`.
  static const _iconBasePath = 'icons';

  /// The default favicon path.
  static const _defaultFavicon = 'favicon.png';

  @override
  Future<bool> supportsAlternateIcons() async => true;

  @override
  Future<String?> getAlternateIconName() async {
    return _getStorage(_activeIconKey);
  }

  @override
  Future<void> setAlternateIconName(
    String? iconName, {
    List<String>? blacklistedBrands,
    bool relaunch = false,
  }) async {
    if (iconName != null) {
      _setFavicon('$_iconBasePath/$iconName.png');
      _setStorage(_activeIconKey, iconName);
    } else {
      _setFavicon(_defaultFavicon);
      _removeStorage(_activeIconKey);
    }
  }

  @override
  Future<void> scheduleAlternateIcon(
    String iconName, {
    DateTime? startAt,
    required DateTime endAt,
    List<String>? blacklistedBrands,
  }) async {
    final startMillis = startAt?.millisecondsSinceEpoch ?? 0;
    final endMillis = endAt.millisecondsSinceEpoch;

    _setStorage(_scheduleIconKey, iconName);
    _setStorage(_scheduleStartKey, startMillis.toString());
    _setStorage(_scheduleEndKey, endMillis.toString());

    final now = DateTime.now().millisecondsSinceEpoch;
    if (startMillis == 0 || now >= startMillis) {
      _setFavicon('$_iconBasePath/$iconName.png');
      _setStorage(_activeIconKey, iconName);
    }
  }

  @override
  Future<void> cancelScheduledIcon({bool resetToDefault = true}) async {
    _removeStorage(_scheduleIconKey);
    _removeStorage(_scheduleStartKey);
    _removeStorage(_scheduleEndKey);

    if (resetToDefault) {
      _setFavicon(_defaultFavicon);
      _removeStorage(_activeIconKey);
    }
  }

  @override
  Future<ScheduleInfo?> getActiveSchedule() async {
    _checkSchedule();
    final iconName = _getStorage(_scheduleIconKey);
    if (iconName == null) return null;

    final endMillis = int.tryParse(_getStorage(_scheduleEndKey) ?? '') ?? 0;
    if (endMillis == 0) return null;

    final startMillis =
        int.tryParse(_getStorage(_scheduleStartKey) ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final isActive = (startMillis == 0 || now >= startMillis) && now < endMillis;

    return ScheduleInfo(
      iconName: iconName,
      startAt: startMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(startMillis)
          : null,
      endAt: DateTime.fromMillisecondsSinceEpoch(endMillis),
      isActive: isActive,
    );
  }

  @override
  Future<void> setBadgeNumber(int count) async {
    // Update the page title with a badge indicator
    final baseTitle =
        _getStorage('dic_base_title') ?? web.document.title;
    _setStorage('dic_base_title', baseTitle);
    if (count > 0) {
      web.document.title = '($count) $baseTitle';
    } else {
      web.document.title = baseTitle;
    }
  }

  @override
  Future<int> getBadgeNumber() async {
    final title = web.document.title;
    final match = RegExp(r'^\((\d+)\) ').firstMatch(title);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  @override
  Future<void> registerProtectedComponents(
    List<ProtectedComponent> components,
  ) async {
    // No-op on web
  }

  // ── Schedule checking ──────────────────────────────────────────────

  void _checkSchedule() {
    final iconName = _getStorage(_scheduleIconKey);
    if (iconName == null) return;

    final endMillis = int.tryParse(_getStorage(_scheduleEndKey) ?? '') ?? 0;
    if (endMillis == 0) return;

    final startMillis =
        int.tryParse(_getStorage(_scheduleStartKey) ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now >= endMillis) {
      // Expired
      _removeStorage(_scheduleIconKey);
      _removeStorage(_scheduleStartKey);
      _removeStorage(_scheduleEndKey);
      _setFavicon(_defaultFavicon);
      _removeStorage(_activeIconKey);
      return;
    }

    if (startMillis == 0 || now >= startMillis) {
      final current = _getStorage(_activeIconKey);
      if (current != iconName) {
        _setFavicon('$_iconBasePath/$iconName.png');
        _setStorage(_activeIconKey, iconName);
      }
    }
  }

  // ── Favicon manipulation ───────────────────────────────────────────

  void _setFavicon(String href) {
    // Find existing link[rel=icon] or create one
    final links = web.document.querySelectorAll('link[rel="icon"]');
    if (links.length > 0) {
      for (var i = 0; i < links.length; i++) {
        final link = links.item(i)! as web.HTMLLinkElement;
        link.href = href;
      }
    } else {
      final link = web.document.createElement('link') as web.HTMLLinkElement;
      link.rel = 'icon';
      link.href = href;
      web.document.head?.append(link);
    }

    // Also update shortcut icon if present
    final shortcutLinks =
        web.document.querySelectorAll('link[rel="shortcut icon"]');
    for (var i = 0; i < shortcutLinks.length; i++) {
      final link = shortcutLinks.item(i)! as web.HTMLLinkElement;
      link.href = href;
    }
  }

  // ── localStorage helpers ───────────────────────────────────────────

  String? _getStorage(String key) {
    return web.window.localStorage.getItem(key);
  }

  void _setStorage(String key, String value) {
    web.window.localStorage.setItem(key, value);
  }

  void _removeStorage(String key) {
    web.window.localStorage.removeItem(key);
  }
}
