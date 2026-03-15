# dynamic_app_icon_changer

A Flutter plugin for changing app icons dynamically at runtime on **all 6 platforms** — Android, iOS, macOS, Windows, Linux, and Web — with built-in state recovery that works seamlessly alongside third-party SDKs.

## Features

- Switch app icons at runtime on **all platforms**
- **Scheduled icon changes** with automatic reset (e.g., holiday icons)
- **Relaunch support** — optionally restart the app after icon switch (Android)
- Built-in state recovery on boot, app update, and engine attach (Android)
- Protected Components API to safeguard third-party SDK components (e.g., MoEngage, Firebase)
- OEM blacklist support to skip problematic Android devices
- Badge number support (iOS + macOS dock badge + web title badge)
- Zero manual recovery code needed in consuming apps

## Platform Support

| Feature                | Android | iOS       | macOS      | Windows   | Linux     | Web       |
|------------------------|---------|-----------|------------|-----------|-----------|-----------|
| Alternate icon switch  | API 21+ | iOS 10.3+ | 10.14+     | Win 10+   | GTK 3+    | All       |
| Get current icon name  | API 21+ | iOS 10.3+ | 10.14+     | Win 10+   | GTK 3+    | All       |
| Scheduled icon change  | API 21+ | iOS 10.3+ | 10.14+     | Win 10+   | GTK 3+    | All       |
| Relaunch after switch  | API 21+ | --        | --         | --        | --        | --        |
| Protected components   | API 21+ | --        | --         | --        | --        | --        |
| OEM blacklist          | API 21+ | --        | --         | --        | --        | --        |
| Badge number           | --      | iOS 10.3+ | 10.14+     | --        | --        | Title     |

> **How icons work per platform:**
> - **Android**: Enables/disables `<activity-alias>` entries — changes the launcher icon permanently.
> - **iOS**: Uses `UIApplication.setAlternateIconName` — changes the home screen icon permanently.
> - **macOS**: Sets `NSApplication.applicationIconImage` — changes the Dock icon. Persists via UserDefaults and re-applies on launch.
> - **Windows**: Uses `WM_SETICON` to change the window/taskbar icon. Icons loaded from `assets/icons/` in the Flutter assets directory.
> - **Linux**: Uses `gtk_window_set_icon` to change the window icon. Icons loaded from `assets/icons/` in the Flutter assets directory.
> - **Web**: Dynamically changes the `<link rel="icon">` favicon. Icons served from `web/icons/`.
>
> Desktop and web icon changes are **session-scoped** (revert on app restart) but the plugin persists the choice and re-applies it on next launch.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  dynamic_app_icon_changer: ^0.0.3
```

Then run:

```bash
flutter pub get
```

---

## Android Setup

On Android, dynamic icon switching works by enabling/disabling `<activity-alias>` entries declared in `AndroidManifest.xml`. Each alias represents one icon variant.

### Step 1: Add icon drawables

Place your icon PNG files in the appropriate `mipmap-*` density directories:

```
android/app/src/main/res/
  mipmap-hdpi/
    ic_launcher.png            (default icon, already exists)
    ic_launcher_blue.png
    ic_launcher_green.png
  mipmap-xhdpi/   (same set)
  mipmap-xxhdpi/  (same set)
  mipmap-xxxhdpi/ (same set)
