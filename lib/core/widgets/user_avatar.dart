import "package:flutter/material.dart";

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.url,
    required this.fallback,
    this.radius = 18,
  });

  final String url;
  final String fallback;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF5865F2),
      foregroundImage: NetworkImage(url),
      child: Text(
        fallback.substring(0, 1).toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
