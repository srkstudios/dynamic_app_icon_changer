import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dynamic_app_icon_changer/dynamic_app_icon_changer.dart';
import 'package:dynamic_app_icon_changer/dynamic_app_icon_changer_platform_interface.dart';
import 'package:dynamic_app_icon_changer/dynamic_app_icon_changer_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDynamicAppIconChangerPlatform
    with MockPlatformInterfaceMixin
    implements DynamicAppIconChangerPlatform {
  @override
  Future<bool> supportsAlternateIcons() => Future.value(true);

  @override
  Future<String?> getAlternateIconName() => Future.value('TestIcon');

  @override
  Future<void> setAlternateIconName(String? iconName,
      {List<String>? blacklistedBrands, bool relaunch = false}) async {}

  @override
  Future<void> setBadgeNumber(int count) async {}

  @override
  Future<int> getBadgeNumber() => Future.value(42);

  @override
  Future<void> registerProtectedComponents(
      List<ProtectedComponent> components) async {}

  @override
  Future<void> scheduleAlternateIcon(String iconName,
      {DateTime? startAt,
      required DateTime endAt,
      List<String>? blacklistedBrands}) async {}

  @override
  Future<void> cancelScheduledIcon({bool resetToDefault = true}) async {}

  @override
  Future<ScheduleInfo?> getActiveSchedule() => Future.value(null);
}

/// Mock platform whose mutating methods fail with a [PlatformException],
/// mimicking a real method-channel error.
class ThrowingMockPlatform extends MockDynamicAppIconChangerPlatform {
  @override
  Future<void> setAlternateIconName(String? iconName,
      {List<String>? blacklistedBrands, bool relaunch = false}) {
    throw PlatformException(
        code: 'ICON_NOT_FOUND', message: 'No alias named X');
  }

  @override
  Future<void> scheduleAlternateIcon(String iconName,
      {DateTime? startAt,
      required DateTime endAt,
      List<String>? blacklistedBrands}) {
    throw PlatformException(code: 'SCHEDULE_FAILED', message: 'boom');
  }
}