```

### Step 2: Update AndroidManifest.xml

> **Critical:** `MainActivity` must **NOT** have a `LAUNCHER` intent-filter. The launcher entry is handled entirely through `<activity-alias>` entries. This ensures `MainActivity` always remains enabled, preventing the _"Activity class does not exist"_ error.

```xml
<application ...>

    <!--
      MainActivity: NO LAUNCHER intent-filter.
      Always enabled so Flutter/adb can start it directly.
    -->
    <activity
        android:name=".MainActivity"
        android:exported="true"
        android:launchMode="singleTask"
        android:theme="@style/LaunchTheme"
        android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
        android:hardwareAccelerated="true"
        android:windowSoftInputMode="adjustResize">
        <meta-data
            android:name="io.flutter.embedding.android.NormalTheme"
            android:resource="@style/NormalTheme" />
    </activity>

    <!--
      DEFAULT icon alias: android:enabled="true"
      The plugin identifies this as the default because enabled="true".
    -->
    <activity-alias
        android:name=".DefaultIcon"
        android:enabled="true"
        android:exported="true"
        android:icon="@mipmap/ic_launcher"
        android:label="My App"
        android:targetActivity=".MainActivity">
        <intent-filter>
            <action android:name="android.intent.action.MAIN"/>
            <category android:name="android.intent.category.LAUNCHER"/>
        </intent-filter>
    </activity-alias>

    <!--
      ALTERNATE icon aliases: android:enabled="false"
      Add one block per alternate icon.
    -->
    <activity-alias
        android:name=".IconBlue"
        android:enabled="false"
        android:exported="true"
        android:icon="@mipmap/ic_launcher_blue"
        android:label="My App"
        android:targetActivity=".MainActivity">
        <intent-filter>
            <action android:name="android.intent.action.MAIN"/>
            <category android:name="android.intent.category.LAUNCHER"/>
        </intent-filter>
    </activity-alias>

    <activity-alias
        android:name=".IconGreen"
        android:enabled="false"
        android:exported="true"
        android:icon="@mipmap/ic_launcher_green"
        android:label="My App"
        android:targetActivity=".MainActivity">
        <intent-filter>
            <action android:name="android.intent.action.MAIN"/>
            <category android:name="android.intent.category.LAUNCHER"/>
        </intent-filter>
    </activity-alias>

</application>
```

### Manifest Rules

All five rules must be followed or the plugin will not work correctly:

| Rule | What breaks if you skip it |
|------|---------------------------|
| `MainActivity` has **no** `LAUNCHER` intent-filter | `flutter run` / `adb am start .MainActivity` fails after any icon switch |
| `MainActivity` uses `launchMode="singleTask"` | Tapping the new icon creates a new app instance instead of resuming |
| `MainActivity` has **no** `taskAffinity=""` | Same new-instance problem — aliases can't find the existing task |
| Default alias has `android:enabled="true"` | Plugin can't identify or restore the default icon |
| All other aliases have `android:enabled="false"` | Multiple launcher icons appear simultaneously |

> **Why `singleTask` instead of Flutter's default `singleTop`?**
>
> Activity-aliases inherit both `launchMode` and `taskAffinity` from their `targetActivity`. With `singleTask`, when any alias is tapped Android searches for an existing task whose affinity matches the package name (the default), finds the running app, and brings it to the foreground. Flutter's default (`singleTop` + `taskAffinity=""`) is **incompatible** with dynamic icons because aliases with no affinity always spawn a new task.

---

## iOS Setup

On iOS, dynamic icon switching uses `UIApplication.setAlternateIconName` (iOS 10.3+).

### Step 1: Add icon files

Place your alternate icon PNG files in the Runner directory (or a subfolder):

- `IconBlue@2x.png` (120x120)
- `IconBlue@3x.png` (180x180)
- `IconGreen@2x.png` (120x120)
- `IconGreen@3x.png` (180x180)

### Step 2: Configure Info.plist

In `ios/Runner/Info.plist`, add the `CFBundleIcons` dictionary:

```xml
<key>CFBundleIcons</key>
<dict>
    <key>CFBundleAlternateIcons</key>
    <dict>
        <key>IconBlue</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>IconBlue</string>
            </array>
            <key>UIPrerenderedIcon</key>
            <false/>
        </dict>
        <key>IconGreen</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>IconGreen</string>
            </array>
            <key>UIPrerenderedIcon</key>
            <false/>
        </dict>
    </dict>
