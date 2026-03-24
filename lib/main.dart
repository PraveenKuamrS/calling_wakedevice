import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';

// ── CONFIG ────────────────────────────────────────────────────────
const String SERVER_IP = "192.168.1.141";
const String SERVER_URL = "http://$SERVER_IP:3000";
const String WS_URL = "ws://$SERVER_IP:3000";

// ── User model ────────────────────────────────────────────────────
class UserInfo {
  final String name;
  final bool online;
  final bool inCall;
  UserInfo({required this.name, required this.online, this.inCall = false});
}

// ── Background FCM handler ────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['type'] == 'incoming_call') {
    await _showIncomingCallUI(
      callerName: message.data['callerName'] ?? 'Unknown',
      roomId: message.data['roomId'] ?? '',
    );
  }
}

Future<void> _showIncomingCallUI({
  required String callerName,
  required String roomId,
}) async {
  final params = CallKitParams(
    id: roomId,
    nameCaller: callerName,
    appName: 'CallTest',
    type: 0,
    duration: 30000,
    textAccept: 'Accept',
    textDecline: 'Decline',
    extra: {'roomId': roomId, 'callerName': callerName},
    android: const AndroidParams(
      isCustomNotification: true,
      isShowFullLockedScreen: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#0d1117',
      actionColor: '#4CAF50',
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

// ── App entry ─────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const CallTestApp());
}

class CallTestApp extends StatelessWidget {
  const CallTestApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CallTest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F9FE),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF6C5CE7),
          secondary: Color(0xFF00B894),
          surface: Colors.white,
          background: Color(0xFFF8F9FE),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF2D3436),
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE1E8ED)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE1E8ED)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF6C5CE7), width: 2),
          ),
        ),
      ),
      home: const RootScreen(),
    );
  }
}

// ── Root: decides which screen to show ───────────────────────────
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  bool _loading = true;
  String? _savedName;

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name');
    setState(() {
      _savedName = name;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_savedName == null || _savedName!.isEmpty) {
      return NameScreen(
        onNameSaved: (name) {
          setState(() => _savedName = name);
        },
      );
    }
    return UsersScreen(myName: _savedName!);
  }
}

// ═══════════════════════════════════════════════════════════════════
// SCREEN 1 — Name entry
// ═══════════════════════════════════════════════════════════════════
class NameScreen extends StatefulWidget {
  final void Function(String name) onNameSaved;
  const NameScreen({super.key, required this.onNameSaved});
  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    widget.onNameSaved(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'CallTest',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enter your name to get started',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 48),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _ctrl,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF2D3436),
                          ),
                          decoration: InputDecoration(
                            labelText: 'Your name',
                            labelStyle: TextStyle(color: Colors.grey.shade600),
                            prefixIcon: Icon(
                              Icons.person_outline,
                              color: const Color(0xFF6C5CE7),
                            ),
                          ),
                          onSubmitted: (_) => _save(),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C5CE7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: _saving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Continue',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SCREEN 2 — Users list
// ═══════════════════════════════════════════════════════════════════
class UsersScreen extends StatefulWidget {
  final String myName;
  const UsersScreen({super.key, required this.myName});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<UserInfo> _users = [];
  bool _loading = false;
  String? _fcmToken;
  WebSocketChannel? _ws;
  Stream? _wsBroadcast;
  bool _registered = false;
  StreamSubscription? _wsSub;
  bool _isInCallScreen = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Permission.microphone.request();
    await Permission.notification.request();

    // Get FCM token
    await FirebaseMessaging.instance.requestPermission();
    _fcmToken = await FirebaseMessaging.instance.getToken();
    print('[FCM] token: $_fcmToken');

    // Connect WebSocket + register
    _connectWS();

