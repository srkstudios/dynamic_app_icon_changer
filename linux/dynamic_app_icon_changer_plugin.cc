#include "include/dynamic_app_icon_changer/dynamic_app_icon_changer_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>
#include <fstream>
#include <map>
#include <string>
#include <chrono>
#include <sstream>
#include <filesystem>

#define DYNAMIC_APP_ICON_CHANGER_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), dynamic_app_icon_changer_plugin_get_type(), \
                              DynamicAppIconChangerPlugin))

struct _DynamicAppIconChangerPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
};

G_DEFINE_TYPE(DynamicAppIconChangerPlugin, dynamic_app_icon_changer_plugin,
              g_object_get_type())

// ── Preferences helpers ──────────────────────────────────────────────

static const char* kActiveIconKey = "active_icon_name";
static const char* kScheduleIconKey = "schedule_icon_name";
static const char* kScheduleStartKey = "schedule_start_millis";
static const char* kScheduleEndKey = "schedule_end_millis";

static std::string get_prefs_path() {
  const char* home = g_get_home_dir();
  auto path = std::filesystem::path(home) / ".config" / "dynamic_app_icon_changer";
  std::filesystem::create_directories(path);
  return (path / "prefs.ini").string();
}

static std::map<std::string, std::string> read_all_prefs() {
  std::map<std::string, std::string> prefs;
  std::ifstream in(get_prefs_path());
  std::string line;
  while (std::getline(in, line)) {
    auto pos = line.find('=');
    if (pos != std::string::npos) {
      prefs[line.substr(0, pos)] = line.substr(pos + 1);
    }
  }
  return prefs;
}

static void write_all_prefs(const std::map<std::string, std::string>& prefs) {
  std::ofstream out(get_prefs_path());
  for (const auto& [k, v] : prefs) {
    out << k << "=" << v << "\n";
  }
}

static void save_pref(const char* key, const std::string& value) {
  auto prefs = read_all_prefs();
  prefs[key] = value;
  write_all_prefs(prefs);
}

static std::string read_pref(const char* key) {
  auto prefs = read_all_prefs();
  auto it = prefs.find(key);
  return it != prefs.end() ? it->second : "";
}

static void remove_pref(const char* key) {
  auto prefs = read_all_prefs();
  prefs.erase(key);
  write_all_prefs(prefs);
}

static int64_t now_millis() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

// ── Icon helpers ─────────────────────────────────────────────────────

static std::string get_icon_path(const std::string& icon_name) {
  // Get the directory of the running executable
  char exe_path[PATH_MAX];
  ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
  if (len == -1) return "";
  exe_path[len] = '\0';
  auto exe_dir = std::filesystem::path(exe_path).parent_path();
  auto icon_path = exe_dir / "data" / "flutter_assets" / "assets" / "icons" / icon_name;
  return icon_path.string();
}

static GtkWindow* get_gtk_window(FlPluginRegistrar* registrar) {
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (!view) return nullptr;
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (GTK_IS_WINDOW(toplevel)) {
    return GTK_WINDOW(toplevel);
  }
  return nullptr;
}

static void set_window_icon(FlPluginRegistrar* registrar, const std::string& icon_name) {
  GtkWindow* window = get_gtk_window(registrar);
  if (!window) return;

  std::string path = get_icon_path(icon_name);

  // Try with common extensions
  for (const char* ext : {".png", ".ico", ".svg", ""}) {
    std::string full_path = path + ext;
    if (std::filesystem::exists(full_path)) {
      GError* error = nullptr;
      GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file(full_path.c_str(), &error);
      if (pixbuf) {
        gtk_window_set_icon(window, pixbuf);
        g_object_unref(pixbuf);
        return;
      }
      if (error) g_error_free(error);
    }
  }
}

static void reset_window_icon(FlPluginRegistrar* registrar) {
  GtkWindow* window = get_gtk_window(registrar);
  if (!window) return;
  gtk_window_set_icon(window, nullptr);
}

static void check_schedule(FlPluginRegistrar* registrar) {
  std::string icon = read_pref(kScheduleIconKey);
  if (icon.empty()) return;

  std::string end_str = read_pref(kScheduleEndKey);
  if (end_str.empty()) return;

  int64_t end_millis = std::stoll(end_str);
  std::string start_str = read_pref(kScheduleStartKey);
  int64_t start_millis = start_str.empty() ? 0 : std::stoll(start_str);
  int64_t now = now_millis();

  if (now >= end_millis) {
    remove_pref(kScheduleIconKey);
    remove_pref(kScheduleStartKey);
    remove_pref(kScheduleEndKey);
    reset_window_icon(registrar);
    remove_pref(kActiveIconKey);
    return;
  }

  if (start_millis == 0 || now >= start_millis) {
    std::string current = read_pref(kActiveIconKey);
    if (current != icon) {
      set_window_icon(registrar, icon);
      save_pref(kActiveIconKey, icon);
    }
  }
}

// ── Method call handler ──────────────────────────────────────────────