</dict>
```

### Step 3: Include files in Xcode

1. Open `ios/Runner.xcworkspace` in Xcode
2. Right-click the Runner folder > "Add Files to Runner..."
3. Select your icon PNG files (check "Copy items if needed")
4. Verify they appear in **Build Phases > Copy Bundle Resources**

---

## macOS Setup

macOS uses `NSApplication.applicationIconImage` to change the Dock icon at runtime.

### Option A: Asset Catalog (recommended)

1. Open `macos/Runner.xcworkspace` in Xcode
2. In `Assets.xcassets`, create new Image Sets named `IconBlue`, `IconGreen`, etc.
3. Add the icon images to each set

### Option B: Loose files

Place PNG or ICNS files directly in `macos/Runner/`:
- `IconBlue.png`
- `IconGreen.icns`

The plugin searches for the icon by name using `NSImage(named:)` and falls back to loading from the app bundle and Flutter assets.

---

## Windows / Linux Setup

On Windows and Linux, the plugin changes the **window icon** (taskbar/title bar) at runtime.

### Step 1: Add icon files to Flutter assets

Place your icon files in your project's assets directory:

```
assets/
  icons/
    IconBlue.ico       (Windows: .ico preferred)
    IconBlue.png       (Linux: .png preferred)
    IconGreen.ico
    IconGreen.png
```

### Step 2: Register assets in pubspec.yaml

```yaml
flutter:
  assets:
    - assets/icons/
```

The plugin resolves icons from `<exe_dir>/data/flutter_assets/assets/icons/<iconName>`.

---

## Web Setup

On the web, the plugin changes the **favicon** dynamically.

### Step 1: Add icon files

Place your icon PNG files in the `web/icons/` directory:

```
web/
  icons/
    IconBlue.png
    IconGreen.png
  favicon.png          (default favicon)
```

### Step 2: Ensure default favicon exists

The plugin resets to `favicon.png` when reverting to the default icon. Make sure this file exists in your `web/` directory.

---

## Usage

### Import

```dart
import 'package:dynamic_app_icon_changer/dynamic_app_icon_changer.dart';
```

### Check support

```dart
final isSupported = await DynamicAppIconChanger.supportsAlternateIcons;
```

### Get current icon

```dart
final iconName = await DynamicAppIconChanger.alternateIconName;
// Returns null when the default icon is active.
```

### Switch icon

```dart
// Switch to an alternate icon
await DynamicAppIconChanger.setAlternateIconName('IconBlue');

// Restore the default icon
await DynamicAppIconChanger.setAlternateIconName(null);
```

### Relaunch after icon switch (Android only)

By default, the launcher may take a few seconds to reflect the new icon. Pass `relaunch: true` to kill and restart the app immediately so the change is visible right away:

```dart
await DynamicAppIconChanger.setAlternateIconName(
  'IconBlue',
  relaunch: true, // App restarts after ~500ms
);
```

> **Note:** This finishes the current activity and relaunches via `AlarmManager`. The user will briefly see the app close and reopen. On iOS this parameter is ignored.

### OEM blacklist (Android only)

Silently skip icon changes on devices known to have issues:

```dart
await DynamicAppIconChanger.setAlternateIconName(
  'IconBlue',
  blacklistedBrands: ['Samsung', 'Xiaomi'],
);
```

### Badge number (iOS only)

```dart
await DynamicAppIconChanger.setBadgeNumber(5);
await DynamicAppIconChanger.setBadgeNumber(0); // clear
final badge = await DynamicAppIconChanger.badgeNumber;
```

---

## Scheduled Icon Changes

Schedule an icon to be active during a specific time window, then automatically reset to the default icon when the window ends. Perfect for seasonal/holiday icons, events, or time-limited promotions.

### Schedule an icon

```dart
// Christmas icon: Dec 20 to Dec 26
await DynamicAppIconChanger.scheduleAlternateIcon(
  'IconChristmas',
  startAt: DateTime(2026, 12, 20),
  endAt: DateTime(2026, 12, 26, 23, 59, 59),
);

// Start immediately, reset after 24 hours
await DynamicAppIconChanger.scheduleAlternateIcon(
  'IconPromo',
  endAt: DateTime.now().add(Duration(hours: 24)),
);
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `iconName` | Yes | The alias name to activate |
| `endAt` | Yes | When to reset back to the default icon |
| `startAt` | No | When to activate the icon. If `null` or in the past, activates immediately |
| `blacklistedBrands` | No | Same as `setAlternateIconName` |

### Check active schedule

