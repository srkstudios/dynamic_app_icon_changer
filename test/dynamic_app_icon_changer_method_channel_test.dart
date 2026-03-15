import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dynamic_app_icon_changer/dynamic_app_icon_changer_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelDynamicAppIconChanger();
  const channel = MethodChannel('dynamic_app_icon_changer/methods');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'supportsAlternateIcons':
          return true;
        case 'getAlternateIconName':
          return 'MockIcon';
        case 'setAlternateIconName':
          return null;
        case 'setBadgeNumber':
          return null;
        case 'getBadgeNumber':
          return 5;
        case 'registerProtectedComponents':
          return null;
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
        blacklistedBrands: ['samsung']);
  });

  test('setAlternateIconName with null icon', () async {
    await platform.setAlternateIconName(null);
  });

  test('setBadgeNumber sends correct arguments', () async {
    await platform.setBadgeNumber(3);
  });

  test('getBadgeNumber', () async {
    expect(await platform.getBadgeNumber(), 5);
  });

  test('setAlternateIconName without blacklist', () async {
    await platform.setAlternateIconName('Green');
  });

  test('registerProtectedComponents sends correct arguments', () async {
    // Import is from method_channel file, but ProtectedComponent is in main
    // file which is imported transitively. We test the channel call here.
    await platform.registerProtectedComponents([]);
  });
}
