import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../widgets/avatar.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final AppUser peer;
  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chat = ChatService();
  final _input = TextEditingController();
  late final String _chatId = ChatService.chatIdOf(_chat.myUid, widget.peer.uid);
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  Future<void> _send([String? override]) async {
    final text = override ?? _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await _chat.sendMessage(widget.peer, text);
  }

  Future<void> _call(bool isVideo) async {
    final callId = await CallService().startCall(peer: widget.peer, isVideo: isVideo);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
            callId: callId, peer: widget.peer, isVideo: isVideo, isCaller: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: StreamBuilder<AppUser?>(
          stream: _chat.userStream(widget.peer.uid),
          builder: (context, snap) {
            final online = snap.data?.online ?? false;
            return Row(children: [
              Avatar(name: widget.peer.name, radius: 18, online: online),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.peer.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(online ? 'Đang hoạt động' : 'Không hoạt động',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ),
            ]);
          },
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.call, color: messengerBlue),
              tooltip: 'Gọi thoại',
              onPressed: () => _call(false)),
          IconButton(
              icon: const Icon(Icons.videocam, color: messengerBlue),
              tooltip: 'Gọi video',
              onPressed: () => _call(true)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chat.messages(_chatId),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Lỗi: ${snap.error}'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Avatar(name: widget.peer.name, radius: 40),
                      const SizedBox(height: 12),
                      Text(widget.peer.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Text('Hãy gửi lời chào 👋', style: TextStyle(color: Colors.grey)),
                    ]),
                  );
                }
                return ListView.builder(
                  reverse: true, // tin moi nhat o duoi cung
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) => _buildMessage(docs[i].data()),
                );
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> m) {
    final isMe = m['senderId'] == _chat.myUid;
    final time = (m['createdAt'] as Timestamp?)?.toDate();
    final timeText = time == null ? '' : DateFormat('HH:mm').format(time);

    // Tin nhan lich su cuoc goi
    if (m['type'] == 'call') {
      final isVideo = m['isVideo'] == true;
      final missed = (m['text'] as String).contains('nhỡ') ||
          (m['text'] as String).contains('từ chối');
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => _call(isVideo), // bam de goi lai
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: const Color(0xFFF0F2F5), borderRadius: BorderRadius.circular(18)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: missed ? Colors.red : Colors.grey.shade400,
                child: Icon(isVideo ? Icons.videocam : Icons.call, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m['text'], style: const TextStyle(fontWeight: FontWeight.w600)),
                const Text('Bấm để gọi lại', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ]),
          ),
        ),
      );
    }

    final text = m['text'] as String;
    final onlyEmoji = text == '👍';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Tooltip(
        message: timeText,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
          padding: onlyEmoji
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: onlyEmoji
              ? null
              : BoxDecoration(
            color: isMe ? messengerBlue : const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: onlyEmoji ? 40 : 15,
              color: isMe ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Nhắn tin',
                filled: true,
                fillColor: const Color(0xFFF0F2F5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          // Giong Messenger: o trong -> nut 👍, co chu -> nut gui
          IconButton(
            icon: Icon(_hasText ? Icons.send : Icons.thumb_up, color: messengerBlue),
            onPressed: () => _hasText ? _send() : _send('👍'),
          ),
        ]),
      ),
    );
  }
}
