import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _phone = TextEditingController();
  final _db = FirebaseFirestore.instance;
  String get uid => FirebaseAuth.instance.currentUser!.uid;
  bool _busy = false;
  Map<String, dynamic>? _found;
  String? _result;

  @override
  void dispose() { _phone.dispose(); super.dispose(); }

  Future<void> _search() async {
    final phone = AuthService.normalizePhone(_phone.text);
    if (phone == null) {
      setState(() { _found = null; _result = 'Nhập số Việt Nam hợp lệ (09..., 03..., +84...).'; });
      return;
    }
    setState(() { _busy = true; _result = null; _found = null; });
    try {
      final result = await _db.collection('users').where('phone', isEqualTo: phone).limit(2).get();
      if (!mounted) return;
      final docs = result.docs.where((doc) => doc.id != uid).toList();
      setState(() {
        _found = docs.isEmpty ? null : {...docs.first.data(), 'uid': docs.first.id};
        _result = docs.isEmpty ? 'Không tìm thấy tài khoản khác với số điện thoại này.' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _result = 'Không tìm được tài khoản: $e');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _invite() async {
    final found = _found;
    if (found == null) return;
    final target = found['uid'] as String;
    final myName = FirebaseAuth.instance.currentUser?.displayName ?? 'Người dùng';
    setState(() => _busy = true);
    try {
      final id = '${uid}_$target';
      final reverse = '${target}_$uid';
      final reverseDoc = await _db.collection('friend_requests').doc(reverse).get();
      if (reverseDoc.exists && reverseDoc.data()?['status'] == 'pending') {
        if (mounted) setState(() => _result = 'Người này đã gửi lời mời cho bạn. Hãy chấp nhận bên dưới.');
        return;
      }
      final ref = _db.collection('friend_requests').doc(id);
      final current = await ref.get();
      if (current.exists) {
        if (mounted) setState(() => _result = current.data()?['status'] == 'accepted'
            ? 'Hai bạn đã là bạn bè.' : 'Đã gửi lời mời trước đó.');
        return;
      }
      await ref.set({
        'senderId': uid, 'receiverId': target,
        'senderName': myName, 'receiverName': found['name'] ?? 'Người dùng',
        'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _result = 'Đã gửi lời mời kết bạn.');
    } catch (e) {
      if (mounted) setState(() => _result = 'Không thể gửi lời mời: $e');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _respond(QueryDocumentSnapshot<Map<String, dynamic>> doc, String status) async {
    try {
      await doc.reference.update({'status': status, 'respondedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _requests({required bool incoming, bool accepted = false}) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _db.collection('friend_requests')
        .where(incoming ? 'receiverId' : 'senderId', isEqualTo: uid).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Text('Không tải được lời mời: ${snapshot.error}');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final docs = snapshot.data!.docs.where((doc) => doc.data()['status'] == (accepted || !incoming ? 'accepted' : 'pending')).toList();
      if (docs.isEmpty) return Text(incoming ? 'Không có lời mời đang chờ.' : 'Chưa có bạn bè.');
      return Column(children: docs.map((doc) {
        final data = doc.data();
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text((data[incoming ? 'senderName' : 'receiverName'] ?? 'Người dùng').toString()),
          subtitle: Text(incoming && !accepted ? 'Muốn kết bạn với bạn' : 'Đã kết bạn'),
          trailing: incoming && !accepted ? Wrap(spacing: 4, children: [
            TextButton(onPressed: () => _respond(doc, 'rejected'), child: const Text('Từ chối')),
            FilledButton(onPressed: () => _respond(doc, 'accepted'), child: const Text('Đồng ý')),
          ]) : IconButton(
            tooltip: 'Nhắn tin', icon: const Icon(Icons.chat_outlined),
            onPressed: () async {
              final user = await _db.collection('users').doc(incoming ? data['senderId'] : data['receiverId']).get();
              if (!context.mounted || !user.exists) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) =>
                  ChatScreen(peer: AppUser.fromMap(user.data()!))));
            },
          ),
        );
      }).toList());
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tìm và thêm bạn')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Tìm tài khoản bằng số điện thoại đã nhập khi đăng ký.'),
      const SizedBox(height: 12),
      TextField(controller: _phone, keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: 'Số điện thoại',
              hintText: '0912345678', border: const OutlineInputBorder(),
              suffixIcon: IconButton(onPressed: _busy ? null : _search,
                  icon: const Icon(Icons.search)))),
      const SizedBox(height: 10),
      FilledButton.icon(onPressed: _busy ? null : _search,
          icon: const Icon(Icons.person_search), label: const Text('Tìm bạn')),
      if (_busy) const LinearProgressIndicator(),
      if (_result != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_result!)),
      if (_found != null) Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text((_found!['name'] ?? 'Người dùng').toString()),
        subtitle: const Text('Tài khoản đã đăng ký'),
        trailing: FilledButton(onPressed: _busy ? null : _invite,
            child: const Text('Kết bạn')),
      )),
      const SizedBox(height: 24),
      const Text('Lời mời kết bạn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      _requests(incoming: true),
      const SizedBox(height: 18),
      const Text('Bạn bè', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      _requests(incoming: false),
      _requests(incoming: true, accepted: true),
    ]),
  );
}
