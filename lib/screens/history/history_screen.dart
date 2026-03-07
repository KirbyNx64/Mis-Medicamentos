import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:mis_medicamentos/db/local/medications_db.dart';
import 'package:mis_medicamentos/services/notifications_service.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text(
          'Historial de notificaciones',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: NotificationsService.instance.historyChangeToken,
          builder: (context, token, _) {
            return FutureBuilder<List<Map<String, Object?>>>(
              key: ValueKey(token),
              future: AppDatabase.instance.getNotificationLogs(limit: 300),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allRows = snapshot.data ?? const <Map<String, Object?>>[];
                final rows = allRows
                    .where((row) {
                      final kind = (row['kind']?.toString() ?? '').trim();
                      return kind == 'shown';
                    })
                    .toList(growable: false);
                if (rows.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aun no hay notificaciones en el historial.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF65758E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    NotificationsService.instance.historyChangeToken.value++;
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: rows.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return _NotificationHistoryCard(row: row);
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _NotificationHistoryCard extends StatelessWidget {
  const _NotificationHistoryCard({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final kind = (row['kind']?.toString() ?? '').trim();
    final medicationForm = row['medication_form']?.toString() ?? '';
    final title = row['title']?.toString() ?? 'Notificacion';
    final body = row['body']?.toString() ?? '';
    final scheduledAt = DateTime.tryParse(
      row['scheduled_at']?.toString() ?? '',
    );
    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final displayTime = scheduledAt ?? createdAt;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconForMedication(medicationForm),
                  weight: _iconWeightForMedication(medicationForm),
                  color: const Color(0xFF2F80ED),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _TypeChip(kind: kind),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF55657D),
              ),
            ),
          ],
          if (displayTime != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 15,
                  color: Color(0xFF6D7E98),
                ),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy', 'es_ES').format(displayTime),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6D7E98),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.access_time_rounded,
                  size: 15,
                  color: Color(0xFF6D7E98),
                ),
                const SizedBox(width: 4),
                Text(
                  DateFormat('h:mm a', 'es_ES').format(displayTime),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6D7E98),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

IconData _iconForMedication(String form) {
  final lower = form.toLowerCase();
  if (lower.contains('tableta') ||
      lower.contains('cápsula') ||
      lower.contains('capsula')) {
    return Symbols.pill;
  }
  if (lower.contains('inyec')) return Icons.vaccines_outlined;
  if (lower.contains('jarabe') || lower.contains('liquid')) {
    return Icons.medication_liquid_outlined;
  }
  if (lower.contains('gota')) return Icons.water_drop_outlined;
  if (lower.contains('crema')) return Icons.sanitizer_outlined;
  if (lower.contains('polvo')) return Icons.grain;
  if (lower.contains('spray')) return Icons.air;
  if (lower.contains('inhalador')) return Icons.air;
  if (lower.contains('parche')) return Icons.healing_outlined;
  if (lower.contains('supositorio')) return Icons.medication_outlined;
  return Icons.medication_outlined;
}

double? _iconWeightForMedication(String form) {
  final lower = form.toLowerCase();
  if (lower.contains('tableta') ||
      lower.contains('cápsula') ||
      lower.contains('capsula')) {
    return 600;
  }
  return null;
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final isScheduled = kind == 'scheduled';
    final bg = isScheduled ? const Color(0xFFE8F6EE) : const Color(0xFFE8F1FF);
    final fg = isScheduled ? const Color(0xFF1A7F4F) : const Color(0xFF2F80ED);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isScheduled ? 'Programada' : 'Mostrada',
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
