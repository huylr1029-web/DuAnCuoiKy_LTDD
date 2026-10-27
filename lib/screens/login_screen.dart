import 'package:flutter/material.dart';

import '../config.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.isEmpty || _password.text.isEmpty || (_isRegister && (_name.text.isEmpty || _phone.text.isEmpty))) {
      _snack('Vui lòng nhập đầy đủ thông tin');
      return;
    }
    if (_isRegister && _password.text != _confirmPassword.text) {
      _snack('Mật khẩu xác nhận không trùng khớp');
      return;
    }
    if (_isRegister && AuthService.normalizePhone(_phone.text) == null) {
      _snack('Số điện thoại Việt Nam không hợp lệ (ví dụ 0912345678)');
      return;
    }
    setState(() => _loading = true);
    try {
      if (_isRegister) {
        await AuthService().register(_name.text, _email.text, _password.text, _phone.text);
      } else {
        await AuthService().login(_email.text, _password.text);
      }
    } catch (e) {
      _snack(AuthService.message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleLogin() async {
    setState(() => _loading = true);
    try {
      await AuthService().signInWithGoogle();
    } catch (e) {
      if (mounted) _snack(AuthService.message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    String typedEmail = _email.text.trim();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quên mật khẩu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nhập email đã đăng ký để nhận liên kết đặt lại mật khẩu.'),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: typedEmail,
              onChanged: (value) => typedEmail = value,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: _deco('Email của bạn', Icons.email_outlined).copyWith(
                hintText: null,
                labelText: 'Email',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(typedEmail.trim()),
            child: const Text('Gửi liên kết'),
          ),
        ],
      ),
    );
    if (!mounted || email == null) return;
    if (email.isEmpty || !email.contains('@')) {
      _snack('Vui lòng nhập địa chỉ email hợp lệ');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService().sendPasswordResetEmail(email);
      if (mounted) {
        _snack('Nếu email đã đăng ký, bạn sẽ nhận được liên kết đặt lại mật khẩu. Hãy kiểm tra cả thư mục Spam.');
      }
    } catch (e) {
      if (mounted) _snack(AuthService.message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: const Color(0xFFF0F2F5),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.forum_rounded, size: 80, color: messengerBlue),
                const SizedBox(height: 12),
                Text(_isRegister ? 'Tạo tài khoản' : 'Đăng nhập',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 28),
                if (_isRegister) ...[
                  TextField(controller: _name, decoration: _deco('Họ và tên', Icons.person)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: _deco('Số điện thoại (ví dụ 0912345678)', Icons.phone),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _deco('Email', Icons.email)),
                const SizedBox(height: 12),
                TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: _deco('Mật khẩu', Icons.lock)),
                if (_isRegister) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPassword,
                    obscureText: true,
                    decoration: _deco('Xác nhận mật khẩu', Icons.verified_user_outlined),
                  ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _loading ? null : _forgotPassword,
                      child: const Text('Quên mật khẩu?'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: messengerBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isRegister ? 'Đăng ký' : 'Đăng nhập',
                        style: const TextStyle(fontSize: 16)),
                  ),
                ),
                if (!_isRegister) ...[
                  const SizedBox(height: 12),
                  const Text('hoặc'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _googleLogin,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Đăng nhập bằng Google'),
                    ),
                  ),
                ],
                TextButton(
                  onPressed: _loading ? null : () => setState(() => _isRegister = !_isRegister),
                  child: Text(_isRegister
                      ? 'Đã có tài khoản? Đăng nhập'
                      : 'Chưa có tài khoản? Đăng ký'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
