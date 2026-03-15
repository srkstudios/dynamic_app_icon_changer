## 0.0.3

* **Scheduled icon changes**: New `scheduleAlternateIcon()` API lets you set an
  icon with a start time and end time — the icon automatically resets to default
  when the schedule expires.
  * Android: Uses `AlarmManager` with `setExactAndAllowWhileIdle` for reliable
    background triggers. Schedules survive reboots (alarms are re-registered on
    `BOOT_COMPLETED`) and app updates.
  * iOS: Persists schedule in `UserDefaults` and checks on every foreground entry
    via `willEnterForegroundNotification`.
* **Schedule management**: Added `cancelScheduledIcon()` and `activeSchedule`
  getter to inspect or cancel running schedules.
* **Relaunch support** (Android-only): `setAlternateIconName()` now accepts an
  optional `relaunch` parameter. When `true`, the app is killed and relaunched
  via `AlarmManager` after ~500ms so the launcher immediately reflects the new icon.
* New `ScheduleInfo` model class for inspecting schedule state from Dart.
* New `ScheduledIconReceiver` broadcast receiver for handling `AlarmManager`
  callbacks on Android.
* Boot recovery now re-registers schedule alarms (lost on reboot) and checks for
  expired schedules.
* Plugin now implements `ActivityAware` on Android to support relaunch.
* Added 10 new integration tests covering schedule and relaunch features.

## 0.0.2

* Added MIT License and verified package publishing requirements.

## 0.0.1

* Initial release of `dynamic_app_icon_changer` (renamed from `dynamic_app_icon`).
* **Android**: Activity-alias + `PackageManager` based icon switching.
  * OEM blacklist support (`blacklistedBrands`).
  * Automatic state recovery on boot / app-update via `IconStateRecoveryReceiver`.
  * `MainActivity` safety-net: explicitly re-enabled after every alias toggle.
  * Protected Components API: register third-party components (e.g., push trackers)
    that should be restored to a specific enabled state after every icon change.
* **iOS**: `UIApplication.setAlternateIconName` based icon switching.
* Badge number support (`setBadgeNumber` / `getBadgeNumber`).
