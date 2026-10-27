import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

/// Cau truc Firestore:
///   users/{uid}                    : {uid, name, email, online}
///   chats/{chatId}                 : {members:[a,b], names:{a:..,b:..}, lastMessage, updatedAt}
///   chats/{chatId}/messages/{id}   : {senderId, text, type: text|call, isVideo?, createdAt}
class ChatService {
  final _db = FirebaseFirestore.instance;

  User get _me => FirebaseAuth.instance.currentUser!;
  String get myUid => _me.uid;
  String get myName => _me.displayName ?? _me.email ?? 'Tôi';

  /// Hai nguoi luon co cung 1 chatId (sap xep uid theo thu tu).
  static String chatIdOf(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  /// Danh sach tat ca nguoi dung (tru minh).
  Stream<List<AppUser>> otherUsers() => _db.collection('users').snapshots().map(
        (s) => s.docs
        .map((d) => AppUser.fromMap(d.data()))
        .where((u) => u.uid != myUid)
        .toList()
      ..sort((a, b) => (b.online ? 1 : 0) - (a.online ? 1 : 0)),
  );

  Stream<AppUser?> userStream(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? AppUser.fromMap(d.data()!) : null);

  /// Cac doan chat cua toi, moi nhat len dau.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> myChats() => _db
      .collection('chats')
      .where('members', arrayContains: myUid)
      .snapshots()
      .map((s) {
    final docs = s.docs.toList();
    docs.sort((a, b) {
      final ta = a.data()['updatedAt'] as Timestamp?;
      final tb = b.data()['updatedAt'] as Timestamp?;
      return (tb?.millisecondsSinceEpoch ?? 1 << 62)
          .compareTo(ta?.millisecondsSinceEpoch ?? 1 << 62);
    });
    return docs;
  });

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String chatId) => _db
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots();

  Future<void> sendMessage(AppUser peer, String text,
      {String type = 'text', bool isVideo = false}) async {
    final chatId = chatIdOf(myUid, peer.uid);
    final chatRef = _db.collection('chats').doc(chatId);
    final batch = _db.batch();
    batch.set(chatRef.collection('messages').doc(), {
      'senderId': myUid,
      'text': text,
      'type': type,
      'isVideo': isVideo,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      chatRef,
      {
        'members': [myUid, peer.uid],
        'names': {myUid: myName, peer.uid: peer.name},
        'lastMessage': type == 'call' ? '📞 $text' : text,
        'lastSenderId': myUid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Ghi lich su cuoc goi vao doan chat (giong Messenger).
  Future<void> sendCallLog(AppUser peer,
      {required bool isVideo, required String outcome, int? seconds}) {
    final kind = isVideo ? 'Cuộc gọi video' : 'Cuộc gọi thoại';
    String text;
    if (seconds != null) {
      final m = (seconds ~/ 60).toString().padLeft(2, '0');
      final s = (seconds % 60).toString().padLeft(2, '0');
      text = '$kind · $m:$s';
    } else if (outcome == 'rejected') {
      text = '$kind bị từ chối';
    } else {
      text = '$kind nhỡ';
    }
    return sendMessage(peer, text, type: 'call', isVideo: isVideo);
  }

  Future<void> setOnline(bool online) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).set(
      {'online': online, 'lastSeen': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }
}