```dart
final schedule = await DynamicAppIconChanger.activeSchedule;
if (schedule != null) {
  print('Icon: ${schedule.iconName}');
  print('Active: ${schedule.isActive}');
  print('Ends: ${schedule.endAt}');
}
```

### Cancel a schedule

```dart
// Cancel and reset to default
await DynamicAppIconChanger.cancelScheduledIcon();

// Cancel but keep the current icon
await DynamicAppIconChanger.cancelScheduledIcon(resetToDefault: false);
```

### How scheduling works

| Platform | Mechanism | Reliability |
|----------|-----------|-------------|
| **Android** | `AlarmManager` with `setExactAndAllowWhileIdle` | Fires in background even if app is killed. Alarms are re-registered on reboot via `BOOT_COMPLETED` receiver. |
| **iOS** | `UserDefaults` + `willEnterForegroundNotification` | Schedule is checked every time the app enters the foreground. If the app isn't opened after `endAt`, the reset happens on the next launch. |

**Schedule lifecycle:**
1. `scheduleAlternateIcon()` is called
2. If `startAt` is now/past → icon changes immediately. If future → alarm is set.
3. `AlarmManager` fires `ACTION_SCHEDULE_START` → icon changes (Android)
4. `AlarmManager` fires `ACTION_SCHEDULE_END` → icon resets to default
5. On reboot → `IconStateRecoveryReceiver` re-registers alarms and checks for expired schedules
6. On app update → recovery runs + default alias re-enabled for `flutter run`

Only one schedule can be active at a time. Calling `scheduleAlternateIcon()` again replaces any existing schedule.

---

## Protected Components (Android)

### The Problem

When the plugin toggles activity-alias states to change the launcher icon, Android's `PackageManager` can inadvertently disrupt the enabled state of other components declared in the manifest. This breaks third-party SDK features like:

- **MoEngage PushTracker** — notification taps stop opening the app
- **Firebase messaging components** — push notifications fail
- **Legacy activity-aliases** — leftover aliases from previous builds get re-enabled

Previously, apps had to write manual recovery classes with `BroadcastReceiver` to fix this on every boot and app update. **This plugin handles it automatically.**

### The Solution

Register components that need protection, and the plugin ensures they stay in the correct state:

```dart
await DynamicAppIconChanger.registerProtectedComponents([
  // Keep MoEngage PushTracker always enabled
  const ProtectedComponent(
    className: 'com.moengage.pushbase.activities.PushTracker',
    desiredState: ComponentState.enabled,
  ),
  // Keep a legacy alias always disabled
  const ProtectedComponent(
    className: '.momTurnsOne',
    desiredState: ComponentState.disabled,
  ),
]);
```

