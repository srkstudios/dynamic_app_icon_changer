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
  });
}
