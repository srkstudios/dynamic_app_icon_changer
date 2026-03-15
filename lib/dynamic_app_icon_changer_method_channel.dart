import 'package:flutter/services.dart';

import 'dynamic_app_icon_changer.dart';
import 'dynamic_app_icon_changer_platform_interface.dart';

/// [MethodChannel]-based implementation of [DynamicAppIconChangerPlatform].
class MethodChannelDynamicAppIconChanger extends DynamicAppIconChangerPlatform {
  final methodChannel = const MethodChannel('dynamic_app_icon_changer/methods');

  @override
  Future<bool> supportsAlternateIcons() async {
    return await methodChannel.invokeMethod<bool>('supportsAlternateIcons') ??
        false;
  }

  @override
  Future<String?> getAlternateIconName() {
    return methodChannel.invokeMethod<String?>('getAlternateIconName');
  }

  @override
  Future<void> setAlternateIconName(
    String? iconName, {
    List<String>? blacklistedBrands,
  }) {
    return methodChannel.invokeMethod('setAlternateIconName', {
      'iconName': iconName,
      'blacklistedBrands': blacklistedBrands,
    });
  }

  @override
  Future<void> setBadgeNumber(int count) {
    return methodChannel.invokeMethod('setBadgeNumber', {'count': count});
  }

  @override
  Future<int> getBadgeNumber() async {
    return await methodChannel.invokeMethod<int>('getBadgeNumber') ?? 0;
  }

  @override
  Future<void> registerProtectedComponents(
    List<ProtectedComponent> components,
  ) {
    return methodChannel.invokeMethod('registerProtectedComponents', {
      'components': components.map((c) => c.toMap()).toList(),
    });
  }
}
