import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';

/// Personal area: the account, its posts, recent calls and a safe sign-out.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Bạn có muốn đăng xuất khỏi tài khoản này không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await AuthService().logout();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể đăng xuất: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Bạn chưa đăng nhập.'));
    final uid = currentUser.uid;
    final db = FirebaseFirestore.instance;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.collection('users').doc(uid).snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data();
            final name = (data?['name'] ?? currentUser.displayName ??
                currentUser.email?.split('@').first ?? 'Người dùng').toString();
            final email = (data?['email'] ?? currentUser.email ?? '').toString();
            return Column(children: [
              CircleAvatar(
                radius: 37,
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(height: 10),
              Text(name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(email, style: Theme.of(context).textTheme.bodyMedium),
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Không tải được hồ sơ: ${snapshot.error}',
                      textAlign: TextAlign.center),
                ),
            ]);
          },
        ),
        const SizedBox(height: 24),
        Text('Bài đăng của tôi', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          // No orderBy: avoids a Firestore composite index requirement.
          stream: db.collection('reels').where('authorId', isEqualTo: uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('Không tải được bài đăng: ${snapshot.error}');
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!.docs.toList()
              ..sort((a, b) => _createdAt(b.data()).compareTo(_createdAt(a.data())));
            if (docs.isEmpty) return const Text('Bạn chưa đăng bài Reels nào.');
            return Column(
              children: docs.map((doc) {
                final post = doc.data();
                final imageUrl = (post['imageUrl'] ?? '').toString();
                final caption = (post['caption'] ?? '').toString();
                final hasMusic = (post['musicUrl'] ?? '').toString().isNotEmpty;
                return Card(
                  child: ListTile(
                    leading: imageUrl.isEmpty
                        ? const Icon(Icons.image_outlined)
                        : SizedBox(
                        width: 54, height: 54,
                        child: Image.network(imageUrl, fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined))),
                    title: Text(caption.isEmpty ? 'Bài đăng không có chú thích' : caption,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${_displayDate(post)}${hasMusic ? ' · Có nhạc' : ''}'),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 24),
        Text('Hoạt động cuộc gọi gần đây', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _RecentCalls(uid: uid),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _signingOut ? null : _signOut,
          icon: _signingOut
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.logout),
          label: Text(_signingOut ? 'Đang đăng xuất...' : 'Đăng xuất tài khoản'),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

int _createdAt(Map<String, dynamic> data) =>
    (data['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

String _displayDate(Map<String, dynamic> data) {
  final value = data['createdAt'];
  return value is Timestamp ? DateFormat('dd/MM/yyyy HH:mm').format(value.toDate()) : 'Mới đăng';
}

class _RecentCalls extends StatelessWidget {
  final String uid;
  const _RecentCalls({required this.uid});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('calls').where('callerId', isEqualTo: uid).snapshots(),
      builder: (context, outgoing) {
        if (outgoing.hasError) return Text('Không tải được cuộc gọi đi: ${outgoing.error}');
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('calls').where('calleeId', isEqualTo: uid).snapshots(),
          builder: (context, incoming) {
            if (incoming.hasError) return Text('Không tải được cuộc gọi đến: ${incoming.error}');
            if (!outgoing.hasData || !incoming.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final calls = <QueryDocumentSnapshot<Map<String, dynamic>>>[
              ...outgoing.data!.docs,
              ...incoming.data!.docs.where(
                      (doc) => !outgoing.data!.docs.any((other) => other.id == doc.id)),
            ]..sort((a, b) => _createdAt(b.data()).compareTo(_createdAt(a.data())));
            if (calls.isEmpty) return const Text('Chưa có hoạt động cuộc gọi.');
            return Column(
              children: calls.take(10).map((doc) {
                final data = doc.data();
                final isOutgoing = data['callerId'] == uid;
                final peer = (data[isOutgoing ? 'calleeName' : 'callerName'] ?? 'Người dùng').toString();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(data['isVideo'] == true ? Icons.videocam_outlined : Icons.call_outlined),
                  title: Text('${isOutgoing ? 'Gọi đi' : 'Gọi đến'} · $peer'),
                  subtitle: Text('${data['status'] ?? 'Không rõ'} · ${_displayDate(data)}'),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}