Call this once at app startup (e.g., in your `main()` or root widget's `initState`). The plugin persists the configuration and enforces it:

| Trigger | What happens |
|---------|-------------|
| Every icon switch | Protected components are restored immediately after alias toggle |
| Device reboot | `IconStateRecoveryReceiver` restores all states (auto-registered via manifest merger) |
| App update | Same receiver triggers on `MY_PACKAGE_REPLACED` |
| Flutter engine attach | Recovery runs as a safety net on every app launch |

### ComponentState values

| Value | Effect |
|-------|--------|
| `ComponentState.enabled` | Explicitly enable the component |
| `ComponentState.disabled` | Explicitly disable the component |
| `ComponentState.defaultState` | Respect the manifest's declared value |

This is **Android-only** — all other platforms ignore this call.

---

## How Recovery Works

The plugin includes a multi-layered recovery system that runs automatically:

1. **After every icon switch** — re-enables `MainActivity`, restores protected components
2. **On Flutter engine attach** — runs a full state reconciliation from persisted SharedPreferences, checks active schedules
3. **On `BOOT_COMPLETED`** — `IconStateRecoveryReceiver` restores alias states + protected components, re-registers schedule alarms (lost on reboot), checks for expired schedules
4. **On `MY_PACKAGE_REPLACED`** — same receiver handles app updates + re-enables default alias for `flutter run` compatibility

The recovery receiver has **zero Flutter dependencies** and runs before the Flutter engine starts. No manual manifest changes or receiver registration needed in consuming apps.

---

## Error Handling

The plugin throws `DynamicIconException` on failures:

```dart
try {
  await DynamicAppIconChanger.setAlternateIconName('IconBlue');
} on DynamicIconException catch (e) {
  print('Error: ${e.message}');  // Human-readable message
  print('Code: ${e.code}');      // Machine-readable code (e.g., ICON_NOT_FOUND)
}
```

### Error codes

| Code | Meaning |
|------|---------|
| `NO_ALIASES_FOUND` | No `<activity-alias>` entries with `MAIN+LAUNCHER` in manifest |
| `ICON_NOT_FOUND` | The requested alias name doesn't exist in the manifest |
| `ICON_CHANGE_FAILED` | An exception occurred during the component state change |
| `INVALID_ARGUMENTS` | Invalid arguments passed to a method |
| `INVALID_SCHEDULE` | `endAt` is in the past, or `endAt` is before `startAt` |
| `SCHEDULE_FAILED` | An exception occurred while setting up the schedule |
| `CANCEL_SCHEDULE_FAILED` | An exception occurred while cancelling the schedule |

---

## Troubleshooting

### "Activity class does not exist" when running `flutter run`

After switching icons, `flutter run` fails with:
```
Error: Activity class {com.example.app/com.example.app.MainActivity} does not exist.
```

**Fix:** `MainActivity` must have **no LAUNCHER intent-filter** and must never be disabled. Follow the manifest setup above. The plugin automatically re-enables the default alias on `MY_PACKAGE_REPLACED` (triggered by every `flutter run` install) to prevent this error.

If you're already in this state, re-enable it manually:

```bash
adb shell pm enable com.your.package/.MainActivity
```

### Tapping the new icon opens a second copy of the app

**Fix:** Change `MainActivity` to use `launchMode="singleTask"` and remove `taskAffinity=""`. See the [Manifest Rules](#manifest-rules) section.

### Icon doesn't change on Android

1. Verify default alias has `enabled="true"`, alternates have `enabled="false"`
2. Ensure `MainActivity` has no LAUNCHER intent-filter
3. Ensure the alias `android:name` (without the dot) matches what you pass to `setAlternateIconName()`
4. Some launchers cache aggressively — try restarting the launcher or rebooting

### Icon doesn't change on iOS

1. Confirm icon files are listed in `Info.plist` under `CFBundleIcons > CFBundleAlternateIcons`
2. Ensure PNG files are included in Xcode's **Copy Bundle Resources**
3. The icon name must exactly match the string passed to `setAlternateIconName()`

### Scheduled icon didn't reset on iOS

The iOS schedule check runs on foreground entry. If the app isn't opened after the `endAt` time, the reset happens on the next launch. Background execution is not guaranteed on iOS.

### Notifications stop working after icon switch (Android)

Third-party notification components (e.g., MoEngage PushTracker) can get disrupted by alias state changes. **Use `registerProtectedComponents()`** to keep them in the correct state. See [Protected Components](#protected-components-android).

---

## Notes and Caveats

- **iOS system alert:** iOS always shows a confirmation dialog when changing icons. This cannot be suppressed.
- **Android launcher delay:** The launcher may take a few seconds to reflect the new icon. Use `relaunch: true` to force an immediate restart.
- **Pre-bundled icons only:** You cannot download and set arbitrary icons at runtime. All icons must be included in the app bundle at build time.
- **Android OEM quirks:** Some OEM launchers may not reflect the change correctly. Use `blacklistedBrands` to skip problematic devices.
- **Badge numbers:** Only supported on iOS. On Android, `setBadgeNumber` is a no-op and `badgeNumber` always returns 0.
- **BOOT_COMPLETED permission:** The plugin's manifest declares `RECEIVE_BOOT_COMPLETED` for the recovery receiver. This merges automatically into your app.
- **Exact alarm permission (Android 12+):** For precise schedule timing, the app should have the `SCHEDULE_EXACT_ALARM` permission. If not granted, the plugin falls back to inexact alarms which may have a few minutes of delay.
- **One schedule at a time:** Calling `scheduleAlternateIcon()` replaces any existing schedule.

---

## License

See [LICENSE](LICENSE) for details.
