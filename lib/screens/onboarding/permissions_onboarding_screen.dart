import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mis_medicamentos/services/notifications_service.dart';

class PermissionsOnboardingScreen extends StatefulWidget {
  const PermissionsOnboardingScreen({super.key, required this.onContinue});

  final Future<void> Function() onContinue;

  @override
  State<PermissionsOnboardingScreen> createState() =>
      _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState
    extends State<PermissionsOnboardingScreen> {
  bool _isRequestingNotifications = false;
  bool _isRequestingAlarms = false;
  bool? _notificationsGranted;
  bool? _alarmsGranted;
  bool _isContinuing = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _canContinue {
    if (!_isAndroid) return true;
    return _notificationsGranted != null && _alarmsGranted != null;
  }

  Future<void> _requestNotificationsPermission() async {
    if (_isRequestingNotifications) return;
    setState(() => _isRequestingNotifications = true);
    try {
      final granted = await NotificationsService.instance
          .requestNotificationsPermission();
      if (!mounted) return;
      setState(() => _notificationsGranted = granted);
    } finally {
      if (mounted) {
        setState(() => _isRequestingNotifications = false);
      }
    }
  }

  Future<void> _requestAlarmsPermission() async {
    if (_isRequestingAlarms) return;
    setState(() => _isRequestingAlarms = true);
    try {
      final granted = await NotificationsService.instance
          .requestExactAlarmsPermission();
      if (!mounted) return;
      setState(() => _alarmsGranted = granted);
    } finally {
      if (mounted) {
        setState(() => _isRequestingAlarms = false);
      }
    }
  }

  Future<void> _continue() async {
    if (_isContinuing || !_canContinue) return;
    setState(() => _isContinuing = true);
    try {
      await widget.onContinue();
    } finally {
      if (mounted) {
        setState(() => _isContinuing = false);
      }
    }
  }

  Widget _statusChip(bool? granted) {
    if (granted == null) {
      return const SizedBox.shrink();
    }
    final ok = granted == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE9F7EF) : const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        ok ? 'Concedido' : 'No concedido',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: ok ? const Color(0xFF198754) : const Color(0xFFB23434),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _permissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLoading,
    required VoidCallback? onTap,
    required bool? granted,
  }) {
    final shouldShowAllowButton = granted != true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE7F5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFDCE8F8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF2F80ED), size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2740),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF5F7190),
                  ),
                ),
                if (granted != null) ...[
                  const SizedBox(height: 8),
                  _statusChip(granted),
                ],
              ],
            ),
          ),
          if (shouldShowAllowButton) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: isLoading ? null : onTap,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2F80ED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                minimumSize: const Size(110, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF2F80ED),
                      ),
                    )
                  : const Text('Permitir'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF2F80ED),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F6FF),
        body: Stack(
          children: [
            Container(
              height: 280,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2F80ED), Color(0xFF6FA9F4)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 18,
                20,
                20,
              ),
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 3),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icon/icon.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE1EAF7)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140E386B),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Activa tus recordatorios',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isAndroid
                              ? 'Concede estos permisos para enviar avisos de dosis a tiempo.'
                              : 'En este dispositivo no se requiere configuración adicional.',
                          style: const TextStyle(
                            color: Color(0xFF5F7190),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _permissionTile(
                          icon: Icons.notifications_active_rounded,
                          title: 'Notificaciones',
                          subtitle: 'Mostrar recordatorios en tu teléfono.',
                          isLoading: _isRequestingNotifications,
                          onTap: _isAndroid
                              ? _requestNotificationsPermission
                              : null,
                          granted: _notificationsGranted,
                        ),
                        const SizedBox(height: 10),
                        _permissionTile(
                          icon: Icons.alarm_on_rounded,
                          title: 'Alarmas exactas',
                          subtitle: 'Ejecutar recordatorios en hora exacta.',
                          isLoading: _isRequestingAlarms,
                          onTap: _isAndroid ? _requestAlarmsPermission : null,
                          granted: _alarmsGranted,
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: (_isContinuing || !_canContinue)
                                ? null
                                : _continue,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2F80ED),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            child: _isContinuing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF2F80ED),
                                    ),
                                  )
                                : Text(
                                    _canContinue
                                        ? 'Continuar'
                                        : 'Conceder permisos',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
