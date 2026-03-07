import 'package:flutter/material.dart';

class RoundAddFab extends StatelessWidget {
  const RoundAddFab({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed ?? () {},
      backgroundColor: const Color(0xFF2F80ED),
      foregroundColor: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      child: const Icon(Icons.add, size: 30),
    );
  }
}
