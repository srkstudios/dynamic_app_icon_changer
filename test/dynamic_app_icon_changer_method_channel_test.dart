import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dynamic_app_icon_changer/dynamic_app_icon_changer.dart';
import 'package:dynamic_app_icon_changer/dynamic_app_icon_changer_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelDynamicAppIconChanger();
  const channel = MethodChannel('dynamic_app_icon_changer/methods');

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'supportsAlternateIcons':
          return true;
        case 'getAlternateIconName':
          return 'MockIcon';
        case 'getBadgeNumber':
          return 5;
        case 'getActiveSchedule':
          return <String, dynamic>{
            'iconName': 'IconBlue',
            'startAtMillis': 1000,
            'endAtMillis': 2000,
            'isActive': true,
          };
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('supportsAlternateIcons', () async {
    expect(await platform.supportsAlternateIcons(), true);
  });

  test('getAlternateIconName', () async {
    expect(await platform.getAlternateIconName(), 'MockIcon');
  });

  test('setAlternateIconName sends correct arguments', () async {
    await platform.setAlternateIconName('Blue',
        blacklistedBrands: ['samsung'], relaunch: true);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setAlternateIconName');
    expect(calls.single.arguments, {
      'iconName': 'Blue',
      'blacklistedBrands': ['samsung'],
      'relaunch': true,
    });
  });

  test('setAlternateIconName with null icon', () async {
    await platform.setAlternateIconName(null);

    expect(calls.single.arguments, {
      'iconName': null,
      'blacklistedBrands': null,
      'relaunch': false,
    });
  });

  test('scheduleAlternateIcon sends epoch millis', () async {
    final start = DateTime(2026, 12, 20);
    final end = DateTime(2026, 12, 26);
    await platform.scheduleAlternateIcon('IconChristmas',
        startAt: start, endAt: end);

    expect(calls.single.method, 'scheduleAlternateIcon');
    expect(calls.single.arguments, {
      'iconName': 'IconChristmas',
      'startAtMillis': start.millisecondsSinceEpoch,
      'endAtMillis': end.millisecondsSinceEpoch,
      'blacklistedBrands': null,
    });
  });

  test('cancelScheduledIcon sends resetToDefault', () async {
    await platform.cancelScheduledIcon(resetToDefault: false);

    expect(calls.single.method, 'cancelScheduledIcon');
    expect(calls.single.arguments, {'resetToDefault': false});
  });

  test('getActiveSchedule parses the returned map', () async {
    final schedule = await platform.getActiveSchedule();

    expect(schedule, isNotNull);
    expect(schedule!.iconName, 'IconBlue');
    expect(schedule.startAt, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(schedule.endAt, DateTime.fromMillisecondsSinceEpoch(2000));
    expect(schedule.isActive, true);
  });

  test('setBadgeNumber sends correct arguments', () async {
    await platform.setBadgeNumber(3);

    expect(calls.single.method, 'setBadgeNumber');
    expect(calls.single.arguments, {'count': 3});
  });

  test('getBadgeNumber', () async {
    expect(await platform.getBadgeNumber(), 5);
  });

  test('registerProtectedComponents serialises components', () async {
    await platform.registerProtectedComponents([
      const ProtectedComponent(
        className: 'com.example.MyReceiver',
        desiredState: ComponentState.enabled,
      ),
    ]);

    expect(calls.single.method, 'registerProtectedComponents');
    expect(calls.single.arguments, {
      'components': [
        {'className': 'com.example.MyReceiver', 'desiredState': 'enabled'},
      ],
    });
  });
}