    // Listen for foreground FCM
    FirebaseMessaging.onMessage.listen((msg) {
      if (msg.data['type'] == 'incoming_call') {
        // Show full screen incoming call UI when app is open
        final callerName = msg.data['callerName'] ?? 'Unknown';
        final roomId = msg.data['roomId'] ?? '';

        if (!_isInCallScreen && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IncomingCallScreen(
                callerName: callerName,
                roomId: roomId,
                onAccept: () => _acceptCall(roomId, callerName),
                onDecline: () => _declineCall(roomId),
              ),
              fullscreenDialog: true,
            ),
          );
        }
      }
    });

    // CallKit events (for when app is killed/background)
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      print('[CallKit] event: ${event.event}');

      if (event.event == Event.actionCallAccept) {
        final roomId = event.body['extra']?['roomId'] ?? event.body['id'];
        final callerName = event.body['extra']?['callerName'] ?? 'Unknown';

        // Dismiss any incoming call screens
        Navigator.popUntil(context, (route) => route.isFirst);

        _acceptCall(roomId.toString(), callerName.toString());
      }

      if (event.event == Event.actionCallDecline) {
        final roomId = event.body['extra']?['roomId'] ?? event.body['id'];
        _declineCall(roomId.toString());
      }

      if (event.event == Event.actionCallEnded) {
        FlutterCallkitIncoming.endAllCalls();
      }
    });

    await _fetchUsers();
  }

  void _connectWS() {
    try {
      _ws = WebSocketChannel.connect(Uri.parse(WS_URL));
      // Convert to broadcast stream so multiple listeners can attach
      _wsBroadcast = _ws!.stream.asBroadcastStream();

      _wsSub = _wsBroadcast!.listen(
        (data) {
          final msg = jsonDecode(data);
          print('[WS] ${msg['type']}');
          if (msg['type'] == 'registered') {
            setState(() => _registered = true);
          }
          if (msg['type'] == 'call_cancelled') {
            // Caller cancelled the call - dismiss incoming call UI
            FlutterCallkitIncoming.endAllCalls();
            if (mounted && Navigator.canPop(context)) {
              Navigator.popUntil(context, (route) => route.isFirst);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Call cancelled'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        },
        onDone: () => print('[WS] closed'),
        onError: (e) => print('[WS] error: $e'),
      );

      // Register this user
      _ws!.sink.add(
        jsonEncode({
          'type': 'register',
          'name': widget.myName,
          'fcmToken': _fcmToken,
        }),
      );
    } catch (e) {
      print('[WS] connect error: $e');
    }
  }

  void _reconnectWS() {
    if (_wsBroadcast != null) {
      _wsSub = _wsBroadcast!.listen(
        (data) {
          final msg = jsonDecode(data);
          print('[WS] ${msg['type']}');
          if (msg['type'] == 'registered') {
            setState(() => _registered = true);
          }
          if (msg['type'] == 'call_cancelled') {
            // Caller cancelled the call - dismiss incoming call UI
            FlutterCallkitIncoming.endAllCalls();
            if (mounted && Navigator.canPop(context)) {
              Navigator.popUntil(context, (route) => route.isFirst);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Call cancelled'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        },
        onDone: () => print('[WS] closed'),
        onError: (e) => print('[WS] error: $e'),
      );
    }
  }

  Future<void> _fetchUsers() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('$SERVER_URL/users?me=${Uri.encodeComponent(widget.myName)}'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['users'] as List)
            .map(
              (u) => UserInfo(
                name: u['name'].toString(),
                online: u['online'] ?? false,
              ),
            )
            .toList();
        setState(() => _users = list);
      }
    } catch (e) {
      print('[HTTP] error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _acceptCall(String roomId, String callerName) async {
    // Cancel current subscription
    await _wsSub?.cancel();
    _isInCallScreen = true;

    // Dismiss all CallKit notifications
    await FlutterCallkitIncoming.endAllCalls();

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InCallScreen(
          myName: widget.myName,
          peerName: callerName,
          roomId: roomId,
          ws: _ws!,
          wsStream: _wsBroadcast!,
          isCaller: false,
        ),
      ),
    );

    // When returning from call
    _isInCallScreen = false;
    _reconnectWS();
    _fetchUsers();
  }

  Future<void> _declineCall(String roomId) async {
    // End CallKit notifications
    await FlutterCallkitIncoming.endAllCalls();

    // Send decline via WebSocket (peer will receive peer_left message)
    _ws?.sink.add(jsonEncode({'type': 'leave', 'roomId': roomId}));

    // Dismiss incoming call screen if present
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<void> _callUser(String targetName) async {
    final roomId = 'room_${DateTime.now().millisecondsSinceEpoch}';

    // Tell server to push the target
    final res = await http.post(
      Uri.parse('$SERVER_URL/call'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'callerName': widget.myName,
        'targetName': targetName,
        'roomId': roomId,
      }),
    );

    if (res.statusCode == 200) {
      // Cancel current subscription to avoid "Stream already listened to" error
      await _wsSub?.cancel();
      _isInCallScreen = true;

      // Go to calling screen (caller side)
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallingScreen(
            myName: widget.myName,
            peerName: targetName,
            roomId: roomId,
            ws: _ws!,
            wsStream: _wsBroadcast!,
            onCallEnded: () => Navigator.pop(context),
          ),
        ),
      );

      // Reconnect WebSocket when returning to users screen
      _isInCallScreen = false;
      _reconnectWS();
      _fetchUsers();
    } else if (res.statusCode == 409) {
      // User is busy
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$targetName is busy in another call'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      final err = jsonDecode(res.body)['error'] ?? 'Failed';
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_name');
    _ws?.sink.close();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => NameScreen(
          onNameSaved: (name) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => UsersScreen(myName: name)),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _ws?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.myName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3436),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _registered
                        ? const Color(0xFF00B894)
                        : Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _registered ? 'Online' : 'Connecting...',
                  style: TextStyle(
                    fontSize: 12,
                    color: _registered
                        ? const Color(0xFF00B894)
                        : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchUsers,
            tooltip: 'Refresh users',
            color: const Color(0xFF6C5CE7),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
            tooltip: 'Change name',
            color: const Color(0xFF6C5CE7),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
            )
          : _users.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C5CE7).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.people_outline_rounded,
                      size: 50,
                      color: Color(0xFF6C5CE7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No other users online',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D3436),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pull to refresh or try again',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _fetchUsers,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final user = _users[i];
                return _UserTile(
                  name: user.name,
                  isOnline: user.online,
                  isInCall: user.inCall,
                  onCall: () => _callUser(user.name),
                );
              },
            ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final String name;
  final bool isOnline;
  final bool isInCall;
  final VoidCallback onCall;
  const _UserTile({
    required this.name,
    required this.isOnline,
    this.isInCall = false,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onCall,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          name[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? const Color(0xFF00B894)
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            isOnline ? Icons.circle : Icons.circle_outlined,
                            size: 8,
                            color: isOnline
                                ? const Color(0xFF00B894)
                                : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isOnline
                                  ? (isInCall ? 'In another call' : 'Available')
                                  : 'Offline',
                              style: TextStyle(
                                color: isOnline
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00B894), Color(0xFF00D2AA)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00B894).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: onCall,
                    icon: const Icon(Icons.call_rounded, color: Colors.white),
                    iconSize: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SCREEN 3 — Incoming Call (full screen for receiver when app is open)
// ═══════════════════════════════════════════════════════════════════
class IncomingCallScreen extends StatefulWidget {
  final String callerName;
  final String roomId;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallScreen({
    super.key,
    required this.callerName,
    required this.roomId,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  void _accept() {
    Navigator.pop(context);
    widget.onAccept();
  }

  void _decline() {
    Navigator.pop(context);
    widget.onDecline();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              // Pulsing avatar
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Transform.scale(
                  scale: 1.0 + _pulse.value * 0.1,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.2),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        widget.callerName[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 64,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                widget.callerName,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Incoming call...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Decline button
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _decline,
                              borderRadius: BorderRadius.circular(35),
                              child: const Icon(
                                Icons.call_end_rounded,
                                size: 32,
                                color: Color(0xFFFF6B6B),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Decline',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    // Accept button
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00B894), Color(0xFF00D2AA)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00B894).withOpacity(0.5),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _accept,
                              borderRadius: BorderRadius.circular(40),
                              child: const Icon(
                                Icons.call_rounded,
                                size: 36,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Accept',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SCREEN 4 — Calling (caller waits for answer)
// ═══════════════════════════════════════════════════════════════════
class CallingScreen extends StatefulWidget {
  final String myName;
  final String peerName;
  final String roomId;
  final WebSocketChannel ws;
  final Stream wsStream;
  final VoidCallback onCallEnded;

  const CallingScreen({
    super.key,
    required this.myName,
    required this.peerName,
    required this.roomId,
    required this.ws,
    required this.wsStream,
    required this.onCallEnded,
  });

  @override
  State<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends State<CallingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late StreamSubscription _wsSub;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    // Join room and wait for peer to join
    widget.ws.sink.add(jsonEncode({'type': 'join', 'roomId': widget.roomId}));

    _wsSub = widget.wsStream.listen((data) {
      final msg = jsonDecode(data);
      if (msg['type'] == 'peer_joined') {
        // Peer accepted — go to in-call
        _wsSub.cancel();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InCallScreen(
              myName: widget.myName,
              peerName: widget.peerName,
              roomId: widget.roomId,
              ws: widget.ws,
              wsStream: widget.wsStream,
              isCaller: true,
            ),
          ),
        );
      }
      if (msg['type'] == 'peer_left' || msg['type'] == 'call_declined') {
        _wsSub.cancel();
        if (!mounted) return;
        Navigator.pop(context);
        if (msg['type'] == 'call_declined') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call declined'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Call ended')));
        }
      }
    });
  }

  void _cancelCall() {
    // Notify backend to cancel the call and reset states
    http
        .post(
          Uri.parse('$SERVER_URL/call-cancel'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'callerName': widget.myName,
            'targetName': widget.peerName,
            'roomId': widget.roomId,
          }),
        )
        .then((_) {})
        .catchError((e) {
          print('[Cancel] error: $e');
        });

    widget.ws.sink.add(jsonEncode({'type': 'leave', 'roomId': widget.roomId}));
    FlutterCallkitIncoming.endAllCalls();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _wsSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) => Transform.scale(
                    scale: 1.0 + _pulse.value * 0.08,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.2),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          widget.peerName[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 56,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  widget.peerName,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Calling...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _cancelCall,
                      borderRadius: BorderRadius.circular(35),
                      child: const Icon(
                        Icons.call_end_rounded,
                        size: 32,
                        color: Color(0xFFFF6B6B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SCREEN 5 — In call (audio over WebSocket)
// ═══════════════════════════════════════════════════════════════════
class InCallScreen extends StatefulWidget {
  final String myName;
  final String peerName;
  final String roomId;
  final WebSocketChannel ws;
  final Stream wsStream;
  final bool isCaller;

  const InCallScreen({
    super.key,
    required this.myName,
    required this.peerName,
    required this.roomId,
    required this.ws,
    required this.wsStream,
    required this.isCaller,
  });

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _muted = false;
  bool _connected = false;
  int _duration = 0;
  Timer? _timer;
  late StreamSubscription _wsSub;
  bool _speakerOn = false;

  @override
  void initState() {
    super.initState();
    _initWebRTC();
  }

  Future<void> _initWebRTC() async {
    // Get microphone access
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    // Create peer connection
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(config);

    // Add local audio track
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // Handle incoming remote audio
    _peerConnection!.onTrack = (event) {
      print('[WebRTC] Remote track received');
      // Audio plays automatically through device speakers
    };

    // Handle ICE candidates
    _peerConnection!.onIceCandidate = (candidate) {
      widget.ws.sink.add(
        jsonEncode({
          'type': 'ice-candidate',
          'target': widget.peerName,
          'payload': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        }),
      );
    };

    _peerConnection!.onConnectionState = (state) {
      print('[WebRTC] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _connected = true);
        _startTimer();
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _endCall(peerLeft: true);
      }
    };

    // Start the call
    await _startCall();
  }

  Future<void> _startCall() async {
    // Listen for signaling messages
    _wsSub = widget.wsStream.listen((data) async {
      try {
        final msg = jsonDecode(data);

        // Handle WebRTC signaling
        if (msg['type'] == 'offer') {
          await _handleOffer(msg['payload']);
        } else if (msg['type'] == 'answer') {
          await _handleAnswer(msg['payload']);
        } else if (msg['type'] == 'ice-candidate') {
          await _handleIceCandidate(msg['payload']);
        } else if (msg['type'] == 'call-ended') {
          _endCall(peerLeft: true, reason: msg['reason']);
        } else if (msg['type'] == 'peer_left') {
          _endCall(peerLeft: true);
        }
      } catch (e) {
        print('[WS] Error: $e');
      }
    });

    // Caller creates offer
    if (widget.isCaller) {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      widget.ws.sink.add(
        jsonEncode({
          'type': 'offer',
          'target': widget.peerName,
          'payload': {'sdp': offer.sdp, 'type': offer.type},
        }),
      );
      print('[WebRTC] Offer sent');
    } else {
      // Receiver joins room and waits for offer
      widget.ws.sink.add(jsonEncode({'type': 'join', 'roomId': widget.roomId}));
    }

    // Notify backend that call is accepted
    await http.post(
      Uri.parse('$SERVER_URL/call-accept'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'callerName': widget.isCaller ? widget.myName : widget.peerName,
        'targetName': widget.isCaller ? widget.peerName : widget.myName,
      }),
    );
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    final rtcDescription = RTCSessionDescription(
      payload['sdp'],
      payload['type'],
    );
    await _peerConnection!.setRemoteDescription(rtcDescription);

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    widget.ws.sink.add(
      jsonEncode({
        'type': 'answer',
        'target': widget.peerName,
        'payload': {'sdp': answer.sdp, 'type': answer.type},
      }),
    );
    print('[WebRTC] Answer sent');
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final rtcDescription = RTCSessionDescription(
      payload['sdp'],
      payload['type'],
    );
    await _peerConnection!.setRemoteDescription(rtcDescription);
    print('[WebRTC] Answer received');
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> payload) async {
    final candidate = RTCIceCandidate(
      payload['candidate'],
      payload['sdpMid'],
      payload['sdpMLineIndex'],
    );
    await _peerConnection!.addCandidate(candidate);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _duration++);
    });
  }

  void _toggleMute() {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().first;
      audioTrack.enabled = !audioTrack.enabled;
      setState(() => _muted = !audioTrack.enabled);
    }
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    Helper.setSpeakerphoneOn(_speakerOn);
  }

  void _endCall({bool peerLeft = false, String? reason}) {
    // Send end-call to backend and notify peer
    if (!peerLeft) {
      widget.ws.sink.add(
        jsonEncode({'type': 'end-call', 'roomId': widget.roomId}),
      );
    }

    FlutterCallkitIncoming.endAllCalls();
    _cleanup();

    if (mounted) {
      if (peerLeft) {
        final message = reason == 'peer_disconnected'
            ? 'Call ended - peer disconnected'
            : 'Call ended by peer';

        // Pop back to users screen
        Navigator.pop(context);

        // Show message after navigation
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          }
        });
      } else {
        Navigator.pop(context);
      }
    }
  }

  void _cleanup() {
    _timer?.cancel();
    _wsSub.cancel();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _peerConnection?.dispose();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  String get _durationStr {
    final m = (_duration ~/ 60).toString().padLeft(2, '0');
    final s = (_duration % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          // End call properly when back button is pressed
          _endCall();
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8F9FE), Colors.white],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Top section with avatar
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6C5CE7).withOpacity(0.3),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              widget.peerName[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 52,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          widget.peerName,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D3436),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _connected
                                ? const Color(0xFF00B894).withOpacity(0.1)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _connected ? _durationStr : 'Connecting...',
                            style: TextStyle(
                              color: _connected
                                  ? const Color(0xFF00B894)
                                  : Colors.grey.shade600,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Controls section
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mute button
                      _ModernCallButton(
                        icon: _muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: _muted ? 'Unmute' : 'Mute',
                        color: _muted
                            ? const Color(0xFFFF6B6B)
                            : Colors.grey.shade300,
                        iconColor: _muted ? Colors.white : Colors.grey.shade700,
                        onTap: _toggleMute,
                      ),
                      // End call button
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B6B),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFFF6B6B,
                                  ).withOpacity(0.4),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _endCall,
                                borderRadius: BorderRadius.circular(35),
                                child: const Icon(
                                  Icons.call_end_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'End',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      // Speaker button
                      _ModernCallButton(
                        icon: _speakerOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                        label: _speakerOn ? 'Speaker' : 'Earpiece',
                        color: _speakerOn
                            ? const Color(0xFF6C5CE7)
                            : Colors.grey.shade300,
                        iconColor: _speakerOn
                            ? Colors.white
                            : Colors.grey.shade700,
                        onTap: _toggleSpeaker,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _ModernCallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color == Colors.grey.shade300
                    ? Colors.black.withOpacity(0.05)
                    : color.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(30),
              child: Icon(icon, color: iconColor, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
// import 'package:flutter_callkit_incoming/entities/entities.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:http/http.dart' as http;

// // ── Change this to your machine's local IP (not localhost) ────────
// // Run `ifconfig` on Mac or `ipconfig` on Windows to find it
// // Example: 192.168.1.10
// const String SERVER_IP = "10.80.105.79";
// const String SERVER_URL = "http://$SERVER_IP:3000";
// const String WS_URL = "ws://$SERVER_IP:3000";

// // ── Background FCM handler (must be top-level function) ───────────
// @pragma('vm:entry-point')
// Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   await Firebase.initializeApp();
//   print("[FCM BG] received: ${message.data}");

//   if (message.data['type'] == 'incoming_call') {
//     await _showIncomingCall(
//       callerName: message.data['callerName'] ?? 'Unknown',
//       roomId: message.data['roomId'] ?? '',
//     );
//   }
// }

// // ── Show native call UI ───────────────────────────────────────────
// Future<void> _showIncomingCall({
//   required String callerName,
//   required String roomId,
// }) async {
//   final params = CallKitParams(
//     id: roomId,
//     nameCaller: callerName,
//     appName: 'CallTest',
//     type: 0, // 0 = audio, 1 = video
//     duration: 30000,
//     textAccept: 'Accept',
//     textDecline: 'Decline',
//     extra: {'roomId': roomId},
//     android: const AndroidParams(
//       isCustomNotification: true,
//       isShowFullLockedScreen: true,
//       isShowLogo: false,
//       ringtonePath: 'system_ringtone_default',
//       backgroundColor: '#1a1a2e',
//       actionColor: '#4CAF50',
//     ),
//   );
//   await FlutterCallkitIncoming.showCallkitIncoming(params);
// }

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await Firebase.initializeApp();

//   // Register background handler
//   FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

//   runApp(const CallTestApp());
// }

// class CallTestApp extends StatelessWidget {
//   const CallTestApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Call Test',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData.dark().copyWith(
//         colorScheme: ColorScheme.dark(
//           primary: Colors.greenAccent,
//           surface: const Color(0xFF1a1a2e),
//         ),
//         scaffoldBackgroundColor: const Color(0xFF1a1a2e),
//       ),
//       home: const HomeScreen(),
//     );
//   }
// }

// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});

//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> {
//   String _myToken = 'Fetching token...';
//   final _targetTokenController = TextEditingController();
//   final _callerNameController = TextEditingController(text: 'Device A');
//   String _status = 'Idle';
//   WebSocketChannel? _channel;
//   bool _inCall = false;
//   String? _currentRoomId;

//   @override
//   void initState() {
//     super.initState();
//     _init();
//   }

//   Future<void> _init() async {
//     // Permissions
//     await Permission.microphone.request();
//     await Permission.notification.request();

//     // FCM token
//     final messaging = FirebaseMessaging.instance;
//     await messaging.requestPermission();
//     final token = await messaging.getToken();
//     setState(() => _myToken = token ?? 'Failed to get token');
//     print('[FCM] My token: $_myToken');

//     // Foreground FCM
//     FirebaseMessaging.onMessage.listen((message) {
//       print('[FCM FG] ${message.data}');
//       if (message.data['type'] == 'incoming_call') {
//         _showIncomingCall(
//           callerName: message.data['callerName'] ?? 'Unknown',
//           roomId: message.data['roomId'] ?? '',
//         );
//       }
//     });

//     // CallKit events (accept / decline)
//     FlutterCallkitIncoming.onEvent.listen((event) {
//       if (event == null) return;
//       print('[CallKit] event: ${event.event} | body: ${event.body}');

//       switch (event.event) {
//         case Event.actionCallAccept:
//           final roomId = event.body['extra']?['roomId'] ?? event.body['id'];
//           _joinCall(roomId: roomId.toString());
//           break;
//         case Event.actionCallDecline:
//         case Event.actionCallEnded:
//           _leaveCall();
//           break;
//         default:
//           break;
//       }
//     });
//   }

//   // ── Outgoing call ─────────────────────────────────────────────
//   Future<void> _makeCall() async {
//     final targetToken = _targetTokenController.text.trim();
//     final callerName = _callerNameController.text.trim();

//     if (targetToken.isEmpty) {
//       _setStatus('Paste target device FCM token first');
//       return;
//     }

//     final roomId = 'room_${DateTime.now().millisecondsSinceEpoch}';
//     _setStatus('Calling...');

//     try {
//       final response = await http.post(
//         Uri.parse('$SERVER_URL/call'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'targetFcmToken': targetToken,
//           'callerName': callerName,
//           'roomId': roomId,
//         }),
//       );

//       if (response.statusCode == 200) {
//         _setStatus('Ringing... waiting for answer');
//         _currentRoomId = roomId;
//         // Caller also connects to the room
//         _connectWebSocket(roomId);
//       } else {
//         _setStatus('FCM error: ${response.body}');
//       }
//     } catch (e) {
//       _setStatus('Error: $e');
//     }
//   }

//   // ── Join call room via WebSocket ──────────────────────────────
//   void _joinCall({required String roomId}) {
//     _currentRoomId = roomId;
//     _connectWebSocket(roomId);
//     setState(() => _inCall = true);
//     _setStatus('In call — room: $roomId');
//   }

//   void _connectWebSocket(String roomId) {
//     _channel = WebSocketChannel.connect(Uri.parse(WS_URL));

//     // Join the room
//     _channel!.sink.add(jsonEncode({'type': 'join', 'roomId': roomId}));

//     _channel!.stream.listen(
//       (data) {
//         final msg = jsonDecode(data);
//         print('[WS] received: ${msg['type']}');

//         switch (msg['type']) {
//           case 'joined':
//             final peers = msg['peers'];
//             _setStatus('Connected — $peers peer(s) in room');
//             setState(() => _inCall = true);
//             break;
//           case 'peer_joined':
//             _setStatus('Peer joined the room!');
//             break;
//           case 'peer_left':
//             _setStatus('Peer left the call');
//             _leaveCall();
//             break;
//         }
//       },
//       onError: (e) => _setStatus('WS error: $e'),
//       onDone: () {
//         if (_inCall) _setStatus('Disconnected');
//       },
//     );
//   }

//   void _leaveCall() {
//     if (_currentRoomId != null) {
//       _channel?.sink.add(
//         jsonEncode({'type': 'leave', 'roomId': _currentRoomId}),
//       );
//     }
//     _channel?.sink.close();
//     _channel = null;
//     setState(() {
//       _inCall = false;
//       _currentRoomId = null;
//     });
//     _setStatus('Call ended');
//     FlutterCallkitIncoming.endAllCalls();
//   }

//   void _setStatus(String s) {
//     setState(() => _status = s);
//     print('[STATUS] $s');
//   }

//   @override
//   void dispose() {
//     _channel?.sink.close();
//     _targetTokenController.dispose();
//     _callerNameController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Call Test'),
//         backgroundColor: const Color(0xFF16213e),
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // ── My FCM Token ──────────────────────────────
//             _SectionCard(
//               title: 'My FCM token',
//               child: Column(
//                 children: [
//                   SelectableText(
//                     _myToken,
//                     style: const TextStyle(
//                       fontSize: 11,
//                       color: Colors.greenAccent,
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   ElevatedButton.icon(
//                     onPressed: () {
//                       Clipboard.setData(ClipboardData(text: _myToken));
//                       ScaffoldMessenger.of(context).showSnackBar(
//                         const SnackBar(content: Text('Token copied!')),
//                       );
//                     },
//                     icon: const Icon(Icons.copy, size: 16),
//                     label: const Text('Copy token'),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: const Color(0xFF0f3460),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             const SizedBox(height: 16),

//             // ── Make a call ───────────────────────────────
//             _SectionCard(
//               title: 'Make a call',
//               child: Column(
//                 children: [
//                   TextField(
//                     controller: _callerNameController,
//                     decoration: const InputDecoration(
//                       labelText: 'Your name (caller)',
//                       border: OutlineInputBorder(),
//                     ),
//                   ),
//                   const SizedBox(height: 12),
//                   TextField(
//                     controller: _targetTokenController,
//                     maxLines: 3,
//                     decoration: const InputDecoration(
//                       labelText: 'Target device FCM token',
//                       border: OutlineInputBorder(),
//                       hintText: 'Paste the other device\'s token here',
//                     ),
//                   ),
//                   const SizedBox(height: 12),
//                   SizedBox(
//                     width: double.infinity,
//                     child: ElevatedButton.icon(
//                       onPressed: _inCall ? null : _makeCall,
//                       icon: const Icon(Icons.call),
//                       label: const Text('Call'),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.green,
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             const SizedBox(height: 16),

//             // ── Status ────────────────────────────────────
//             _SectionCard(
//               title: 'Status',
//               child: Row(
//                 children: [
//                   Container(
//                     width: 10,
//                     height: 10,
//                     decoration: BoxDecoration(
//                       color: _inCall ? Colors.greenAccent : Colors.grey,
//                       shape: BoxShape.circle,
//                     ),
//                   ),
//                   const SizedBox(width: 10),
//                   Expanded(
//                     child: Text(_status, style: const TextStyle(fontSize: 14)),
//                   ),
//                 ],
//               ),
//             ),

//             const SizedBox(height: 16),

//             // ── In call controls ──────────────────────────
//             if (_inCall)
//               _SectionCard(
//                 title: 'In call',
//                 child: Column(
//                   children: [
//                     Text(
//                       'Room: $_currentRoomId',
//                       style: const TextStyle(fontSize: 11, color: Colors.grey),
//                     ),
//                     const SizedBox(height: 12),
//                     SizedBox(
//                       width: double.infinity,
//                       child: ElevatedButton.icon(
//                         onPressed: _leaveCall,
//                         icon: const Icon(Icons.call_end),
//                         label: const Text('End call'),
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: Colors.red,
//                           padding: const EdgeInsets.symmetric(vertical: 14),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _SectionCard extends StatelessWidget {
//   final String title;
//   final Widget child;
//   const _SectionCard({required this.title, required this.child});

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: const Color(0xFF16213e),
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: Colors.white12),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             title,
//             style: const TextStyle(
//               fontSize: 12,
//               color: Colors.white54,
//               letterSpacing: 1,
//             ),
//           ),
//           const SizedBox(height: 12),
//           child,
//         ],
//       ),
//     );
//   }
// }