static void method_call_handler(FlMethodChannel* channel, FlMethodCall* method_call,
                                gpointer user_data) {
  DynamicAppIconChangerPlugin* self = DYNAMIC_APP_ICON_CHANGER_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "supportsAlternateIcons") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "getAlternateIconName") == 0) {
    std::string name = read_pref(kActiveIconKey);
    if (name.empty()) {
      g_autoptr(FlValue) result = fl_value_new_null();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
      g_autoptr(FlValue) result = fl_value_new_string(name.c_str());
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }

  } else if (strcmp(method, "setAlternateIconName") == 0) {
    FlValue* icon_val = fl_value_lookup_string(args, "iconName");
    if (icon_val && fl_value_get_type(icon_val) == FL_VALUE_TYPE_STRING) {
      std::string icon_name = fl_value_get_string(icon_val);
      set_window_icon(self->registrar, icon_name);
      save_pref(kActiveIconKey, icon_name);
    } else {
      reset_window_icon(self->registrar);
      remove_pref(kActiveIconKey);
    }
    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "scheduleAlternateIcon") == 0) {
    FlValue* icon_val = fl_value_lookup_string(args, "iconName");
    FlValue* end_val = fl_value_lookup_string(args, "endAtMillis");

    if (!icon_val || !end_val) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGUMENTS", "Expected iconName and endAtMillis.", nullptr));
    } else {
      std::string icon_name = fl_value_get_string(icon_val);
      int64_t end_millis = fl_value_get_int(end_val);
      int64_t start_millis = 0;
      FlValue* start_val = fl_value_lookup_string(args, "startAtMillis");
      if (start_val && fl_value_get_type(start_val) == FL_VALUE_TYPE_INT) {
        start_millis = fl_value_get_int(start_val);
      }

      save_pref(kScheduleIconKey, icon_name);
      save_pref(kScheduleStartKey, std::to_string(start_millis));
      save_pref(kScheduleEndKey, std::to_string(end_millis));

      int64_t now = now_millis();
      if (start_millis == 0 || now >= start_millis) {
        set_window_icon(self->registrar, icon_name);
        save_pref(kActiveIconKey, icon_name);
      }

      g_autoptr(FlValue) result = fl_value_new_null();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }

  } else if (strcmp(method, "cancelScheduledIcon") == 0) {
    gboolean reset_to_default = TRUE;
    FlValue* reset_val = fl_value_lookup_string(args, "resetToDefault");
    if (reset_val && fl_value_get_type(reset_val) == FL_VALUE_TYPE_BOOL) {
      reset_to_default = fl_value_get_bool(reset_val);
    }

    remove_pref(kScheduleIconKey);
    remove_pref(kScheduleStartKey);
    remove_pref(kScheduleEndKey);

    if (reset_to_default) {
      reset_window_icon(self->registrar);
      remove_pref(kActiveIconKey);
    }

    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "getActiveSchedule") == 0) {
    check_schedule(self->registrar);
    std::string icon = read_pref(kScheduleIconKey);
    if (icon.empty()) {
      g_autoptr(FlValue) result = fl_value_new_null();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
      std::string end_str = read_pref(kScheduleEndKey);
      if (end_str.empty()) {
        g_autoptr(FlValue) result = fl_value_new_null();
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
      } else {
        int64_t end_millis = std::stoll(end_str);
        std::string start_str = read_pref(kScheduleStartKey);
        int64_t start_millis = start_str.empty() ? 0 : std::stoll(start_str);
        int64_t now = now_millis();
        gboolean is_active = (start_millis == 0 || now >= start_millis) && now < end_millis;

        g_autoptr(FlValue) result = fl_value_new_map();
        fl_value_set_string_take(result, "iconName",
            fl_value_new_string(icon.c_str()));
        if (start_millis > 0) {
          fl_value_set_string_take(result, "startAtMillis",
              fl_value_new_int(start_millis));
        } else {
          fl_value_set_string_take(result, "startAtMillis",
              fl_value_new_null());
        }
        fl_value_set_string_take(result, "endAtMillis",
            fl_value_new_int(end_millis));
        fl_value_set_string_take(result, "isActive",
            fl_value_new_bool(is_active));

        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
      }
    }

  } else if (strcmp(method, "registerProtectedComponents") == 0 ||
             strcmp(method, "setBadgeNumber") == 0) {
    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "getBadgeNumber") == 0) {
    g_autoptr(FlValue) result = fl_value_new_int(0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// ── Plugin lifecycle ─────────────────────────────────────────────────

static void dynamic_app_icon_changer_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(dynamic_app_icon_changer_plugin_parent_class)->dispose(object);
}

static void dynamic_app_icon_changer_plugin_class_init(
    DynamicAppIconChangerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = dynamic_app_icon_changer_plugin_dispose;
}

static void dynamic_app_icon_changer_plugin_init(DynamicAppIconChangerPlugin* self) {}

void dynamic_app_icon_changer_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  DynamicAppIconChangerPlugin* plugin = DYNAMIC_APP_ICON_CHANGER_PLUGIN(
      g_object_new(dynamic_app_icon_changer_plugin_get_type(), nullptr));
  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "dynamic_app_icon_changer/methods",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_handler, g_object_ref(plugin), g_object_unref);

  // Check schedule on startup
  check_schedule(registrar);

  g_object_unref(plugin);
}
