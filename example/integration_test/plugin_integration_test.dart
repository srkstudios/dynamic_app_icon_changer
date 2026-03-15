import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dynamic_icon_changer/dynamic_icon_changer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Support check ───────────────────────────────────────────────────

  group('supportsAlternateIcons', () {
    testWidgets('returns true on a real device', (tester) async {
      final supported = await DynamicIconChanger.supportsAlternateIcons;
      expect(supported, isTrue);
    });
  });

  // ── Default state ───────────────────────────────────────────────────

  group('default state', () {
    testWidgets('alternateIconName is null before any switch', (tester) async {
      // Ensure we start from default
      await DynamicIconChanger.setAlternateIconName(null);
      final iconName = await DynamicIconChanger.alternateIconName;
      expect(iconName, isNull);
    });
  });

  // ── Icon switching ──────────────────────────────────────────────────

  group('setAlternateIconName', () {
    tearDown(() async {
      // Always restore default icon after each test to keep state clean
      await DynamicIconChanger.setAlternateIconName(null);
    });

    testWidgets('switch to IconBlue and read back', (tester) async {
      await DynamicIconChanger.setAlternateIconName('IconBlue');
      final iconName = await DynamicIconChanger.alternateIconName;
      expect(iconName, equals('IconBlue'));
    });

    testWidgets('switch to IconGreen and read back', (tester) async {
      await DynamicIconChanger.setAlternateIconName('IconGreen');
      final iconName = await DynamicIconChanger.alternateIconName;
      expect(iconName, equals('IconGreen'));
    });

    testWidgets('switch to Blue then Green, verify only Green is active',
        (tester) async {
      await DynamicIconChanger.setAlternateIconName('IconBlue');
      await DynamicIconChanger.setAlternateIconName('IconGreen');
      final iconName = await DynamicIconChanger.alternateIconName;
      expect(iconName, equals('IconGreen'));
    });

    testWidgets('revert to default with null', (tester) async {
      await DynamicIconChanger.setAlternateIconName('IconBlue');
      await DynamicIconChanger.setAlternateIconName(null);
      final iconName = await DynamicIconChanger.alternateIconName;
      expect(iconName, isNull);
    });

    testWidgets('setting same icon twice does not throw', (tester) async {
      await DynamicIconChanger.setAlternateIconName('IconBlue');
      // Should not throw when setting the same icon again
      await DynamicIconChanger.setAlternateIconName('IconBlue');
      final iconName = await DynamicIconChanger.alternateIconName;
      expect(iconName, equals('IconBlue'));
    });

    testWidgets('setting default twice does not throw', (tester) async {
      await DynamicIconChanger.setAlternateIconName(null);
      await DynamicIconChanger.setAlternateIconName(null);
      final iconName = await DynamicIconChanger.alternateIconName;
      expect(iconName, isNull);
    });
  });

  // ── Error handling ──────────────────────────────────────────────────

  group('error handling', () {
    tearDown(() async {
      await DynamicIconChanger.setAlternateIconName(null);
    });

    testWidgets('setting a non-existent icon name throws',
        (tester) async {
      expect(
        () => DynamicIconChanger.setAlternateIconName('NonExistentIcon'),
        throwsA(isA<DynamicIconException>()),
      );
    });
  });

  // ── Blacklist (Android only) ────────────────────────────────────────

  group('blacklistedBrands', () {
    tearDown(() async {
      await DynamicIconChanger.setAlternateIconName(null);
    });

    testWidgets('blacklisting a non-matching brand allows the change',
        (tester) async {
      if (!Platform.isAndroid) return;

      await DynamicIconChanger.setAlternateIconName(
        'IconBlue',
        blacklistedBrands: ['__definitely_not_a_real_brand__'],
      );
      final iconName = await DynamicIconChanger.alternateIconName;
      expect(iconName, equals('IconBlue'));
    });

    testWidgets('empty blacklist allows the change', (tester) async {
      if (!Platform.isAndroid) return;

      await DynamicIconChanger.setAlternateIconName(
        'IconGreen',
        blacklistedBrands: [],
      );
      final iconName = await DynamicIconChanger.alternateIconName;
      expect(iconName, equals('IconGreen'));
    });
  });

  // ── Protected components (Android only) ─────────────────────────────

  group('registerProtectedComponents', () {
    testWidgets('registering empty list does not throw', (tester) async {
      await DynamicIconChanger.registerProtectedComponents([]);
    });

    testWidgets('registering components does not throw', (tester) async {
      if (!Platform.isAndroid) return;

      // Register a component that doesn't actually exist in this example app.
      // The plugin should not throw — it silently logs the error for unknown
      // components but does not fail the entire call.
      await DynamicIconChanger.registerProtectedComponents([
        const ProtectedComponent(
          className: 'com.example.test.FakeComponent',
          desiredState: ComponentState.enabled,
        ),
      ]);
    });

    testWidgets('registering multiple components with different states',
        (tester) async {
      if (!Platform.isAndroid) return;

      await DynamicIconChanger.registerProtectedComponents([
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

      await DynamicIconChanger.registerProtectedComponents([
        const ProtectedComponent(
          className: 'com.example.test.FakeComponent',
          desiredState: ComponentState.enabled,
        ),
      ]);

      // Switch icon — the plugin should toggle aliases AND restore protected
      // components without throwing.
      await DynamicIconChanger.setAlternateIconName('IconBlue');
      final iconName = await DynamicIconChanger.alternateIconName;
      expect(iconName, equals('IconBlue'));

      // Restore default
      await DynamicIconChanger.setAlternateIconName(null);
    });
  });

  // ── Badge number (iOS only) ─────────────────────────────────────────

  group('badge number', () {
    testWidgets('setBadgeNumber and getBadgeNumber round-trip',
        (tester) async {
      if (!Platform.isIOS) {
        // On Android, badge is a no-op — just verify it doesn't throw
        await DynamicIconChanger.setBadgeNumber(5);
        final badge = await DynamicIconChanger.badgeNumber;
        expect(badge, equals(0)); // always 0 on Android
        return;
      }

      // iOS: set and read back
      await DynamicIconChanger.setBadgeNumber(7);
      final badge = await DynamicIconChanger.badgeNumber;
      expect(badge, equals(7));

      // Clear
      await DynamicIconChanger.setBadgeNumber(0);
      final cleared = await DynamicIconChanger.badgeNumber;
      expect(cleared, equals(0));
    });
  });

  // ── Full round-trip: switch → read → restore ───────────────────────

  group('full round-trip', () {
    testWidgets('default → Blue → Green → default', (tester) async {
      // Start from default
      await DynamicIconChanger.setAlternateIconName(null);
      expect(await DynamicIconChanger.alternateIconName, isNull);

      // Switch to Blue
      await DynamicIconChanger.setAlternateIconName('IconBlue');
      expect(await DynamicIconChanger.alternateIconName, equals('IconBlue'));

      // Switch to Green
      await DynamicIconChanger.setAlternateIconName('IconGreen');
      expect(await DynamicIconChanger.alternateIconName, equals('IconGreen'));

      // Restore default
      await DynamicIconChanger.setAlternateIconName(null);
      expect(await DynamicIconChanger.alternateIconName, isNull);
    });
  });
}
