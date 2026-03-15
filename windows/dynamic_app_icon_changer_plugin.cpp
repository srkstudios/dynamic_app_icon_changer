#include "dynamic_app_icon_changer_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <fstream>
#include <sstream>
#include <filesystem>
#include <map>
#include <chrono>

namespace dynamic_app_icon_changer {

static const char* kActiveIconKey = "active_icon_name";
static const char* kScheduleIconKey = "schedule_icon_name";
static const char* kScheduleStartKey = "schedule_start_millis";
static const char* kScheduleEndKey = "schedule_end_millis";

void DynamicAppIconChangerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "dynamic_app_icon_changer/methods",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<DynamicAppIconChangerPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  // Check schedule on startup
  plugin->CheckSchedule();

  registrar->AddPlugin(std::move(plugin));
}

DynamicAppIconChangerPlugin::DynamicAppIconChangerPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {}

DynamicAppIconChangerPlugin::~DynamicAppIconChangerPlugin() {}

static int64_t NowMillis() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

void DynamicAppIconChangerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  const auto &method = method_call.method_name();

  if (method == "supportsAlternateIcons") {
    result->Success(flutter::EncodableValue(true));

  } else if (method == "getAlternateIconName") {
    auto name = ReadPref(kActiveIconKey);
    if (name.has_value()) {
      result->Success(flutter::EncodableValue(name.value()));
    } else {
      result->Success(flutter::EncodableValue());
    }

  } else if (method == "setAlternateIconName") {
    const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGUMENTS", "Expected a map with 'iconName'.");
      return;
    }

    auto it = args->find(flutter::EncodableValue("iconName"));
    if (it != args->end() && !it->second.IsNull()) {
      auto icon_name = std::get<std::string>(it->second);
      SetWindowIcon(icon_name);
      SavePref(kActiveIconKey, icon_name);
    } else {
      ResetWindowIcon();
      RemovePref(kActiveIconKey);
    }
    result->Success(flutter::EncodableValue());

  } else if (method == "scheduleAlternateIcon") {
    const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGUMENTS", "Expected iconName and endAtMillis.");
      return;
    }

    auto icon_it = args->find(flutter::EncodableValue("iconName"));
    auto end_it = args->find(flutter::EncodableValue("endAtMillis"));
    if (icon_it == args->end() || end_it == args->end()) {
      result->Error("INVALID_ARGUMENTS", "Expected iconName and endAtMillis.");
      return;
    }

    auto icon_name = std::get<std::string>(icon_it->second);
    int64_t end_millis = std::get<int64_t>(end_it->second);
    int64_t start_millis = 0;
    auto start_it = args->find(flutter::EncodableValue("startAtMillis"));
    if (start_it != args->end() && !start_it->second.IsNull()) {
      start_millis = std::get<int64_t>(start_it->second);
    }

    SavePref(kScheduleIconKey, icon_name);
    SavePref(kScheduleStartKey, std::to_string(start_millis));
    SavePref(kScheduleEndKey, std::to_string(end_millis));

    int64_t now = NowMillis();
    if (start_millis == 0 || now >= start_millis) {
      SetWindowIcon(icon_name);
      SavePref(kActiveIconKey, icon_name);
    }

    result->Success(flutter::EncodableValue());

  } else if (method == "cancelScheduledIcon") {
    const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    bool reset_to_default = true;
    if (args) {
      auto it = args->find(flutter::EncodableValue("resetToDefault"));
      if (it != args->end()) {
        reset_to_default = std::get<bool>(it->second);
      }
    }

    RemovePref(kScheduleIconKey);
    RemovePref(kScheduleStartKey);
    RemovePref(kScheduleEndKey);

    if (reset_to_default) {
      ResetWindowIcon();
      RemovePref(kActiveIconKey);
    }

    result->Success(flutter::EncodableValue());

  } else if (method == "getActiveSchedule") {
    CheckSchedule();
    auto icon = ReadPref(kScheduleIconKey);
    if (!icon.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }

    auto end_str = ReadPref(kScheduleEndKey);
    if (!end_str.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }

    int64_t end_millis = std::stoll(end_str.value());
    auto start_str = ReadPref(kScheduleStartKey);
    int64_t start_millis = start_str.has_value() ? std::stoll(start_str.value()) : 0;
    int64_t now = NowMillis();
    bool is_active = (start_millis == 0 || now >= start_millis) && now < end_millis;

    flutter::EncodableMap map;
    map[flutter::EncodableValue("iconName")] = flutter::EncodableValue(icon.value());
    if (start_millis > 0) {
      map[flutter::EncodableValue("startAtMillis")] = flutter::EncodableValue(start_millis);
    } else {
      map[flutter::EncodableValue("startAtMillis")] = flutter::EncodableValue();
    }
    map[flutter::EncodableValue("endAtMillis")] = flutter::EncodableValue(end_millis);
    map[flutter::EncodableValue("isActive")] = flutter::EncodableValue(is_active);

    result->Success(flutter::EncodableValue(map));

  } else if (method == "registerProtectedComponents") {
    result->Success(flutter::EncodableValue());

  } else if (method == "setBadgeNumber") {
    result->Success(flutter::EncodableValue());

  } else if (method == "getBadgeNumber") {
    result->Success(flutter::EncodableValue(0));

  } else {
    result->NotImplemented();
  }
}

