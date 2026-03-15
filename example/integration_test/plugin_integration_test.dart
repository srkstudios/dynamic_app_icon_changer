import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dynamic_app_icon_changer/dynamic_app_icon_changer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Support check ───────────────────────────────────────────────────

  group('supportsAlternateIcons', () {
    testWidgets('returns true on a real device', (tester) async {
      final supported = await DynamicAppIconChanger.supportsAlternateIcons;
      expect(supported, isTrue);
    });
  });

  // ── Default state ───────────────────────────────────────────────────

  group('default state', () {
    testWidgets('alternateIconName is null before any switch', (tester) async {
      // Ensure we start from default
      await DynamicAppIconChanger.setAlternateIconName(null);
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, isNull);
    });
  });

  // ── Icon switching ──────────────────────────────────────────────────

  group('setAlternateIconName', () {
    tearDown(() async {
      // Always restore default icon after each test to keep state clean
      await DynamicAppIconChanger.setAlternateIconName(null);
    });

    testWidgets('switch to IconBlue and read back', (tester) async {
      await DynamicAppIconChanger.setAlternateIconName('IconBlue');
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, equals('IconBlue'));
    });

    testWidgets('switch to IconGreen and read back', (tester) async {
      await DynamicAppIconChanger.setAlternateIconName('IconGreen');
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, equals('IconGreen'));
    });

    testWidgets('switch to Blue then Green, verify only Green is active',
        (tester) async {
      await DynamicAppIconChanger.setAlternateIconName('IconBlue');
      await DynamicAppIconChanger.setAlternateIconName('IconGreen');
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, equals('IconGreen'));
    });

    testWidgets('revert to default with null', (tester) async {
      await DynamicAppIconChanger.setAlternateIconName('IconBlue');
      await DynamicAppIconChanger.setAlternateIconName(null);
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, isNull);
    });

    testWidgets('setting same icon twice does not throw', (tester) async {
      await DynamicAppIconChanger.setAlternateIconName('IconBlue');
      // Should not throw when setting the same icon again
      await DynamicAppIconChanger.setAlternateIconName('IconBlue');
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, equals('IconBlue'));
    });

    testWidgets('setting default twice does not throw', (tester) async {
      await DynamicAppIconChanger.setAlternateIconName(null);
      await DynamicAppIconChanger.setAlternateIconName(null);
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, isNull);
    });
  });

  // ── Relaunch (Android only) ─────────────────────────────────────────

  group('relaunch', () {
    tearDown(() async {
      await DynamicAppIconChanger.setAlternateIconName(null);
    });

    testWidgets('setAlternateIconName with relaunch=false does not throw',
        (tester) async {
      await DynamicAppIconChanger.setAlternateIconName(
        'IconBlue',
        relaunch: false,
      );
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, equals('IconBlue'));
    });

    // Note: relaunch=true kills the app — can't be tested in integration tests.
    // Just verify the parameter is accepted without error.
  });

  // ── Error handling ──────────────────────────────────────────────────

  group('error handling', () {
    tearDown(() async {
      await DynamicAppIconChanger.setAlternateIconName(null);
    });

    testWidgets('setting a non-existent icon name throws',
        (tester) async {
      expect(
        () => DynamicAppIconChanger.setAlternateIconName('NonExistentIcon'),
        throwsA(isA<DynamicIconException>()),
      );
    });
  });

  // ── Blacklist (Android only) ────────────────────────────────────────

  group('blacklistedBrands', () {
    tearDown(() async {
      await DynamicAppIconChanger.setAlternateIconName(null);
    });

    testWidgets('blacklisting a non-matching brand allows the change',
        (tester) async {
      if (!Platform.isAndroid) return;

      await DynamicAppIconChanger.setAlternateIconName(
        'IconBlue',
        blacklistedBrands: ['__definitely_not_a_real_brand__'],
      );
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, equals('IconBlue'));
    });

    testWidgets('empty blacklist allows the change', (tester) async {
      if (!Platform.isAndroid) return;

      await DynamicAppIconChanger.setAlternateIconName(
        'IconGreen',
        blacklistedBrands: [],
      );
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, equals('IconGreen'));
    });
  });

  // ── Protected components (Android only) ─────────────────────────────

  group('registerProtectedComponents', () {
    testWidgets('registering empty list does not throw', (tester) async {
      await DynamicAppIconChanger.registerProtectedComponents([]);
    });

    testWidgets('registering components does not throw', (tester) async {
      if (!Platform.isAndroid) return;

      // Register a component that doesn't actually exist in this example app.
      // The plugin should not throw — it silently logs the error for unknown
      // components but does not fail the entire call.
      await DynamicAppIconChanger.registerProtectedComponents([
        const ProtectedComponent(
          className: 'com.example.test.FakeComponent',
          desiredState: ComponentState.enabled,
        ),
      ]);
    });

    testWidgets('registering multiple components with different states',
        (tester) async {
      if (!Platform.isAndroid) return;

      await DynamicAppIconChanger.registerProtectedComponents([
        const ProtectedComponent(
          className: 'com.example.test.ComponentA',
          desiredState: ComponentState.enabled,
        ),
        const ProtectedComponent(
          className: 'com.example.test.ComponentB',
          desiredState: ComponentState.disabled,
        ),
        const ProtectedComponent(
          className: 'com.example.test.ComponentC',
          desiredState: ComponentState.defaultState,
        ),
      ]);
    });

    testWidgets(
        'icon switch after registering protected components does not throw',
        (tester) async {
      if (!Platform.isAndroid) return;

      await DynamicAppIconChanger.registerProtectedComponents([
        const ProtectedComponent(
          className: 'com.example.test.FakeComponent',
          desiredState: ComponentState.enabled,
        ),
      ]);

      // Switch icon — the plugin should toggle aliases AND restore protected
      // components without throwing.
      await DynamicAppIconChanger.setAlternateIconName('IconBlue');
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, equals('IconBlue'));

      // Restore default
      await DynamicAppIconChanger.setAlternateIconName(null);
    });
  });

  // ── Scheduled icon ──────────────────────────────────────────────────

  group('scheduleAlternateIcon', () {
    tearDown(() async {
      await DynamicAppIconChanger.cancelScheduledIcon();
    });

    testWidgets('schedule with immediate start sets icon', (tester) async {
      final endAt = DateTime.now().add(const Duration(hours: 1));

      await DynamicAppIconChanger.scheduleAlternateIcon(
        'IconBlue',
        endAt: endAt,
      );

      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, equals('IconBlue'));
    });

    testWidgets('schedule info is returned correctly', (tester) async {
      final endAt = DateTime.now().add(const Duration(hours: 2));

      await DynamicAppIconChanger.scheduleAlternateIcon(
        'IconGreen',
        endAt: endAt,
      );

      final schedule = await DynamicAppIconChanger.activeSchedule;
      expect(schedule, isNotNull);
      expect(schedule!.iconName, equals('IconGreen'));
      expect(schedule.isActive, isTrue);
      // endAt should be roughly 2 hours from now
      expect(
        schedule.endAt.difference(DateTime.now()).inMinutes,
        greaterThanOrEqualTo(119),
      );
    });

    testWidgets('schedule with future start does not change icon immediately',
        (tester) async {
      // First ensure we're on default
      await DynamicAppIconChanger.setAlternateIconName(null);

      final startAt = DateTime.now().add(const Duration(hours: 1));
      final endAt = DateTime.now().add(const Duration(hours: 2));

      await DynamicAppIconChanger.scheduleAlternateIcon(
        'IconBlue',
        startAt: startAt,
        endAt: endAt,
      );

      // Icon should still be default since start is in the future
      final iconName = await DynamicAppIconChanger.alternateIconName;
      expect(iconName, isNull);

      // But schedule info should exist and show not-yet-active
      final schedule = await DynamicAppIconChanger.activeSchedule;
      expect(schedule, isNotNull);
      expect(schedule!.iconName, equals('IconBlue'));
      expect(schedule.isActive, isFalse);
    });

    testWidgets('cancelScheduledIcon resets to default', (tester) async {
      final endAt = DateTime.now().add(const Duration(hours: 1));

      await DynamicAppIconChanger.scheduleAlternateIcon(
        'IconGreen',
        endAt: endAt,
      );

      // Should be active
      expect(await DynamicAppIconChanger.alternateIconName, equals('IconGreen'));

      // Cancel and reset
      await DynamicAppIconChanger.cancelScheduledIcon();

      expect(await DynamicAppIconChanger.alternateIconName, isNull);
      expect(await DynamicAppIconChanger.activeSchedule, isNull);
    });

    testWidgets('cancelScheduledIcon with resetToDefault=false keeps icon',
        (tester) async {
      final endAt = DateTime.now().add(const Duration(hours: 1));

      await DynamicAppIconChanger.scheduleAlternateIcon(
        'IconBlue',
        endAt: endAt,
      );

      expect(await DynamicAppIconChanger.alternateIconName, equals('IconBlue'));

      // Cancel without resetting
      await DynamicAppIconChanger.cancelScheduledIcon(resetToDefault: false);

      // Icon should still be Blue, but schedule gone
      expect(await DynamicAppIconChanger.alternateIconName, equals('IconBlue'));
      expect(await DynamicAppIconChanger.activeSchedule, isNull);

      // Clean up
      await DynamicAppIconChanger.setAlternateIconName(null);
    });

    testWidgets('endAt in the past throws INVALID_SCHEDULE', (tester) async {
      final pastEnd = DateTime.now().subtract(const Duration(hours: 1));

      expect(
        () => DynamicAppIconChanger.scheduleAlternateIcon(
          'IconBlue',
          endAt: pastEnd,
        ),
        throwsA(isA<DynamicIconException>()),
      );
    });

    testWidgets('endAt before startAt throws INVALID_SCHEDULE', (tester) async {
      final startAt = DateTime.now().add(const Duration(hours: 2));
      final endAt = DateTime.now().add(const Duration(hours: 1));

      expect(
        () => DynamicAppIconChanger.scheduleAlternateIcon(
          'IconBlue',
          startAt: startAt,
          endAt: endAt,
        ),
        throwsA(isA<DynamicIconException>()),
      );
    });

    testWidgets('new schedule replaces existing one', (tester) async {
      final endAt1 = DateTime.now().add(const Duration(hours: 1));
      final endAt2 = DateTime.now().add(const Duration(hours: 3));

      await DynamicAppIconChanger.scheduleAlternateIcon(
        'IconBlue',
        endAt: endAt1,
      );

      await DynamicAppIconChanger.scheduleAlternateIcon(
        'IconGreen',
        endAt: endAt2,
      );

      final schedule = await DynamicAppIconChanger.activeSchedule;
      expect(schedule, isNotNull);
      expect(schedule!.iconName, equals('IconGreen'));
      expect(await DynamicAppIconChanger.alternateIconName, equals('IconGreen'));
    });
  });

  // ── Badge number (iOS only) ─────────────────────────────────────────

  group('badge number', () {
    testWidgets('setBadgeNumber and getBadgeNumber round-trip',
        (tester) async {
      if (!Platform.isIOS) {
        // On Android, badge is a no-op — just verify it doesn't throw
        await DynamicAppIconChanger.setBadgeNumber(5);
        final badge = await DynamicAppIconChanger.badgeNumber;
        expect(badge, equals(0)); // always 0 on Android
        return;
      }

      // iOS: set and read back
      await DynamicAppIconChanger.setBadgeNumber(7);
      final badge = await DynamicAppIconChanger.badgeNumber;
      expect(badge, equals(7));

      // Clear
      await DynamicAppIconChanger.setBadgeNumber(0);
      final cleared = await DynamicAppIconChanger.badgeNumber;
      expect(cleared, equals(0));
    });
  });

  // ── Full round-trip: switch → read → restore ───────────────────────

  group('full round-trip', () {
    testWidgets('default → Blue → Green → default', (tester) async {
      // Start from default
      await DynamicAppIconChanger.setAlternateIconName(null);
      expect(await DynamicAppIconChanger.alternateIconName, isNull);

      // Switch to Blue
      await DynamicAppIconChanger.setAlternateIconName('IconBlue');
      expect(await DynamicAppIconChanger.alternateIconName, equals('IconBlue'));

      // Switch to Green
      await DynamicAppIconChanger.setAlternateIconName('IconGreen');
      expect(await DynamicAppIconChanger.alternateIconName, equals('IconGreen'));

      // Restore default
      await DynamicAppIconChanger.setAlternateIconName(null);
      expect(await DynamicAppIconChanger.alternateIconName, isNull);
    });

    testWidgets('schedule → cancel → manual switch → default', (tester) async {
      // Schedule an icon
      final endAt = DateTime.now().add(const Duration(hours: 1));
      await DynamicAppIconChanger.scheduleAlternateIcon(
        'IconBlue',
        endAt: endAt,
      );
      expect(await DynamicAppIconChanger.alternateIconName, equals('IconBlue'));

      // Cancel without reset
      await DynamicAppIconChanger.cancelScheduledIcon(resetToDefault: false);
      expect(await DynamicAppIconChanger.alternateIconName, equals('IconBlue'));

      // Manual switch to Green
      await DynamicAppIconChanger.setAlternateIconName('IconGreen');
      expect(await DynamicAppIconChanger.alternateIconName, equals('IconGreen'));

      // Restore default
      await DynamicAppIconChanger.setAlternateIconName(null);
      expect(await DynamicAppIconChanger.alternateIconName, isNull);
    });
  });
}
