import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';
import 'incoming_call_screen.dart';
import 'calls_tab.dart';
import 'reels_tab.dart';
import 'profile_tab.dart';
import 'friends_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _chat = ChatService();
  StreamSubscription? _incomingSub;
  bool _showingIncoming = false;
  int _selectedTab = 0;
  Object? _profileError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncProfile();
    _listenIncomingCalls();
  }

  Future<void> _syncProfile() async {
    try {
      final me = FirebaseAuth.instance.currentUser;
      if (me != null) await AuthService().ensureUserProfile(me);
      if (mounted) setState(() => _profileError = null);
    } catch (error) {
      if (mounted) setState(() => _profileError = error);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingSub?.cancel();
    super.dispose();
  }

  /// Cap nhat trang thai online khi mo / thoat app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _chat.setOnline(true);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _chat.setOnline(false);
    }
  }

  /// Lang nghe cuoc goi den -> bat man hinh do chuong.
  void _listenIncomingCalls() {
    _incomingSub = CallService().incomingCalls(_chat.myUid).listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;

        // Bo qua cuoc goi cu (qua 40 giay) con sot lai
        final created = (data['createdAt'] as Timestamp?)?.toDate();
        if (created != null && DateTime.now().difference(created).inSeconds > 40) {
          CallService().updateStatus(change.doc.id, 'missed');
          continue;
        }
        // Dang ban -> tu choi
        if (CallService.inCall || _showingIncoming) {
          CallService().updateStatus(change.doc.id, 'rejected');
          continue;
        }
        _showingIncoming = true;
        navigatorKey.currentState!
            .push(MaterialPageRoute(
            builder: (_) => IncomingCallScreen(callId: change.doc.id, data: data)))
            .then((_) => _showingIncoming = false);
      }
    }, onError: (Object error) {
      debugPrint("Không thể nghe cuộc gọi đến: $error");
    });
  }

  void _openChat(AppUser peer) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(['Đoạn chat', 'Cuộc gọi', 'Reels', 'Cá nhân'][_selectedTab],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 26)),
        actions: [
          if (_selectedTab == 0)
            IconButton(
              tooltip: 'Tìm và thêm bạn bằng số điện thoại',
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FriendsScreen())),
            ),
        ],

      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call), label: 'Cuộc gọi'),
          NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library), label: 'Reels'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Cá nhân'),
        ],
      ),
      body: IndexedStack(index: _selectedTab, children: [
        _buildChatTab(),
        const CallsTab(),
        const ReelsTab(),
        const ProfileTab(),
      ]),
    );
  }

  Widget _buildChatTab() => Column(
    children: [
      if (_profileError != null)
        MaterialBanner(
          content: Text('Không đồng bộ được tài khoản: $_profileError'),
          actions: [TextButton(onPressed: _syncProfile, child: const Text('Thử lại'))],
        ),
      // Hang ngang nguoi dung (giong thanh "dang hoat dong" cua Messenger)
      SizedBox(
        height: 104,
        child: StreamBuilder<List<AppUser>>(
          stream: _chat.otherUsers(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text("Không tải được người dùng: ${snap.error}",
                    textAlign: TextAlign.center),
              ));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final users = snap.data ?? [];
            if (users.isEmpty) {
              return const Center(
                  child: Padding(padding: EdgeInsets.all(12), child: Text(
                      'Chưa tìm thấy tài khoản khác trong Firestore. Hãy đăng nhập tài khoản còn lại ít nhất một lần trên bản ứng dụng này.',
                      textAlign: TextAlign.center)));
            }
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              itemCount: users.length,
              itemBuilder: (_, i) {
                final u = users[i];
                return GestureDetector(
                  onTap: () => _openChat(u),
                  child: SizedBox(
                    width: 76,
                    child: Column(children: [
                      Avatar(name: u.name, radius: 28, online: u.online),
                      const SizedBox(height: 6),
                      Text(u.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
      const Divider(height: 1),
      // Danh sach doan chat
      Expanded(
        child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: _chat.myChats(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Lỗi: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final chats = snap.data!;
            if (chats.isEmpty) {
              return const Center(child: Text('Chọn một người ở trên để bắt đầu nhắn tin'));
            }
            return ListView.builder(
              itemCount: chats.length,
              itemBuilder: (_, i) {
                final d = chats[i].data();
                final members = List<String>.from(d['members'] ?? []);
                final peerId = members.firstWhere((m) => m != _chat.myUid,
                    orElse: () => _chat.myUid);
                final names = Map<String, dynamic>.from(d['names'] ?? {});
                final peerName = (names[peerId] as String?) ?? 'Người dùng';
                final isMine = d['lastSenderId'] == _chat.myUid;
                final time = (d['updatedAt'] as Timestamp?)?.toDate();

                return StreamBuilder<AppUser?>(
                  stream: _chat.userStream(peerId),
                  builder: (context, us) => ListTile(
                    leading: Avatar(name: peerName, online: us.data?.online ?? false),
                    title: Text(peerName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${isMine ? 'Bạn: ' : ''}${d['lastMessage'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: time == null
                        ? null
                        : Text(_fmt(time),
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    onTap: () => _openChat(us.data ?? AppUser(uid: peerId, name: peerName)),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );

  String _fmt(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return DateFormat('HH:mm').format(t);
    }
    return DateFormat('dd/MM').format(t);
  }
}