void main() {
  final DynamicAppIconChangerPlatform initialPlatform =
      DynamicAppIconChangerPlatform.instance;

  test('MethodChannelDynamicAppIconChanger is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDynamicAppIconChanger>());
  });

  group('DynamicAppIconChanger', () {
    late MockDynamicAppIconChangerPlatform fakePlatform;

    setUp(() {
      fakePlatform = MockDynamicAppIconChangerPlatform();
      DynamicAppIconChangerPlatform.instance = fakePlatform;
    });

    test('supportsAlternateIcons returns true', () async {
      expect(await DynamicAppIconChanger.supportsAlternateIcons, true);
    });

    test('alternateIconName returns mock value', () async {
      expect(await DynamicAppIconChanger.alternateIconName, 'TestIcon');
    });

    test('setAlternateIconName completes without error', () async {
      await DynamicAppIconChanger.setAlternateIconName('TestIcon');
    });

    test('setAlternateIconName with blacklist completes without error',
        () async {
      await DynamicAppIconChanger.setAlternateIconName('TestIcon',
          blacklistedBrands: ['samsung']);
    });

    test('setBadgeNumber completes without error', () async {
      await DynamicAppIconChanger.setBadgeNumber(5);
    });

    test('badgeNumber returns mock value', () async {
      expect(await DynamicAppIconChanger.badgeNumber, 42);
    });

    test('registerProtectedComponents completes without error', () async {
      await DynamicAppIconChanger.registerProtectedComponents([
        const ProtectedComponent(
          className: 'com.example.SomeReceiver',
          desiredState: ComponentState.enabled,
        ),
      ]);
    });

    test('registerProtectedComponents with empty list completes', () async {
      await DynamicAppIconChanger.registerProtectedComponents([]);
    });

    test('registerProtectedComponents with multiple components', () async {
      await DynamicAppIconChanger.registerProtectedComponents([
        const ProtectedComponent(
          className: 'com.moengage.pushbase.activities.PushTracker',
          desiredState: ComponentState.enabled,
        ),
        const ProtectedComponent(
          className: 'com.example.SomeService',
          desiredState: ComponentState.disabled,
        ),
        const ProtectedComponent(
          className: 'com.example.DefaultReceiver',
          desiredState: ComponentState.defaultState,
        ),
      ]);
    });
  });

  group('scheduleAlternateIcon validation', () {
    setUp(() {
      DynamicAppIconChangerPlatform.instance =
          MockDynamicAppIconChangerPlatform();
    });

    test('throws INVALID_SCHEDULE when endAt is in the past', () async {
      await expectLater(
        DynamicAppIconChanger.scheduleAlternateIcon(
          'IconBlue',
          endAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
        throwsA(isA<DynamicIconException>()
            .having((e) => e.code, 'code', 'INVALID_SCHEDULE')),
      );
    });

    test('throws INVALID_SCHEDULE when endAt is before startAt', () async {
      final start = DateTime.now().add(const Duration(days: 2));
      final end = DateTime.now().add(const Duration(days: 1));
      await expectLater(
        DynamicAppIconChanger.scheduleAlternateIcon(
          'IconBlue',
          startAt: start,
          endAt: end,
        ),
        throwsA(isA<DynamicIconException>()
            .having((e) => e.code, 'code', 'INVALID_SCHEDULE')),
      );
    });

    test('accepts a valid future window', () async {
      await DynamicAppIconChanger.scheduleAlternateIcon(
        'IconBlue',
        startAt: DateTime.now().add(const Duration(hours: 1)),
        endAt: DateTime.now().add(const Duration(hours: 2)),
      );
    });
  });

  group('PlatformException wrapping', () {
    setUp(() {
      DynamicAppIconChangerPlatform.instance = ThrowingMockPlatform();
    });

    test('setAlternateIconName preserves the platform error code', () async {
      await expectLater(
        DynamicAppIconChanger.setAlternateIconName('Missing'),
        throwsA(isA<DynamicIconException>()
            .having((e) => e.code, 'code', 'ICON_NOT_FOUND')
            .having((e) => e.message, 'message', 'No alias named X')),
      );
    });

    test('scheduleAlternateIcon preserves the platform error code', () async {
      await expectLater(
        DynamicAppIconChanger.scheduleAlternateIcon(
          'IconBlue',
          endAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        throwsA(isA<DynamicIconException>()
            .having((e) => e.code, 'code', 'SCHEDULE_FAILED')),
      );
    });
  });

  group('ScheduleInfo', () {
    test('fromMap parses a full schedule', () {
      final info = ScheduleInfo.fromMap({
        'iconName': 'IconBlue',
        'startAtMillis': 1000,
        'endAtMillis': 2000,
        'isActive': true,
      });
      expect(info.iconName, 'IconBlue');
      expect(info.startAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(info.endAt, DateTime.fromMillisecondsSinceEpoch(2000));
      expect(info.isActive, true);
    });

    test('fromMap handles a null startAtMillis', () {
      final info = ScheduleInfo.fromMap({
        'iconName': 'IconGreen',
        'startAtMillis': null,
        'endAtMillis': 5000,
        'isActive': false,
      });
      expect(info.startAt, isNull);
      expect(info.endAt, DateTime.fromMillisecondsSinceEpoch(5000));
      expect(info.isActive, false);
    });
  });

  group('DynamicIconException', () {
    test('toString includes code when present', () {
      final e =
          DynamicIconException('test error', code: 'ICON_NOT_FOUND');
      expect(e.toString(),
          'DynamicIconException(ICON_NOT_FOUND): test error');
    });

    test('toString omits code when null', () {
      final e = DynamicIconException('test error');
      expect(e.toString(), 'DynamicIconException: test error');
    });
  });

  group('ProtectedComponent', () {
    test('toMap serialises correctly for enabled state', () {
      const component = ProtectedComponent(
        className: 'com.example.MyReceiver',
        desiredState: ComponentState.enabled,
      );
      expect(component.toMap(), {
        'className': 'com.example.MyReceiver',
        'desiredState': 'enabled',
      });
    });

    test('toMap serialises correctly for disabled state', () {
      const component = ProtectedComponent(
        className: 'com.example.MyReceiver',
        desiredState: ComponentState.disabled,
      );
      expect(component.toMap(), {
        'className': 'com.example.MyReceiver',
        'desiredState': 'disabled',
      });
    });

    test('toMap serialises correctly for defaultState', () {
      const component = ProtectedComponent(
        className: 'com.example.MyReceiver',
        desiredState: ComponentState.defaultState,
      );
      expect(component.toMap(), {
        'className': 'com.example.MyReceiver',
        'desiredState': 'defaultState',
      });
    });
  });

  group('ComponentState', () {
    test('has all expected values', () {
      expect(ComponentState.values, hasLength(3));
      expect(ComponentState.values,
          contains(ComponentState.enabled));
      expect(ComponentState.values,
          contains(ComponentState.disabled));
      expect(ComponentState.values,
          contains(ComponentState.defaultState));
    });
  });
}
