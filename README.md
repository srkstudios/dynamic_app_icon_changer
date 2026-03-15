# dynamic_app_icon_changer

A Flutter plugin for changing app icons dynamically at runtime on Android and iOS, with built-in state recovery that works seamlessly alongside third-party SDKs.

## Features

- Switch app launcher icons at runtime on both Android and iOS
- Built-in state recovery on boot, app update, and engine attach
- Protected Components API to safeguard third-party SDK components (e.g., MoEngage, Firebase) during icon switches
- OEM blacklist support to skip problematic Android devices
- Badge number support on iOS
- Zero manual recovery code needed in consuming apps

## Platform Support

| Feature                | Android | iOS       |
|------------------------|---------|-----------|
| Alternate icon switch  | API 21+ | iOS 10.3+ |
| Get current icon name  | API 21+ | iOS 10.3+ |
| Protected components   | API 21+ | --        |
| OEM blacklist          | API 21+ | --        |
| Badge number           | --      | iOS 10.3+ |

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  dynamic_app_icon_changer: ^0.0.1
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

This is a **no-op on iOS** — iOS doesn't use component states.

---

## How Recovery Works

The plugin includes a multi-layered recovery system that runs automatically:

1. **After every icon switch** — re-enables `MainActivity`, restores protected components
2. **On Flutter engine attach** — runs a full state reconciliation from persisted SharedPreferences
3. **On `BOOT_COMPLETED`** — `IconStateRecoveryReceiver` (auto-registered via manifest merger) restores alias states + protected components
4. **On `MY_PACKAGE_REPLACED`** — same receiver handles app updates

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

---

## Troubleshooting

### "Activity class does not exist" when running `flutter run`

After switching icons, `flutter run` fails with:
```
Error: Activity class {com.example.app/com.example.app.MainActivity} does not exist.
```

**Fix:** `MainActivity` must have **no LAUNCHER intent-filter** and must never be disabled. Follow the manifest setup above. If you're already in this state, re-enable it manually:

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

### Notifications stop working after icon switch (Android)

Third-party notification components (e.g., MoEngage PushTracker) can get disrupted by alias state changes. **Use `registerProtectedComponents()`** to keep them in the correct state. See [Protected Components](#protected-components-android).

---

## Notes and Caveats

- **iOS system alert:** iOS always shows a confirmation dialog when changing icons. This cannot be suppressed.
- **Android launcher delay:** The launcher may take a few seconds to reflect the new icon. The app may briefly disappear from the home screen.
- **Pre-bundled icons only:** You cannot download and set arbitrary icons at runtime. All icons must be included in the app bundle at build time.
- **Android OEM quirks:** Some OEM launchers may not reflect the change correctly. Use `blacklistedBrands` to skip problematic devices.
- **Badge numbers:** Only supported on iOS. On Android, `setBadgeNumber` is a no-op and `badgeNumber` always returns 0.
- **BOOT_COMPLETED permission:** The plugin's manifest declares `RECEIVE_BOOT_COMPLETED` for the recovery receiver. This merges automatically into your app.

---

## License

See [LICENSE](LICENSE) for details.
