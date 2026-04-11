import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Displays a circular avatar backed by a base64 photo data URI.
/// Falls back to coloured initials when [photo] is null or invalid.
class UserAvatar extends StatelessWidget {
  final String? photo;
  final String name;
  final double radius;
  final Color? backgroundColor;

  const UserAvatar({
    super.key,
    required this.name,
    this.photo,
    this.radius = 24,
    this.backgroundColor,
  });

  String _initials() {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Uint8List? _decodePhoto() {
    final p = photo;
    if (p == null || p.isEmpty) return null;
    try {
      final data = p.contains(',') ? p.split(',').last : p;
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decodePhoto();
    if (bytes != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: MemoryImage(bytes),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.primary,
      child: Text(
        _initials(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.6,
        ),
      ),
    );
  }
}
