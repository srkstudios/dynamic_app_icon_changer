#ifndef FLUTTER_PLUGIN_DYNAMIC_APP_ICON_CHANGER_PLUGIN_H_
#define FLUTTER_PLUGIN_DYNAMIC_APP_ICON_CHANGER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <filesystem>
#include <memory>
#include <optional>
#include <string>

namespace dynamic_app_icon_changer {

class DynamicAppIconChangerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DynamicAppIconChangerPlugin(flutter::PluginRegistrarWindows *registrar);
  virtual ~DynamicAppIconChangerPlugin();

  DynamicAppIconChangerPlugin(const DynamicAppIconChangerPlugin&) = delete;
  DynamicAppIconChangerPlugin& operator=(const DynamicAppIconChangerPlugin&) = delete;

  // Re-applies any persisted schedule/active icon. Called at registration.
  void RestorePersistedIcon();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND GetWindowHandle();
  void SetWindowIcon(const std::string& icon_name);
  void ResetWindowIcon();
  static std::filesystem::path GetExecutablePath();
  std::wstring GetIconPath(const std::string& icon_name);
  std::filesystem::path GetPrefsPath();
  void SavePref(const std::string& key, const std::string& value);
  std::optional<std::string> ReadPref(const std::string& key);
  void RemovePref(const std::string& key);
  void CheckSchedule();

  flutter::PluginRegistrarWindows *registrar_;
  HICON original_big_icon_ = nullptr;
  HICON original_small_icon_ = nullptr;
  HICON loaded_icon_ = nullptr;
  bool original_icons_saved_ = false;
};

}  // namespace dynamic_app_icon_changer

#endif  // FLUTTER_PLUGIN_DYNAMIC_APP_ICON_CHANGER_PLUGIN_H_
