import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'permission_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('user_token');
  runApp(MainApp(isLoggedIn: token != null && token.isNotEmpty));
}

class MainApp extends StatelessWidget {
  final bool isLoggedIn;
  const MainApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call AutoTerminate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A237E),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      initialRoute: isLoggedIn ? '/permissions' : '/login',
      routes: {
        '/permissions': (_) => const PermissionScreen(),
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const CallScreeningHome(),
      },
    );
  }
}

class CallScreeningHome extends StatefulWidget {
  const CallScreeningHome({super.key});

  @override
  State<CallScreeningHome> createState() => _CallScreeningHomeState();
}

class _CallScreeningHomeState extends State<CallScreeningHome>
    with WidgetsBindingObserver {
  static const _methodChannel = MethodChannel('call_screening_channel');
  static const _eventChannel = EventChannel('call_screening_events');

  // Role / status state
  bool _roleHeld = false;
  bool _loading = true;
  bool _checking = false;
  String _statusMessage = 'Checking status…';

  String _serviceName = '';

  String? _incomingNumber; // null = no active call
  StreamSubscription? _callSub;

  final List<Map<String, String>> _callLog = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserInfo();
    _checkRole();
    _subscribeToCallEvents();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkRole();
  }

  // ─── EventChannel ────────────────────────────────────────────────────────

  void _subscribeToCallEvents() {
    _callSub = _eventChannel.receiveBroadcastStream().listen(
      _onCallEvent,
      onError: (e) => debugPrint('[CallScreening] EventChannel error: $e'),
    );
  }

  void _onCallEvent(dynamic event) {
    final map = Map<String, String>.from(event as Map);
    final state = map['state'] ?? '';
    final number = map['number'] ?? '';
    final isUpdate = map['update'] == 'true';
    debugPrint(
      '[CallScreening] call event: state=$state number=$number update=$isUpdate',
    );

    setState(() {
      if (state == 'RINGING') {
        final displayNumber = number.isEmpty ? 'Unknown number' : number;
        _incomingNumber = displayNumber;

        if (isUpdate) {
          if (_callLog.isNotEmpty &&
              _callLog.first['number'] == 'Unknown number') {
            _callLog[0] = {
              'number': displayNumber,
              'time': _callLog[0]['time']!,
            };
          }
        } else if (number.isNotEmpty) {
          // First RINGING with a real number — add fresh log entry
          _callLog.insert(0, {'number': displayNumber, 'time': _now()});
          if (_callLog.length > 50) _callLog.removeLast();
        }
        // First RINGING with empty number: show banner only, don't log yet
        // (the update event will arrive with the real number shortly)
      } else {
        _incomingNumber = null;
      }
    });
  }

  String _now() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }

  // ─── Load user from prefs ────────────────────────────────────────────────

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serviceName = prefs.getString('user_serviceName') ?? '';
    });
  }

  Future<void> _logout() async {
    final confirm = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A1A4E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Confirm Logout',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Text(
              'Are you sure you want to log out?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Logout'),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return ScaleTransition(scale: curve, child: child);
      },
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.of(context).pushReplacementNamed('/login');
  }

  Future<void> _checkRole() async {
    if (_checking) return;
    _checking = true;
    setState(() => _loading = true);
    try {
      final held = await _methodChannel.invokeMethod<bool>(
        'isScreeningRoleHeld',
      );
      debugPrint('[CallScreening] isScreeningRoleHeld result: $held');
      setState(() {
        _roleHeld = held ?? false;
        _statusMessage = _roleHeld
            ? 'Auto-termination is ACTIVE'
            : 'Auto-termination is INACTIVE';
        _loading = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.message}';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _loading = false;
      });
    } finally {
      _checking = false;
    }
  }

  Future<void> _requestRole() async {
    setState(() => _loading = true);
    try {
      final granted = await _methodChannel.invokeMethod<bool>(
        'requestScreeningRole',
      );
      debugPrint('[CallScreening] requestScreeningRole result: $granted');
      _showSnack(
        granted == true
            ? '✅ Active — calls will now be auto-terminated!'
            : '❌ Permission not granted.',
      );
    } on PlatformException catch (e) {
      _showSnack('Error: ${e.message}');
    } finally {
      await _checkRole();
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0D0D2B),
              const Color(0xFF1A1A4E),
              cs.primary.withValues(alpha: 0.6),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                  child: IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white54),
                    tooltip: 'Sign out',
                    onPressed: _logout,
                  ),
                ),
              ),
              // Incoming call banner
              if (_incomingNumber != null) _buildIncomingBanner(),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildIcon(),
                      const SizedBox(height: 28),
                      _buildTitle(),
                      const SizedBox(height: 40),
                      if (_loading)
                        const CircularProgressIndicator()
                      else ...[
                        _buildStatusCard(),
                        const SizedBox(height: 24),
                        _buildActionButton(),
                      ],
                      const SizedBox(height: 32),
                      if (_callLog.isNotEmpty) _buildCallLog(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncomingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF4081), Color(0xFFE91E63)],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_received, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Incoming Call',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  _incomingNumber!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Auto-rejecting…',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Icon(
        _roleHeld ? Icons.phone_disabled : Icons.phone_callback,
        size: 44,
        color: _roleHeld ? Colors.greenAccent : Colors.white70,
      ),
    );
  }

  Widget _buildTitle() {
    String formattedService = '';
    if (_serviceName.isNotEmpty) {
      formattedService =
          _serviceName[0].toUpperCase() + _serviceName.substring(1);
    }

    return Column(
      children: [
        const Text(
          'Call Auto-Terminate',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (_serviceName.isNotEmpty)
          Text(
            'Service: $formattedService',
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 6),
        const Text(
          'Automatically ends incoming calls\nafter a 3-second grace period.',
          style: TextStyle(fontSize: 13, color: Colors.white60, height: 1.5),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: _roleHeld
            ? Colors.green.withValues(alpha: 0.18)
            : Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _roleHeld
              ? Colors.greenAccent.withValues(alpha: 0.5)
              : Colors.orange.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _roleHeld
                ? Icons.check_circle_outline
                : Icons.warning_amber_outlined,
            color: _roleHeld ? Colors.greenAccent : Colors.orange,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                color: _roleHeld ? Colors.greenAccent : Colors.orange,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _roleHeld
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3F51B5)],
                ),
          borderRadius: BorderRadius.circular(14),
          border: _roleHeld ? Border.all(color: Colors.white24) : null,
        ),
        child: ElevatedButton(
          onPressed: _roleHeld ? null : _requestRole,
          style: ElevatedButton.styleFrom(
            backgroundColor: _roleHeld ? Colors.white10 : Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            _roleHeld ? 'Role Already Active ✓' : 'Enable Auto-Termination',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallLog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AUTO-REJECTED CALLS',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        ..._callLog
            .take(10)
            .map(
              (e) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.phone_missed,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        e['number'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      e['time'] ?? '',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
