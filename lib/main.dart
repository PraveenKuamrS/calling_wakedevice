import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
import 'package:record/record.dart';
import 'package:flutter_sound/flutter_sound.dart';

// ── CONFIG ────────────────────────────────────────────────────────
const String SERVER_IP = "192.168.1.177";
const String SERVER_URL = "http://$SERVER_IP:3000";
const String WS_URL = "ws://$SERVER_IP:3000";

// ── User model ────────────────────────────────────────────────────
class UserInfo {
  final String name;
  final bool online;
  UserInfo({required this.name, required this.online});
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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0d1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50),
          surface: Color(0xFF161b22),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF161b22),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF30363d)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF30363d)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4CAF50)),
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.call, size: 64, color: Color(0xFF4CAF50)),
              const SizedBox(height: 24),
              const Text(
                'CallTest',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your name to get started',
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                ),
              ),
            ],
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
        _showIncomingCallUI(
          callerName: msg.data['callerName'] ?? 'Unknown',
          roomId: msg.data['roomId'] ?? '',
        );
      }
    });

    // CallKit events
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      if (event.event == Event.actionCallAccept) {
        final roomId = event.body['extra']?['roomId'] ?? event.body['id'];
        final callerName = event.body['extra']?['callerName'] ?? 'Unknown';
        _goToInCall(
          roomId: roomId.toString(),
          peerName: callerName.toString(),
          isCaller: false,
        );
      }
      if (event.event == Event.actionCallDecline ||
          event.event == Event.actionCallEnded) {
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

      // Go to calling screen (caller side)
      if (!mounted) return;
      Navigator.push(
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
      ).then((_) {
        // Reconnect WebSocket when returning to users screen
        _reconnectWS();
      });
    } else {
      final err = jsonDecode(res.body)['error'] ?? 'Failed';
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
    }
  }

  void _goToInCall({
    required String roomId,
    required String peerName,
    required bool isCaller,
  }) async {
    // Cancel current subscription
    await _wsSub?.cancel();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InCallScreen(
          myName: widget.myName,
          peerName: peerName,
          roomId: roomId,
          ws: _ws!,
          wsStream: _wsBroadcast!,
          isCaller: isCaller,
        ),
      ),
    ).then((_) {
      // Reconnect WebSocket when returning to users screen
      _reconnectWS();
    });
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.myName, style: const TextStyle(fontSize: 16)),
            Text(
              _registered ? 'online' : 'connecting...',
              style: TextStyle(
                fontSize: 11,
                color: _registered ? Colors.greenAccent : Colors.orange,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchUsers,
            tooltip: 'Refresh users',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Change name',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 64,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No other users online',
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _fetchUsers,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
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
  final VoidCallback onCall;
  const _UserTile({
    required this.name,
    required this.isOnline,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363d)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF4CAF50).withOpacity(0.2),
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isOnline ? Colors.greenAccent : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF161b22), width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          isOnline
              ? 'online • tap to call'
              : 'offline • will receive notification',
          style: TextStyle(
            color: isOnline ? Colors.white54 : Colors.white38,
            fontSize: 11,
          ),
        ),
        trailing: IconButton(
          onPressed: onCall,
          icon: const Icon(Icons.call, color: Color(0xFF4CAF50)),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50).withOpacity(0.15),
          ),
        ),
        onTap: onCall,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SCREEN 3 — Calling (caller waits for answer)
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
      if (msg['type'] == 'peer_left') {
        _wsSub.cancel();
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Call declined')));
      }
    });
  }

  void _cancelCall() {
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
      backgroundColor: const Color(0xFF0d1117),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) => Transform.scale(
                scale: 1.0 + _pulse.value * 0.08,
                child: child,
              ),
              child: CircleAvatar(
                radius: 60,
                backgroundColor: const Color(0xFF4CAF50).withOpacity(0.2),
                child: Text(
                  widget.peerName[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 48,
                    color: Color(0xFF4CAF50),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.peerName,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Calling...',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 60),
            FloatingActionButton.large(
              onPressed: _cancelCall,
              backgroundColor: Colors.red,
              child: const Icon(Icons.call_end, size: 36),
            ),
            const SizedBox(height: 12),
            const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SCREEN 4 — In call (audio over WebSocket)
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
  final _recorder = AudioRecorder();
  final _player = FlutterSoundPlayer();
  bool _muted = false;
  bool _connected = false;
  int _duration = 0;
  Timer? _timer;
  late StreamSubscription _wsSub;
  StreamSubscription? _audioSub;
  bool _playerInitialized = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _startCall();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.openPlayer();
      await _player.setSubscriptionDuration(const Duration(milliseconds: 10));

      // Start player in feed mode for real-time audio
      await _player.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 16000,
        bufferSize: 8192,
        interleaved: false,
      );

      _playerInitialized = true;
      print('[AUDIO] Player initialized and ready for streaming');
    } catch (e) {
      print('[AUDIO] Player init error: $e');
    }
  }

  Future<void> _startCall() async {
    // Non-caller joins the room
    if (!widget.isCaller) {
      widget.ws.sink.add(jsonEncode({'type': 'join', 'roomId': widget.roomId}));
    }

    setState(() => _connected = true);
    _startTimer();
    _startRecording();

    // Listen for incoming audio + peer events
    _wsSub = widget.wsStream.listen((data) {
      try {
        final msg = jsonDecode(data);
        if (msg['type'] == 'audio' && msg['payload'] != null) {
          final bytes = base64Decode(msg['payload']);
          _playAudio(bytes);
        }
        if (msg['type'] == 'peer_left') {
          _endCall(peerLeft: true);
        }
      } catch (_) {}
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _duration++);
    });
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _audioSub = stream.listen((chunk) {
      if (_muted || !_connected) return;
      // Send raw audio bytes as base64 over WebSocket
      final encoded = base64Encode(chunk);
      widget.ws.sink.add(
        jsonEncode({
          'type': 'audio',
          'roomId': widget.roomId,
          'payload': encoded,
        }),
      );
    });
  }

  Future<void> _playAudio(List<int> bytes) async {
    // Play received PCM bytes in real-time
    if (!_playerInitialized) return;
    try {
      final uint8List = Uint8List.fromList(bytes);
      await _player.feedFromStream(uint8List);
    } catch (e) {
      print('[AUDIO] play error: $e');
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
  }

  void _endCall({bool peerLeft = false}) {
    widget.ws.sink.add(jsonEncode({'type': 'leave', 'roomId': widget.roomId}));
    FlutterCallkitIncoming.endAllCalls();
    _cleanup();
    if (mounted) {
      if (peerLeft) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Call ended by peer')));
      }
      Navigator.pop(context);
    }
  }

  void _cleanup() {
    _timer?.cancel();
    _wsSub.cancel();
    _audioSub?.cancel();
    _recorder.stop();
    if (_playerInitialized) {
      _player.closePlayer();
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Avatar
            CircleAvatar(
              radius: 64,
              backgroundColor: const Color(0xFF4CAF50).withOpacity(0.15),
              child: Text(
                widget.peerName[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 52,
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.peerName,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _connected ? _durationStr : 'Connecting...',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const Spacer(),
            // Controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute
                  _CallButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    label: _muted ? 'Unmute' : 'Mute',
                    color: _muted ? Colors.orange : Colors.white24,
                    onTap: _toggleMute,
                  ),
                  // End call
                  _CallButton(
                    icon: Icons.call_end,
                    label: 'End',
                    color: Colors.red,
                    size: 72,
                    onTap: _endCall,
                  ),
                  // Speaker (placeholder)
                  _CallButton(
                    icon: Icons.volume_up,
                    label: 'Speaker',
                    color: Colors.white24,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
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
