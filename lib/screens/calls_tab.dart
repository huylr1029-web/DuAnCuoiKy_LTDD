import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import 'call_screen.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});
  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  bool _outgoing = false;
  final db = FirebaseFirestore.instance;
  final chat = ChatService();
  Future<void> _startCall(AppUser user, bool video) async {
    try {
      final id = await CallService().startCall(peer: user, isVideo: video);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) =>
          CallScreen(callId: id, peer: user, isVideo: video, isCaller: true)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể gọi: $e')));
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('Gọi đến')),
            ButtonSegment(value: true, label: Text('Gọi đi'))],
          selected: {_outgoing}, onSelectionChanged: (value) => setState(() => _outgoing = value.first))),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('calls').where(_outgoing ? 'callerId' : 'calleeId', isEqualTo: uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Không tải được lịch sử cuộc gọi: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs.toList()
            ..sort((a,b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                .compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
          if (docs.isEmpty) return const Center(child: Text('Chưa có cuộc gọi nào'));
          return ListView.builder(itemCount: docs.length, itemBuilder: (_, i) {
            final d = docs[i].data();
            final peerId = (d[_outgoing ? 'calleeId' : 'callerId'] ?? '').toString();
            final name = (d[_outgoing ? 'calleeName' : 'callerName'] ?? 'Người dùng').toString();
            final video = d['isVideo'] == true;
            final peer = AppUser(uid: peerId, name: name);
            return ListTile(
              leading: Icon(video ? Icons.videocam_outlined : Icons.phone_outlined),
              title: Text(name),
              subtitle: Text('${_outgoing ? 'Gọi đi' : 'Gọi đến'} · ${d['status'] ?? 'Không rõ'}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Gọi thoại', icon: const Icon(Icons.call), onPressed: () => _startCall(peer, false)),
                IconButton(tooltip: 'Gọi video', icon: const Icon(Icons.videocam), onPressed: () => _startCall(peer, true)),
              ]),
            );
          });
        },
      )),
    ]);
  }
}
