class AppUser {
  final String uid;
  final String name;
  final String email;
  final bool online;

  const AppUser({
    required this.uid,
    required this.name,
    this.email = '',
    this.online = false,
  });

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    uid: m['uid'] as String,
    name: (m['name'] as String?) ?? '',
    email: (m['email'] as String?) ?? '',
    online: (m['online'] as bool?) ?? false,
  );
}
