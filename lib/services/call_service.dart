import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

/// Bao hieu cuoc goi (signaling) qua Firestore.
///   calls/{callId} : {callerId, callerName, calleeId, calleeName, isVideo,
///                     status: ringing | accepted | rejected | ended | missed, createdAt}
/// callId cung chinh la ten kenh (channel) Agora ma hai ben cung tham gia.
class CallService {
  final _db = FirebaseFirestore.instance;

  /// Dang trong cuoc goi hay khong (de bao "ban" khi co nguoi khac goi toi).
  static bool inCall = false;

  Future<String> startCall({required AppUser peer, required bool isVideo}) async {
    final me = FirebaseAuth.instance.currentUser!;
    final ref = _db.collection('calls').doc();
    await ref.set({
      'callerId': me.uid,
      'callerName': me.displayName ?? me.email ?? 'Ai đó',
      'calleeId': peer.uid,
      'calleeName': peer.name,
      'isVideo': isVideo,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Cac cuoc goi dang do chuong toi minh.
  Stream<QuerySnapshot<Map<String, dynamic>>> incomingCalls(String myUid) => _db
      .collection('calls')
      .where('calleeId', isEqualTo: myUid)
      .where('status', isEqualTo: 'ringing')
      .snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> callStream(String callId) =>
      _db.collection('calls').doc(callId).snapshots();

  Future<void> updateStatus(String callId, String status) =>
      _db.collection('calls').doc(callId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
