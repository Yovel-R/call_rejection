import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  static const _methodChannel = MethodChannel('call_screening_channel');

  bool _checking = true;
  bool _phoneGranted = false;
  bool _batteryGranted = false;
  bool _roleGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    setState(() => _checking = true);

    // 1. Check basic permissions
    try {
      final basic = await _methodChannel.invokeMethod<bool>(
        'checkBasicPermissions',
      );
      _phoneGranted = basic ?? false;
    } catch (e) {
      _phoneGranted = false;
    }

    // 2. Check battery optimization
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    _batteryGranted = batteryStatus.isGranted;

    // 3. Check Call Screening Role
    try {
      final held = await _methodChannel.invokeMethod<bool>(
        'isScreeningRoleHeld',
      );
      _roleGranted = held ?? false;
    } catch (e) {
      debugPrint("Error checking role: $e");
      _roleGranted = false;
    }

    setState(() => _checking = false);

    if (_allGranted) {
      _proceed();
    }
  }

  bool get _allGranted => _phoneGranted && _roleGranted;

  Future<void> _requestPermissions() async {
    // Request Phone/Call Log First
    if (!_phoneGranted) {
      try {
        final granted = await _methodChannel.invokeMethod<bool>(
          'requestBasicPermissions',
        );
        setState(() => _phoneGranted = granted ?? false);
        if (!_phoneGranted) return; // Stop if they deny
      } catch (e) {
        debugPrint("Error requesting native permissions: $e");
        if (!_phoneGranted) return;
      }
    }

    // Request Battery Optimization Next (Optional)
    if (!_batteryGranted) {
      final status = await Permission.ignoreBatteryOptimizations.request();
      setState(() => _batteryGranted = status.isGranted);
      // We do not return here if denied because this permission is optional.
    }

    // Request Call Screening Role Last
    if (!_roleGranted) {
      try {
        final granted = await _methodChannel.invokeMethod<bool>(
          'requestScreeningRole',
        );
        setState(() => _roleGranted = granted ?? false);
      } catch (e) {
        debugPrint("Error requesting role: $e");
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }

    // Check again and proceed if everything is good
    await _checkAllPermissions();
  }

  void _proceed() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D2B),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 32),
              const Text(
                'Permissions Required',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'To automatically terminate calls, this app needs some system permissions to function correctly.',
                style: TextStyle(fontSize: 16, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              if (_checking)
                const Center(child: CircularProgressIndicator())
              else ...[
                _buildPermissionRow(
                  icon: Icons.phone,
                  title: 'Phone & Call Logs',
                  subtitle: 'To detect incoming calls',
                  isGranted: _phoneGranted,
                ),
                const SizedBox(height: 16),
                _buildPermissionRow(
                  icon: Icons.battery_alert,
                  title: 'Background Execution (Optional)',
                  subtitle:
                      'To ensure calls are rejected even when app is closed',
                  isGranted: _batteryGranted,
                ),
                const SizedBox(height: 16),
                _buildPermissionRow(
                  icon: Icons.call_end,
                  title: 'Caller ID & Spam',
                  subtitle: 'To allow the app to actually terminate calls',
                  isGranted: _roleGranted,
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _allGranted ? _proceed : _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _allGranted ? 'Continue' : 'Grant Permissions',
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.white24,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isGranted ? Colors.green : Colors.white70,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ],
            ),
          ),
          if (isGranted)
            const Icon(Icons.check_circle, color: Colors.green)
          else
            const Icon(Icons.cancel, color: Colors.redAccent),
        ],
      ),
    );
  }
}