void DynamicAppIconChangerPlugin::SetWindowIcon(const std::string& icon_name) {
  HWND hwnd = registrar_->GetView()->GetNativeWindow();
  if (!hwnd) return;

  // Save original icons on first call
  if (!original_icons_saved_) {
    original_big_icon_ = reinterpret_cast<HICON>(
        SendMessage(hwnd, WM_GETICON, ICON_BIG, 0));
    original_small_icon_ = reinterpret_cast<HICON>(
        SendMessage(hwnd, WM_GETICON, ICON_SMALL, 0));
    original_icons_saved_ = true;
  }

  std::string path = GetIconPath(icon_name);
  std::wstring wpath(path.begin(), path.end());

  // Try loading as .ico first, then .png
  HICON icon = static_cast<HICON>(LoadImageW(
      nullptr, wpath.c_str(), IMAGE_ICON, 0, 0,
      LR_LOADFROMFILE | LR_DEFAULTSIZE));

  if (!icon) {
    // Try with .ico extension
    std::wstring ico_path = wpath + L".ico";
    icon = static_cast<HICON>(LoadImageW(
        nullptr, ico_path.c_str(), IMAGE_ICON, 0, 0,
        LR_LOADFROMFILE | LR_DEFAULTSIZE));
  }

  if (icon) {
    SendMessage(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(icon));
    SendMessage(hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(icon));
  }
}

void DynamicAppIconChangerPlugin::ResetWindowIcon() {
  HWND hwnd = registrar_->GetView()->GetNativeWindow();
  if (!hwnd || !original_icons_saved_) return;

  if (original_big_icon_) {
    SendMessage(hwnd, WM_SETICON, ICON_BIG,
                reinterpret_cast<LPARAM>(original_big_icon_));
  }
  if (original_small_icon_) {
    SendMessage(hwnd, WM_SETICON, ICON_SMALL,
                reinterpret_cast<LPARAM>(original_small_icon_));
  }
}

std::string DynamicAppIconChangerPlugin::GetIconPath(const std::string& icon_name) {
  // Get the directory of the running executable
  char exe_path[MAX_PATH];
  GetModuleFileNameA(nullptr, exe_path, MAX_PATH);
  std::filesystem::path exe_dir = std::filesystem::path(exe_path).parent_path();
  // Flutter assets are at <exe_dir>/data/flutter_assets/assets/icons/<name>
  auto icon_path = exe_dir / "data" / "flutter_assets" / "assets" / "icons" / icon_name;
  return icon_path.string();
}

std::string DynamicAppIconChangerPlugin::GetPrefsPath() {
  char app_data[MAX_PATH];
  if (SUCCEEDED(SHGetFolderPathA(nullptr, CSIDL_APPDATA, nullptr, 0, app_data))) {
    auto path = std::filesystem::path(app_data) / "dynamic_app_icon_changer";
    std::filesystem::create_directories(path);
    return (path / "prefs.ini").string();
  }
  return "dic_prefs.ini";
}

void DynamicAppIconChangerPlugin::SavePref(const std::string& key, const std::string& value) {
  // Simple key=value file storage
  auto path = GetPrefsPath();
  std::map<std::string, std::string> prefs;

  // Read existing
  std::ifstream in(path);
  std::string line;
  while (std::getline(in, line)) {
    auto pos = line.find('=');
    if (pos != std::string::npos) {
      prefs[line.substr(0, pos)] = line.substr(pos + 1);
    }
  }
  in.close();

  prefs[key] = value;

  // Write back
  std::ofstream out(path);
  for (const auto& [k, v] : prefs) {
    out << k << "=" << v << "\n";
  }
}

std::optional<std::string> DynamicAppIconChangerPlugin::ReadPref(const std::string& key) {
  auto path = GetPrefsPath();
  std::ifstream in(path);
  std::string line;
  while (std::getline(in, line)) {
    auto pos = line.find('=');
    if (pos != std::string::npos && line.substr(0, pos) == key) {
      return line.substr(pos + 1);
    }
  }
  return std::nullopt;
}

void DynamicAppIconChangerPlugin::RemovePref(const std::string& key) {
  auto path = GetPrefsPath();
  std::map<std::string, std::string> prefs;

  std::ifstream in(path);
  std::string line;
  while (std::getline(in, line)) {
    auto pos = line.find('=');
    if (pos != std::string::npos) {
      auto k = line.substr(0, pos);
      if (k != key) {
        prefs[k] = line.substr(pos + 1);
      }
    }
  }
  in.close();

  std::ofstream out(path);
  for (const auto& [k, v] : prefs) {
    out << k << "=" << v << "\n";
  }
}

void DynamicAppIconChangerPlugin::CheckSchedule() {
  auto icon = ReadPref(kScheduleIconKey);
  if (!icon.has_value()) return;

  auto end_str = ReadPref(kScheduleEndKey);
  if (!end_str.has_value()) return;

  int64_t end_millis = std::stoll(end_str.value());
  auto start_str = ReadPref(kScheduleStartKey);
  int64_t start_millis = start_str.has_value() ? std::stoll(start_str.value()) : 0;
  int64_t now = NowMillis();

  if (now >= end_millis) {
    // Expired
    RemovePref(kScheduleIconKey);
    RemovePref(kScheduleStartKey);
    RemovePref(kScheduleEndKey);
    ResetWindowIcon();
    RemovePref(kActiveIconKey);
    return;
  }

  if (start_millis == 0 || now >= start_millis) {
    auto current = ReadPref(kActiveIconKey);
    if (!current.has_value() || current.value() != icon.value()) {
      SetWindowIcon(icon.value());
      SavePref(kActiveIconKey, icon.value());
    }
  }
}

}  // namespace dynamic_app_icon_changer
