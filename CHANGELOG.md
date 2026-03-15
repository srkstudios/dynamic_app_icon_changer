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
