import 'package:flutter_test/flutter_test.dart';
import 'package:dynamic_icon_changer/dynamic_icon_changer.dart';
import 'package:dynamic_icon_changer/dynamic_icon_changer_platform_interface.dart';
import 'package:dynamic_icon_changer/dynamic_icon_changer_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDynamicIconChangerPlatform
    with MockPlatformInterfaceMixin
    implements DynamicIconChangerPlatform {
  @override
  Future<bool> supportsAlternateIcons() => Future.value(true);

  @override
  Future<String?> getAlternateIconName() => Future.value('TestIcon');

  @override
  Future<void> setAlternateIconName(String? iconName,
      {List<String>? blacklistedBrands}) async {}

  @override
  Future<void> setBadgeNumber(int count) async {}

  @override
  Future<int> getBadgeNumber() => Future.value(42);

  @override
  Future<void> registerProtectedComponents(
      List<ProtectedComponent> components) async {}
}

void main() {
  final DynamicIconChangerPlatform initialPlatform =
      DynamicIconChangerPlatform.instance;

  test('MethodChannelDynamicIconChanger is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDynamicIconChanger>());
  });

  group('DynamicIconChanger', () {
    late MockDynamicIconChangerPlatform fakePlatform;

    setUp(() {
      fakePlatform = MockDynamicIconChangerPlatform();
      DynamicIconChangerPlatform.instance = fakePlatform;
    });

    test('supportsAlternateIcons returns true', () async {
      expect(await DynamicIconChanger.supportsAlternateIcons, true);
    });

    test('alternateIconName returns mock value', () async {
      expect(await DynamicIconChanger.alternateIconName, 'TestIcon');
    });

    test('setAlternateIconName completes without error', () async {
      await DynamicIconChanger.setAlternateIconName('TestIcon');
    });

    test('setAlternateIconName with blacklist completes without error',
        () async {
      await DynamicIconChanger.setAlternateIconName('TestIcon',
          blacklistedBrands: ['samsung']);
    });

    test('setBadgeNumber completes without error', () async {
      await DynamicIconChanger.setBadgeNumber(5);
    });

    test('badgeNumber returns mock value', () async {
      expect(await DynamicIconChanger.badgeNumber, 42);
    });

    test('registerProtectedComponents completes without error', () async {
      await DynamicIconChanger.registerProtectedComponents([
        const ProtectedComponent(
          className: 'com.example.SomeReceiver',
          desiredState: ComponentState.enabled,
        ),
      ]);
    });

    test('registerProtectedComponents with empty list completes', () async {
      await DynamicIconChanger.registerProtectedComponents([]);
    });

    test('registerProtectedComponents with multiple components', () async {
      await DynamicIconChanger.registerProtectedComponents([
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
