import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Render the first Flutter frame BEFORE performing network/native setup.
  runApp(const MessengerCallApp());
}

class MessengerCallApp extends StatefulWidget {
  const MessengerCallApp({super.key});

  @override
  State<MessengerCallApp> createState() => _MessengerCallAppState();
}

class _MessengerCallAppState extends State<MessengerCallApp> {
  late Future<FirebaseApp> _initialization = _initializeFirebase();

  Future<FirebaseApp> _initializeFirebase() => Firebase.initializeApp();

  void _retry() {
    setState(() => _initialization = _initializeFirebase());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messenger Call',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: messengerBlue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
      ),
      home: FutureBuilder<FirebaseApp>(
        future: _initialization,
        builder: (context, initialized) {
          if (initialized.hasError) {
            return _StartupError(
              error: initialized.error.toString(),
              onRetry: _retry,
            );
          }
          if (initialized.connectionState != ConnectionState.done) {
            return const _LoadingScreen(message: 'Đang kết nối Firebase...');
          }
          return StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, auth) {
              if (auth.hasError) {
                return _StartupError(
                  error: auth.error.toString(),
                  onRetry: _retry,
                );
              }
              if (auth.connectionState == ConnectionState.waiting) {
                return const _LoadingScreen(message: 'Đang kiểm tra đăng nhập...');
              }
              return auth.data == null ? const LoginScreen() : const HomeScreen();
            },
          );
        },
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.forum_rounded, size: 70, color: messengerBlue),
        const SizedBox(height: 20),
        const CircularProgressIndicator(),
        const SizedBox(height: 14),
        Text(message),
      ]),
    ),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Không thể khởi động')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Không thể kết nối dịch vụ của ứng dụng.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            SelectableText(error, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ]),
        ),
      ),
    ),
  );
}
