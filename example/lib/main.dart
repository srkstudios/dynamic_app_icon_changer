import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_app_icon_changer/dynamic_app_icon_changer.dart';

/// Web-safe platform checks (`dart:io`'s `Platform` throws on web).
bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dynamic Icon Changer Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _supportsAlternate = false;
  String? _currentIconName;
  String _statusMessage = '';
  int _badgeNumber = 0;
  final TextEditingController _badgeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadState();
    _registerProtectedComponents();
  }

  @override
  void dispose() {
    _badgeController.dispose();
    super.dispose();
  }

  /// Register any third-party Android components that should be protected
  /// during icon switches. This ensures components like push notification
  /// handlers are not disrupted when activity-alias states change.
  Future<void> _registerProtectedComponents() async {
    if (!_isAndroid) return;

    try {
      // Example: protect MoEngage PushTracker from being disabled during
      // icon switches. Uncomment and adjust the class name for your app:
      //
      // await DynamicAppIconChanger.registerProtectedComponents([
      //   const ProtectedComponent(
      //     className: 'com.moengage.pushbase.activities.PushTracker',
      //     desiredState: ComponentState.enabled,
      //   ),
      // ]);
    } catch (e) {
      debugPrint('Failed to register protected components: $e');
    }
  }

  Future<void> _loadState() async {
    try {
      final supports = await DynamicAppIconChanger.supportsAlternateIcons;
      final iconName = await DynamicAppIconChanger.alternateIconName;
      int badge = 0;
      if (_isIOS) {
        badge = await DynamicAppIconChanger.badgeNumber;
      }
      if (!mounted) return;
      setState(() {
        _supportsAlternate = supports;
        _currentIconName = iconName;
        _badgeNumber = badge;
        _statusMessage = 'Ready. Supports alternate icons: $supports';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error loading state: ${e.message}';
      });
    }
  }

  Future<void> _setIcon(String? iconName) async {
    try {
      await DynamicAppIconChanger.setAlternateIconName(iconName);
      final current = await DynamicAppIconChanger.alternateIconName;
      if (!mounted) return;
      setState(() {
        _currentIconName = current;
        _statusMessage =
            'Icon changed to: ${iconName ?? "Default"} successfully!';
      });
    } on DynamicIconException catch (e) {
      if (!mounted) return;
      _showError('Failed to change icon: ${e.message}');
      setState(() {
        _statusMessage = 'Error: ${e.message}';
      });
    }
  }

  Future<void> _setIconBlacklisted() async {
    try {
      // Blacklist the current device manufacturer so the change is skipped
      await DynamicAppIconChanger.setAlternateIconName(
        'IconBlue',
        blacklistedBrands: [
          // This will match the current device, so the change should be skipped
          if (_isAndroid) 'auto-detected',
        ],
      );
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Blacklist demo: Attempted icon change with current manufacturer blacklisted. '
            'Check if the icon actually changed.';
      });
    } on DynamicIconException catch (e) {
      if (!mounted) return;
      _showError('Blacklist demo error: ${e.message}');
    }
  }

  Future<void> _setBadge(int count) async {
    try {
      await DynamicAppIconChanger.setBadgeNumber(count);
      final current = await DynamicAppIconChanger.badgeNumber;
      if (!mounted) return;
      setState(() {
        _badgeNumber = current;
        _statusMessage = 'Badge set to $count';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showError('Failed to set badge: ${e.message}');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dynamic Icon Changer'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Icon',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.app_settings_alt,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currentIconName ?? 'Default',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Icon switching section
          Text(
            'Switch App Icon',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),

          _IconButton(
            label: 'Default Icon',
            icon: Icons.home,
            color: Colors.grey,
            isActive: _currentIconName == null,
            onPressed: _supportsAlternate ? () => _setIcon(null) : null,
          ),
          const SizedBox(height: 8),
          _IconButton(
            label: 'Blue Icon',
            icon: Icons.circle,
            color: Colors.blue,
            isActive: _currentIconName == 'IconBlue',
            onPressed: _supportsAlternate ? () => _setIcon('IconBlue') : null,
          ),
          const SizedBox(height: 8),
          _IconButton(
            label: 'Green Icon',
            icon: Icons.circle,
            color: Colors.green,
            isActive: _currentIconName == 'IconGreen',
            onPressed: _supportsAlternate ? () => _setIcon('IconGreen') : null,
          ),

          // Android blacklist demo
          if (_isAndroid) ...[
            const SizedBox(height: 24),
            Text(
              'Android: Blacklist Demo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'This button tries to switch the icon but blacklists the current '
              'device manufacturer, so the change should be silently skipped.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _setIconBlacklisted,
              child: const Text('Try Blacklisted Change'),
            ),
          ],

          // iOS badge section
          if (_isIOS) ...[
            const SizedBox(height: 24),
            Text(
              'iOS: Badge Number',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Current badge: $_badgeNumber',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _badgeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Badge number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final count =
                        int.tryParse(_badgeController.text.trim()) ?? 0;
                    _setBadge(count);
                  },
                  child: const Text('Set Badge'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _setBadge(0),
              child: const Text('Clear Badge'),
            ),
          ],
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isActive,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: isActive
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          if (isActive)
            Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }
}
