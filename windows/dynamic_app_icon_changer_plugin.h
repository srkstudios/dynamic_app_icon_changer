#ifndef FLUTTER_PLUGIN_DYNAMIC_APP_ICON_CHANGER_PLUGIN_H_
#define FLUTTER_PLUGIN_DYNAMIC_APP_ICON_CHANGER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <optional>

namespace dynamic_app_icon_changer {

class DynamicAppIconChangerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DynamicAppIconChangerPlugin(flutter::PluginRegistrarWindows *registrar);
  virtual ~DynamicAppIconChangerPlugin();

  DynamicAppIconChangerPlugin(const DynamicAppIconChangerPlugin&) = delete;
  DynamicAppIconChangerPlugin& operator=(const DynamicAppIconChangerPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void SetWindowIcon(const std::string& icon_name);
  void ResetWindowIcon();
  std::string GetIconPath(const std::string& icon_name);
  std::string GetPrefsPath();
  void SavePref(const std::string& key, const std::string& value);
  std::optional<std::string> ReadPref(const std::string& key);
  void RemovePref(const std::string& key);
  void CheckSchedule();

  flutter::PluginRegistrarWindows *registrar_;
  HICON original_big_icon_ = nullptr;
  HICON original_small_icon_ = nullptr;
  bool original_icons_saved_ = false;
};

}  // namespace dynamic_app_icon_changer

#endif  // FLUTTER_PLUGIN_DYNAMIC_APP_ICON_CHANGER_PLUGIN_H_
