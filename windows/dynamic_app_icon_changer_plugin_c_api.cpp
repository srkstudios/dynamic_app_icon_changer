#include "include/dynamic_app_icon_changer/dynamic_app_icon_changer_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "dynamic_app_icon_changer_plugin.h"

void DynamicAppIconChangerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  dynamic_app_icon_changer::DynamicAppIconChangerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
