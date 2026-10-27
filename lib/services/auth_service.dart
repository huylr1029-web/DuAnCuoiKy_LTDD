import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  static String? normalizePhone(String raw) {
    final value = raw.replaceAll(RegExp(r'[\s.()-]'), '');
    String digits;
    if (RegExp(r'^0[35789][0-9]{8}$').hasMatch(value)) {
      digits = value.substring(1);
    } else if (RegExp(r'^\+84[35789][0-9]{8}$').hasMatch(value)) {
      digits = value.substring(3);
    } else if (RegExp(r'^84[35789][0-9]{8}$').hasMatch(value)) {
      digits = value.substring(2);
    } else {
      return null;
    }
    return '+84$digits';
  }

  Future<void> register(String name, String email, String password, String phone) async {
    final normalized = normalizePhone(phone);
    if (normalized == null) {
      throw StateError('Số điện thoại không hợp lệ');
    }
    if (name.trim().isEmpty) {
      throw StateError('Vui lòng nhập họ tên');
    }

    // Firebase Auth is required before Firestore's signed-in-only reads.
    // Do not query /users before creating/authenticating this user.
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;
    try {
      // This is a convenience duplicate check, not a globally atomic uniqueness
      // guarantee. A production phone directory needs a protected unique index.
      final existing = await _db.collection('users')
          .where('phone', isEqualTo: normalized)
          .limit(1)
          .get();
      if (existing.docs.any((doc) => doc.id != user.uid)) {
        throw StateError('Số điện thoại đã được đăng ký. Hãy dùng số khác.');
      }
      await user.updateDisplayName(name.trim());
      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name.trim(),
        'email': email.trim(),
        'phone': normalized,
        'online': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      // Never silently claim registration succeeded without a Firestore profile.
      // The Auth user might already exist: tell the user how to recover.
      throw StateError(
        'Đã tạo tài khoản Authentication nhưng chưa hoàn tất hồ sơ: '
            '${message(error)}. Hãy đăng nhập lại để đồng bộ hoặc liên hệ quản trị viên.',
      );
    }
  }

  Future<void> login(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    await ensureUserProfile(credential.user!);
  }

  Future<void> ensureUserProfile(User user) async {
    final ref = _db.collection('users').doc(user.uid);
    final snapshot = await ref.get();
    final email = user.email ?? '';
    final fallbackName = email.contains('@') ? email.split('@').first : 'Người dùng';
    await ref.set({
      'uid': user.uid,
      'name': user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (snapshot.data()?['name'] ?? fallbackName),
      'email': email,
      'online': true,
      'lastSeen': FieldValue.serverTimestamp(),
      if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    await google.initialize();
    if (!google.supportsAuthenticate()) {
      throw StateError('Thiết bị này chưa hỗ trợ đăng nhập Google theo cách này.');
    }
    final account = await google.authenticate();
    final googleAuth = account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw StateError('Google không trả về ID token. Hãy kiểm tra cấu hình OAuth.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result = await _auth.signInWithCredential(credential);
    if (result.user != null) {
      await ensureUserProfile(result.user!);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final address = email.trim();
    if (address.isEmpty || !address.contains('@')) {
      throw StateError('Vui lòng nhập địa chỉ email hợp lệ');
    }
    await _auth.sendPasswordResetEmail(email: address);
  }

  Future<void> logout() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set(
            {'online': false}, SetOptions(merge: true));
      } catch (_) {
        // Network failures must not prevent sign-out.
      }
    }
    await _auth.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Email/password users may not have a Google session.
    }
  }

  static String message(Object e) {
    if (e is FirebaseException && e.code == 'permission-denied') {
      return 'Firestore từ chối quyền truy cập. Kiểm tra Rules và tài khoản đăng nhập';
    }
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email': return 'Email không hợp lệ';
        case 'too-many-requests': return 'Bạn đã yêu cầu quá nhiều lần. Vui lòng thử lại sau';
        case 'network-request-failed': return 'Không có kết nối mạng. Hãy kiểm tra Internet';
        case 'email-already-in-use': return 'Email đã được đăng ký';
        case 'weak-password': return 'Mật khẩu phải có ít nhất 6 ký tự';
        case 'operation-not-allowed': return 'Firebase chưa bật đăng ký Email/Password';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential': return 'Sai email hoặc mật khẩu';
      }
      return e.message ?? e.code;
    }
    if (e is GoogleSignInException) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return 'Đã hủy đăng nhập bằng Google';
      }
      return 'Đăng nhập Google thất bại: ${e.description ?? e.code.name}. Kiểm tra SHA-1/SHA-256 và google-services.json.';
    }
    if (e is StateError) return e.message.toString();
    return e.toString();
  }
}
