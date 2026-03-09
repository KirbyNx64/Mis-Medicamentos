import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:mis_medicamentos/screens/chat/chat_screen.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key});

  String _currentDateLabel() {
    final now = DateTime.now();
    final formatted = DateFormat("EEEE, d 'de' MMMM", 'es_ES').format(now);
    return '${formatted[0].toUpperCase()}${formatted.substring(1)}';
  }

  @override
  Size get preferredSize => const Size.fromHeight(90);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      toolbarHeight: 90,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      titleSpacing: 12,
      title: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          final userName = (user?.displayName?.trim().isNotEmpty ?? false)
              ? user!.displayName!.trim()
              : 'Buen día';
          final hasPhoto = user?.photoURL?.trim().isNotEmpty ?? false;

          return Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFDCE8FF),
                child: hasPhoto
                    ? ClipOval(
                        child: Image.network(
                          user!.photoURL!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) {
                            return const Icon(
                              Icons.person,
                              size: 24,
                              color: Colors.blue,
                            );
                          },
                        ),
                      )
                    : const Icon(Icons.person, size: 24, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¡Hola, $userName!',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentDateLabel(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ChatScreen()),
                );
              },
              icon: const Icon(
                Symbols.robot_2,
                size: 28,
                weight: 600,
              ),
              iconSize: 22,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              splashColor: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}
