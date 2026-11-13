import 'dart:async';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'dynamic_app_icon_changer.dart';
import 'dynamic_app_icon_changer_platform_interface.dart';

/// Web implementation of [DynamicAppIconChangerPlatform].
///
/// Changes the page favicon to switch "app icons" on the web.
/// Schedule and icon state are persisted in `localStorage`; start/end
/// transitions that fall within the current browsing session are applied
/// with in-page timers.
class DynamicAppIconChangerWeb extends DynamicAppIconChangerPlatform {
  /// Called by Flutter's web plugin registrant.
  static void registerWith(Registrar registrar) {
    final instance = DynamicAppIconChangerWeb();
    DynamicAppIconChangerPlatform.instance = instance;
    // Check schedule on registration and arm timers for this session.
    instance._checkSchedule();
  }

  static const _activeIconKey = 'dic_active_icon_name';
  static const _scheduleIconKey = 'dic_schedule_icon_name';
  static const _scheduleStartKey = 'dic_schedule_start_millis';
  static const _scheduleEndKey = 'dic_schedule_end_millis';

  /// The base path where icon files are located (relative to the document
  /// base URI). Users should place favicon files at `web/icons/<iconName>.png`.
  static const _iconBasePath = 'icons';

  /// The default favicon path.
  static const _defaultFavicon = 'favicon.png';

  /// Browsers clamp `setTimeout` delays to a 32-bit signed int (~24.8 days);
  /// longer delays fire immediately. Transitions further out than this are
  /// picked up on the next page load or [getActiveSchedule] call instead.
  static const _maxTimerDuration = Duration(days: 24);

  Timer? _startTimer;
  Timer? _endTimer;

  String? _badgeBaseTitle;
  int _badgeCount = 0;

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

    _armScheduleTimers();
  }

  @override
  Future<void> cancelScheduledIcon({bool resetToDefault = true}) async {
    _cancelScheduleTimers();
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
    // Show the badge count as a "(n) " prefix on the page title. The base
    // title is captured when a badge is first shown and kept in memory only,
    // so a title changed by the app is picked up again once the badge clears.
    if (count > 0) {
      _badgeBaseTitle ??= web.document.title;
      web.document.title = '($count) ${_badgeBaseTitle!}';
      _badgeCount = count;
    } else {
      if (_badgeBaseTitle != null) {
        web.document.title = _badgeBaseTitle!;
      }
      _badgeBaseTitle = null;
      _badgeCount = 0;
    }
  }

  @override
  Future<int> getBadgeNumber() async => _badgeCount;

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
      _cancelScheduleTimers();
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

    _armScheduleTimers();
  }

  /// Arms in-session timers for the pending start/end transitions so the
  /// favicon changes while the page stays open, not just on reload.
  void _armScheduleTimers() {
    _cancelScheduleTimers();

    final endMillis = int.tryParse(_getStorage(_scheduleEndKey) ?? '') ?? 0;
    if (endMillis == 0) return;

    final startMillis =
        int.tryParse(_getStorage(_scheduleStartKey) ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (startMillis > now) {
      final delay = Duration(milliseconds: startMillis - now);
      if (delay <= _maxTimerDuration) {
        _startTimer = Timer(delay, _checkSchedule);
      }
    }

    if (endMillis > now) {
      final delay = Duration(milliseconds: endMillis - now);
      if (delay <= _maxTimerDuration) {
        _endTimer = Timer(delay, _checkSchedule);
      }
    }
  }

  void _cancelScheduleTimers() {
    _startTimer?.cancel();
    _startTimer = null;
    _endTimer?.cancel();
    _endTimer = null;
  }

  // ── Favicon manipulation ───────────────────────────────────────────

  void _setFavicon(String href) {
    // Resolve against the document base URI so the favicon path works on
    // deep-linked routes (e.g. /settings/profile with a path URL strategy).
    final resolved =
        Uri.parse(web.document.baseURI).resolve(href).toString();

    // Find existing link[rel=icon] or create one
    final links = web.document.querySelectorAll('link[rel="icon"]');
    if (links.length > 0) {
      for (var i = 0; i < links.length; i++) {
        final link = links.item(i)! as web.HTMLLinkElement;
        link.href = resolved;
      }
    } else {
      final link = web.document.createElement('link') as web.HTMLLinkElement;
      link.rel = 'icon';
      link.href = resolved;
      web.document.head?.append(link);
    }

    // Also update shortcut icon if present
    final shortcutLinks =
        web.document.querySelectorAll('link[rel="shortcut icon"]');
    for (var i = 0; i < shortcutLinks.length; i++) {
      final link = shortcutLinks.item(i)! as web.HTMLLinkElement;
      link.href = resolved;
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
