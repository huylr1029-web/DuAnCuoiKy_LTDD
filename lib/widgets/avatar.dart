import 'package:flutter/material.dart';

/// Avatar tron co chu cai dau + cham xanh khi dang online (giong Messenger).
class Avatar extends StatelessWidget {
  final String name;
  final double radius;
  final bool online;

  const Avatar({super.key, required this.name, this.radius = 24, this.online = false});

  static const _colors = [
    Color(0xFF0084FF), Color(0xFFA033FF), Color(0xFFFF5C87), Color(0xFFFF8A00),
    Color(0xFF00B67A), Color(0xFF5B6BFF), Color(0xFFE53935), Color(0xFF00897B),
  ];

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final color = _colors[name.hashCode.abs() % _colors.length];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: color,
          child: Text(letter,
              style: TextStyle(
                  color: Colors.white, fontSize: radius * 0.85, fontWeight: FontWeight.w600)),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: radius * 0.6,
              height: radius * 0.6,
              decoration: BoxDecoration(
                color: const Color(0xFF31A24C),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
