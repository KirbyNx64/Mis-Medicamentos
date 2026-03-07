import 'package:flutter/material.dart';
import 'package:mis_medicamentos/db/local/medications_db.dart';

class HomeProgressCard extends StatelessWidget {
  const HomeProgressCard({super.key, this.refreshToken = 0});

  final int refreshToken;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DailyProgress>(
      key: ValueKey(refreshToken),
      future: _loadDailyProgress(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const _DailyProgress(0, 0);
        final completed = data.completed;
        final total = data.total;
        final progress = total == 0 ? 0.0 : completed / total;
        final percentage = (progress * 100).round();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Progreso de hoy',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '$percentage%',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2F80ED),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  borderRadius: BorderRadius.circular(999),
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 20,
                  backgroundColor: const Color(0xFFDDE7F4),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF2F80ED),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '$completed de $total tomas completadas',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF767676),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<_DailyProgress> _loadDailyProgress() async {
  final db = AppDatabase.instance;
  final medications = await db.getMedications();
  final logs = await db.getDoseLogs(status: 'taken');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final scheduleKeys = <String>{};

  for (final medication in medications) {
    final status = medication['status']?.toString() ?? 'active';
    if (status != 'active') continue;

    final medicationId = medication['id'];
    if (medicationId is! int) continue;

    final schedules = await db.getMedicationSchedules(medicationId);
    final scheduleMinutes = <int>[];
    for (final schedule in schedules) {
      final timeText = schedule['time_of_day']?.toString();
      if (timeText == null || !_isValidHourMinute(timeText)) continue;
      final parts = timeText.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      scheduleMinutes.add(hour * 60 + minute);
    }
    if (scheduleMinutes.isEmpty) continue;
    scheduleMinutes.sort();

    final firstDoseAtRaw = medication['first_dose_at']?.toString().trim();
    DateTime? firstDoseAt = (firstDoseAtRaw == null || firstDoseAtRaw.isEmpty)
        ? null
        : DateTime.tryParse(firstDoseAtRaw);
    if (firstDoseAt == null) {
      final startDateRaw = medication['start_date']?.toString().trim();
      final startDate = (startDateRaw == null || startDateRaw.isEmpty)
          ? null
          : DateTime.tryParse(startDateRaw);
      if (startDate != null) {
        final firstMinute = scheduleMinutes.first;
        firstDoseAt = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
          firstMinute ~/ 60,
          firstMinute % 60,
        );
      }
    }
    if (firstDoseAt == null) continue;

    final endDateRaw = medication['end_date']?.toString().trim();
    final endDate = (endDateRaw == null || endDateRaw.isEmpty)
        ? null
        : DateTime.tryParse(endDateRaw);
    final endDateExclusive = endDate == null
        ? null
        : DateTime(endDate.year, endDate.month, endDate.day + 1);
    if (endDateExclusive != null && !today.isBefore(endDateExclusive)) {
      continue;
    }

    final intakeQtyRaw =
        (medication['intake_quantity'] as num?)?.toDouble() ?? 1.0;
    final intakeQty = intakeQtyRaw <= 0 ? 1 : intakeQtyRaw.ceil();
    final stockInitial = (medication['stock_initial'] as num?)?.toDouble();
    final totalDoses = stockInitial == null
        ? null
        : (stockInitial / intakeQty).floor();
    if (totalDoses != null && totalDoses <= 0) continue;

    for (final minute in scheduleMinutes) {
      final scheduledAt = DateTime(
        today.year,
        today.month,
        today.day,
        minute ~/ 60,
        minute % 60,
      );
      if (scheduledAt.isBefore(firstDoseAt)) continue;
      if (endDateExclusive != null && !scheduledAt.isBefore(endDateExclusive)) {
        continue;
      }

      if (totalDoses != null) {
        final ordinal = _doseOrdinalForSchedule(
          scheduleMinutes: scheduleMinutes,
          firstDoseAt: firstDoseAt,
          scheduledAt: scheduledAt,
        );
        if (ordinal > totalDoses) continue;
      }

      scheduleKeys.add('${medicationId}_${_dateTimeKey(scheduledAt)}');
    }
  }

  final takenKeys = <String>{};
  for (final log in logs) {
    final medicationId = log['medication_id'];
    final scheduledAtRaw = log['scheduled_at']?.toString();
    if (medicationId is! int || scheduledAtRaw == null) continue;

    final scheduledAt = DateTime.tryParse(scheduledAtRaw);
    if (scheduledAt == null || !_isSameDay(scheduledAt, now)) continue;

    final key = '${medicationId}_${_dateTimeKey(scheduledAt)}';
    if (scheduleKeys.contains(key)) {
      takenKeys.add(key);
    }
  }

  return _DailyProgress(takenKeys.length, scheduleKeys.length);
}

bool _isValidHourMinute(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return false;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  return hour != null &&
      minute != null &&
      hour >= 0 &&
      hour < 24 &&
      minute >= 0 &&
      minute < 60;
}

int _doseOrdinalForSchedule({
  required List<int> scheduleMinutes,
  required DateTime firstDoseAt,
  required DateTime scheduledAt,
}) {
  final firstDay = DateTime(
    firstDoseAt.year,
    firstDoseAt.month,
    firstDoseAt.day,
  );
  final currentDay = DateTime(
    scheduledAt.year,
    scheduledAt.month,
    scheduledAt.day,
  );
  final firstDoseMinute = (firstDoseAt.hour * 60) + firstDoseAt.minute;
  final currentMinute = (scheduledAt.hour * 60) + scheduledAt.minute;

  if (currentDay.isBefore(firstDay)) return 0;

  final dosesOnFirstDay = scheduleMinutes
      .where((m) => m >= firstDoseMinute)
      .length;
  final dosesPerFullDay = scheduleMinutes.length;
  final dayDiff = currentDay.difference(firstDay).inDays;

  if (dayDiff == 0) {
    return scheduleMinutes
        .where((m) => m >= firstDoseMinute && m <= currentMinute)
        .length;
  }

  final dosesBeforeCurrentDay =
      dosesOnFirstDay + ((dayDiff - 1) * dosesPerFullDay);
  final dosesOnCurrentDayUntilNow = scheduleMinutes
      .where((m) => m <= currentMinute)
      .length;
  return dosesBeforeCurrentDay + dosesOnCurrentDayUntilNow;
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _dateTimeKey(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}

class _DailyProgress {
  const _DailyProgress(this.completed, this.total);

  final int completed;
  final int total;
}
