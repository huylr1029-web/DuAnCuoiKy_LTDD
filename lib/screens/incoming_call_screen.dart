import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/call_service.dart';
import '../widgets/avatar.dart';
import 'call_screen.dart';

/// Man hinh do chuong khi co nguoi goi toi.
class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final Map<String, dynamic> data;
  const IncomingCallScreen({super.key, required this.callId, required this.data});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  StreamSubscription? _sub;
  bool _handled = false;

  bool get _isVideo => widget.data['isVideo'] == true;
  String get _callerName => widget.data['callerName'] ?? 'Ai đó';

  @override
  void initState() {
    super.initState();
    // Neu nguoi goi huy / het gio -> tu dong dong man hinh
    _sub = CallService().callStream(widget.callId).listen((snap) {
      final status = snap.data()?['status'];
      if (!_handled && status != 'ringing' && mounted) {
        _handled = true;
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    _handled = true;
    await _sub?.cancel();
    await CallService().updateStatus(widget.callId, 'accepted');
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: widget.callId,
          peer: AppUser(uid: widget.data['callerId'], name: _callerName),
          isVideo: _isVideo,
          isCaller: false,
        ),
      ),
    );
  }

  Future<void> _decline() async {
    _handled = true;
    await _sub?.cancel();
    await CallService().updateStatus(widget.callId, 'rejected');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1C1E21), Color(0xFF0B3D91)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 80),
                Avatar(name: _callerName, radius: 56),
                const SizedBox(height: 20),
                Text(_callerName,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_isVideo ? 'Cuộc gọi video đến...' : 'Cuộc gọi thoại đến...',
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _button(Icons.call_end, Colors.red, 'Từ chối', _decline),
                      _button(_isVideo ? Icons.videocam : Icons.call, const Color(0xFF31A24C),
                          'Trả lời', _accept),
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

  Widget _button(IconData icon, Color color, String label, VoidCallback onTap) {
    return Column(children: [
      GestureDetector(
        onTap: onTap,
        child: CircleAvatar(
            radius: 34, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 32)),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white)),
    ]);
  }
}
