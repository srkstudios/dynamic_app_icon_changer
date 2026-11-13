#include "dynamic_app_icon_changer_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shlobj.h>

#include <fstream>
#include <sstream>
#include <filesystem>
#include <map>
#include <chrono>
#include <functional>

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

  // Check schedule and restore the persisted icon on startup.
  plugin->RestorePersistedIcon();

  registrar->AddPlugin(std::move(plugin));
}

DynamicAppIconChangerPlugin::DynamicAppIconChangerPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {}

DynamicAppIconChangerPlugin::~DynamicAppIconChangerPlugin() {
  if (loaded_icon_) {
    DestroyIcon(loaded_icon_);
    loaded_icon_ = nullptr;
  }
}

static int64_t NowMillis() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

static int64_t ParseMillis(const std::string& value) {
  try {
    return std::stoll(value);
  } catch (...) {
    return 0;
  }
}

// Extracts an integer argument that the standard codec may have encoded as
// either int32 or int64 depending on magnitude.
static std::optional<int64_t> GetInt64Arg(const flutter::EncodableMap& args,
                                          const char* key) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end() || it->second.IsNull()) return std::nullopt;
  if (const auto* v64 = std::get_if<int64_t>(&it->second)) return *v64;
  if (const auto* v32 = std::get_if<int32_t>(&it->second)) {
    return static_cast<int64_t>(*v32);
  }
  return std::nullopt;
}

static std::optional<std::string> GetStringArg(const flutter::EncodableMap& args,
                                               const char* key) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end() || it->second.IsNull()) return std::nullopt;
  if (const auto* str = std::get_if<std::string>(&it->second)) return *str;
  return std::nullopt;
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

    auto icon_name = GetStringArg(*args, "iconName");
    if (icon_name.has_value()) {
      SetWindowIcon(icon_name.value());
      SavePref(kActiveIconKey, icon_name.value());
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

    auto icon_name = GetStringArg(*args, "iconName");
    auto end_millis = GetInt64Arg(*args, "endAtMillis");
    if (!icon_name.has_value() || !end_millis.has_value()) {
      result->Error("INVALID_ARGUMENTS", "Expected iconName and endAtMillis.");
      return;
    }

    int64_t start_millis = GetInt64Arg(*args, "startAtMillis").value_or(0);

    SavePref(kScheduleIconKey, icon_name.value());
    SavePref(kScheduleStartKey, std::to_string(start_millis));
    SavePref(kScheduleEndKey, std::to_string(end_millis.value()));

    int64_t now = NowMillis();
    if (start_millis == 0 || now >= start_millis) {
      SetWindowIcon(icon_name.value());
      SavePref(kActiveIconKey, icon_name.value());
    }

    result->Success(flutter::EncodableValue());

  } else if (method == "cancelScheduledIcon") {
    const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    bool reset_to_default = true;
    if (args) {
      auto it = args->find(flutter::EncodableValue("resetToDefault"));
      if (it != args->end()) {
        if (const auto* b = std::get_if<bool>(&it->second)) {
          reset_to_default = *b;
        }
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

    int64_t end_millis = ParseMillis(end_str.value());
    auto start_str = ReadPref(kScheduleStartKey);
    int64_t start_millis = start_str.has_value() ? ParseMillis(start_str.value()) : 0;
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

HWND DynamicAppIconChangerPlugin::GetWindowHandle() {
  // The view can be null during early startup or in headless engines.
  flutter::FlutterView* view = registrar_->GetView();
  if (!view) return nullptr;
  return view->GetNativeWindow();
}

void DynamicAppIconChangerPlugin::SetWindowIcon(const std::string& icon_name) {
  HWND hwnd = GetWindowHandle();
  if (!hwnd) return;

  // Save original icons on first call
  if (!original_icons_saved_) {
    original_big_icon_ = reinterpret_cast<HICON>(
        SendMessage(hwnd, WM_GETICON, ICON_BIG, 0));
    original_small_icon_ = reinterpret_cast<HICON>(
        SendMessage(hwnd, WM_GETICON, ICON_SMALL, 0));
    original_icons_saved_ = true;
  }

  std::wstring wpath = GetIconPath(icon_name);

  // LoadImage(IMAGE_ICON) only supports .ico files. Try the bare path first
  // (in case the caller included the extension), then with ".ico" appended.
  HICON icon = static_cast<HICON>(LoadImageW(
      nullptr, wpath.c_str(), IMAGE_ICON, 0, 0,
      LR_LOADFROMFILE | LR_DEFAULTSIZE));

  if (!icon) {
    std::wstring ico_path = wpath + L".ico";
    icon = static_cast<HICON>(LoadImageW(
        nullptr, ico_path.c_str(), IMAGE_ICON, 0, 0,
        LR_LOADFROMFILE | LR_DEFAULTSIZE));
  }

  if (icon) {
    SendMessage(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(icon));
    SendMessage(hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(icon));
    if (loaded_icon_) {
      DestroyIcon(loaded_icon_);
    }
    loaded_icon_ = icon;
  }
}

void DynamicAppIconChangerPlugin::ResetWindowIcon() {
  HWND hwnd = GetWindowHandle();
  if (!hwnd || !original_icons_saved_) return;

  SendMessage(hwnd, WM_SETICON, ICON_BIG,
              reinterpret_cast<LPARAM>(original_big_icon_));
  SendMessage(hwnd, WM_SETICON, ICON_SMALL,
              reinterpret_cast<LPARAM>(original_small_icon_));

  if (loaded_icon_) {
    DestroyIcon(loaded_icon_);
    loaded_icon_ = nullptr;
  }
}

std::filesystem::path DynamicAppIconChangerPlugin::GetExecutablePath() {
  wchar_t exe_path[MAX_PATH];
  GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  return std::filesystem::path(exe_path);
}

std::wstring DynamicAppIconChangerPlugin::GetIconPath(const std::string& icon_name) {
  std::filesystem::path exe_dir = GetExecutablePath().parent_path();
  // Flutter assets are at <exe_dir>/data/flutter_assets/assets/icons/<name>
  auto icon_path = exe_dir / "data" / "flutter_assets" / "assets" / "icons" /
                   std::filesystem::u8path(icon_name);
  return icon_path.wstring();
}

std::filesystem::path DynamicAppIconChangerPlugin::GetPrefsPath() {
  auto exe_path = GetExecutablePath();
  // Namespace the prefs per executable so different apps that use this
  // plugin do not read or clobber each other's state.
  std::wstring app_id = exe_path.stem().wstring() + L"_" +
      std::to_wstring(std::hash<std::wstring>{}(exe_path.wstring()));

  wchar_t app_data[MAX_PATH];
  if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, app_data))) {
    auto path = std::filesystem::path(app_data) / L"dynamic_app_icon_changer" / app_id;
    std::error_code ec;
    std::filesystem::create_directories(path, ec);
    return path / L"prefs.ini";
  }
  return std::filesystem::path(L"dic_prefs.ini");
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

  int64_t end_millis = ParseMillis(end_str.value());
  auto start_str = ReadPref(kScheduleStartKey);
  int64_t start_millis = start_str.has_value() ? ParseMillis(start_str.value()) : 0;
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

void DynamicAppIconChangerPlugin::RestorePersistedIcon() {
  CheckSchedule();
  // Window icons do not survive process restarts, so re-apply whatever
  // icon is recorded as active (set directly or via a schedule).
  auto active = ReadPref(kActiveIconKey);
  if (active.has_value()) {
    SetWindowIcon(active.value());
  }
}

}  // namespace dynamic_app_icon_changer
