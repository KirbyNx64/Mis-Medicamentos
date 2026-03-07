import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:mis_medicamentos/db/local/medications_db.dart';
import 'package:mis_medicamentos/screens/home/home_calendar_screen.dart';
import 'package:mis_medicamentos/services/notifications_service.dart';

class HomeUpcomingDosesSection extends StatefulWidget {
  const HomeUpcomingDosesSection({
    super.key,
    this.onDoseMarked,
    this.refreshToken = 0,
  });

  final VoidCallback? onDoseMarked;
  final int refreshToken;

  @override
  State<HomeUpcomingDosesSection> createState() =>
      _HomeUpcomingDosesSectionState();
}

class _HomeUpcomingDosesSectionState extends State<HomeUpcomingDosesSection> {
  late Future<_UpcomingDoseData> _dataFuture;
  bool _isMarkingDose = false;
  String? _selectedDoseKey;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(covariant HomeUpcomingDosesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      setState(() {
        _selectedDoseKey = null;
        _dataFuture = _loadData();
      });
    }
  }

  Future<void> _markDoseAsTaken(_DoseEntry entry) async {
    if (_isMarkingDose) return;
    final shouldProceed = await _showConfirmMarkDoseDialog(entry);
    if (shouldProceed != true) return;

    setState(() => _isMarkingDose = true);
    try {
      final marked = await AppDatabase.instance.markDoseAsTaken(
        medicationId: entry.medicationId,
        scheduledAt: entry.scheduledAt,
        intakeQuantity: entry.intakeQuantity,
      );

      if (!mounted) return;
      if (!marked) {
        await _showMessageDialog('Esa toma ya estaba marcada');
      }
      setState(() {
        _dataFuture = _loadData();
      });
      widget.onDoseMarked?.call();
    } catch (_) {
      if (!mounted) return;
      await _showMessageDialog('No se pudo marcar la toma');
    } finally {
      if (mounted) {
        setState(() => _isMarkingDose = false);
      }
    }
  }

  Future<void> _showMessageDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Aceptar',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showConfirmMarkDoseDialog(_DoseEntry entry) async {
    if (!mounted) return false;
    final actionLabel = _doseActionLabelForForm(entry.form);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            'Confirmar $actionLabel',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            '¿Confirmar $actionLabel de "${entry.name}" a las ${_to12h(entry.scheduledAt)}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.black),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2F80ED),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_UpcomingDoseData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const _SectionError();
        }

        final data = snapshot.data ?? const _UpcomingDoseData([], []);
        final upcoming = data.upcoming;
        final taken = data.taken;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              onOpenCalendar: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HomeCalendarScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            if (upcoming.isEmpty && taken.isEmpty)
              const _EmptyUpcomingCard()
            else ...[
              for (var index = 0; index < upcoming.length; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                _DoseCard(
                  entry: upcoming[index],
                  highlighted: _selectedDoseKey == upcoming[index].key,
                  showOverdueBadge: upcoming[index].isOverdue,
                  showNowBadge: upcoming[index].isNow,
                  showDoneButton: _selectedDoseKey == upcoming[index].key,
                  isMarking:
                      _isMarkingDose && _selectedDoseKey == upcoming[index].key,
                  onMarkDone: _selectedDoseKey == upcoming[index].key
                      ? () => _markDoseAsTaken(upcoming[index])
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedDoseKey = upcoming[index].key;
                    });
                  },
                ),
              ],
              for (var index = 0; index < taken.length; index++) ...[
                const SizedBox(height: 10),
                _TakenDoseCard(entry: taken[index]),
              ],
            ],
          ],
        );
      },
    );
  }

  Future<_UpcomingDoseData> _loadData() async {
    final db = AppDatabase.instance;
    final medications = await db.getMedications();
    final logs = await db.getDoseLogs(status: 'taken');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final medicationIds = medications
        .map((m) => m['id'])
        .whereType<int>()
        .toList(growable: false);
    final photoPaths = await db.getMedicationImageAttachmentPaths(
      medicationIds,
    );

    final takenByKey = <String, DateTime>{};
    for (final log in logs) {
      final medicationId = log['medication_id'];
      final scheduledAtRaw = log['scheduled_at']?.toString();
      if (medicationId is! int || scheduledAtRaw == null) continue;

      final scheduledAt = DateTime.tryParse(scheduledAtRaw);
      if (scheduledAt == null) continue;

      final takenAt =
          DateTime.tryParse(log['taken_at']?.toString() ?? '') ?? scheduledAt;
      final key = '${medicationId}_${_dateTimeKey(scheduledAt)}';
      takenByKey[key] = takenAt;
    }

    final upcoming = <_DoseEntry>[];
    final taken = <_DoseEntry>[];

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
        if (endDateExclusive != null &&
            !scheduledAt.isBefore(endDateExclusive)) {
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

        final key = '${medicationId}_${_dateTimeKey(scheduledAt)}';
        final takenAt = takenByKey[key];
        final entry = _DoseEntry(
          medicationId: medicationId,
          name: medication['name']?.toString() ?? 'Medicamento',
          doseAmount: (medication['dose_amount'] as num?)?.toDouble() ?? 0,
          doseUnit: medication['dose_unit']?.toString() ?? '',
          form: medication['form']?.toString() ?? 'dosis',
          imagePath: photoPaths[medicationId],
          route: medication['route']?.toString() ?? 'oral',
          intakeQuantity: intakeQty,
          scheduledAt: scheduledAt,
          takenAt: takenAt,
          isOverdue: scheduledAt.isBefore(now),
          isNow:
              !scheduledAt.isBefore(now) &&
              (scheduledAt.difference(now).inMinutes).abs() <= 20,
        );

        if (takenAt != null) {
          taken.add(entry);
        } else {
          upcoming.add(entry);
        }
      }
    }

    upcoming.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    taken.sort((a, b) {
      final timeA = a.takenAt ?? a.scheduledAt;
      final timeB = b.takenAt ?? b.scheduledAt;
      return timeB.compareTo(timeA);
    });

    await NotificationsService.instance.syncTodayDoseNotifications(
      doses: upcoming
          .map(
            (entry) => DoseNotificationSchedule(
              key: entry.key,
              medicationName: entry.name,
              medicationForm: entry.form,
              scheduledAt: entry.scheduledAt,
            ),
          )
          .toList(growable: false),
    );

    return _UpcomingDoseData(upcoming, taken);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.onOpenCalendar});

  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Próximas...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        InkWell(
          onTap: onOpenCalendar,
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              'Ver calendario',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2F80ED),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({
    required this.entry,
    this.highlighted = false,
    this.showOverdueBadge = false,
    this.showNowBadge = false,
    this.showDoneButton = false,
    this.isMarking = false,
    this.onMarkDone,
    this.onTap,
  });

  final _DoseEntry entry;
  final bool highlighted;
  final bool showOverdueBadge;
  final bool showNowBadge;
  final bool showDoneButton;
  final bool isMarking;
  final VoidCallback? onMarkDone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: highlighted
                ? const [
                    BoxShadow(
                      color: Color(0x16000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
            border: Border.all(
              color: highlighted ? const Color(0xFF2F80ED) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              _IconBox(form: entry.form, imagePath: entry.imagePath),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1C2A43),
                            ),
                          ),
                        ),
                        if (showOverdueBadge || showNowBadge)
                          const SizedBox(width: 8),
                        if (showOverdueBadge)
                          const _OverdueBadge()
                        else if (showNowBadge)
                          const _NowBadge(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDose(entry.doseAmount)} ${_shortUnit(entry.doseUnit)} • ${entry.intakeQuantity} ${_formLabel(entry.form, entry.intakeQuantity)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3E516E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          size: 14,
                          color: Color(0xFF6E809A),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatDateShort(entry.scheduledAt),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4C617F),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.access_time,
                          size: 16,
                          color: Color(0xFF6E809A),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _to12h(entry.scheduledAt),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4C617F),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showDoneButton) ...[
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isMarking ? null : onMarkDone,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isMarking
                            ? const Color(0xFF8CB8F2)
                            : const Color(0xFF2F80ED),
                      ),
                      child: Center(
                        child: isMarking
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TakenDoseCard extends StatelessWidget {
  const _TakenDoseCard({required this.entry});

  final _DoseEntry entry;

  @override
  Widget build(BuildContext context) {
    final takenAt = entry.takenAt ?? entry.scheduledAt;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD5DEE9)),
      ),
      child: Row(
        children: [
          _IconBox(
            form: entry.form,
            imagePath: entry.imagePath,
            background: const Color(0xFFDDF1E7),
            showCheckWhenNoImage: true,
            dimImage: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF99A6BA),
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_capitalizeFirst(_doseActionLabelForForm(entry.form))} completada a las ${_to12h(takenAt)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF96A4B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NowBadge extends StatelessWidget {
  const _NowBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFDDE7F4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'AHORA',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF2F80ED),
        ),
      ),
    );
  }
}

class _OverdueBadge extends StatelessWidget {
  const _OverdueBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFBE6E6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'ATRASADO',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFFD93B3B),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({
    required this.form,
    this.imagePath,
    this.background = const Color(0xFFDDE7F4),
    this.showCheckWhenNoImage = false,
    this.dimImage = false,
  });

  final String form;
  final String? imagePath;
  final Color background;
  final bool showCheckWhenNoImage;
  final bool dimImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _MedicationVisual(
        form: form,
        imagePath: imagePath,
        showCheckWhenNoImage: showCheckWhenNoImage,
        dimImage: dimImage,
      ),
    );
  }
}

class _EmptyUpcomingCard extends StatelessWidget {
  const _EmptyUpcomingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9E2EE)),
      ),
      child: const Text(
        'No hay tomas programadas por ahora.',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF5E6F87),
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'No se pudo cargar la información.',
        style: TextStyle(color: Color(0xFF6D7E96), fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _UpcomingDoseData {
  const _UpcomingDoseData(this.upcoming, this.taken);

  final List<_DoseEntry> upcoming;
  final List<_DoseEntry> taken;
}

class _DoseEntry {
  const _DoseEntry({
    required this.medicationId,
    required this.name,
    required this.doseAmount,
    required this.doseUnit,
    required this.form,
    required this.imagePath,
    required this.route,
    required this.intakeQuantity,
    required this.scheduledAt,
    required this.takenAt,
    required this.isOverdue,
    required this.isNow,
  });

  final int medicationId;
  final String name;
  final double doseAmount;
  final String doseUnit;
  final String form;
  final String? imagePath;
  final String route;
  final int intakeQuantity;
  final DateTime scheduledAt;
  final DateTime? takenAt;
  final bool isOverdue;
  final bool isNow;

  String get key => '${medicationId}_${_dateTimeKey(scheduledAt)}';
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

String _dateTimeKey(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}

String _to12h(DateTime dt) {
  final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final minute = dt.minute.toString().padLeft(2, '0');
  final suffix = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String _formatDateShort(DateTime dt) {
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  return '$day/$month';
}

String _formatDose(double amount) {
  return amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toString();
}

String _shortUnit(String fullUnit) {
  final index = fullUnit.indexOf(' ');
  return index > 0 ? fullUnit.substring(0, index) : fullUnit;
}

IconData _iconForMedication(String form) {
  final lower = form.toLowerCase();
  if (lower.contains('tableta') ||
      lower.contains('cápsula') ||
      lower.contains('capsula')) {
    return Symbols.pill;
  }
  if (lower.contains('inyec')) {
    return Icons.vaccines_outlined;
  }
  if (lower.contains('jarabe') || lower.contains('liquid')) {
    return Icons.medication_liquid_outlined;
  }
  if (lower.contains('gota')) {
    return Icons.water_drop_outlined;
  }
  if (lower.contains('crema')) {
    return Icons.sanitizer_outlined;
  }
  if (lower.contains('polvo')) {
    return Icons.grain;
  }
  if (lower.contains('spray')) {
    return Icons.air;
  }
  if (lower.contains('inhalador')) {
    return Icons.air;
  }
  if (lower.contains('parche')) {
    return Icons.healing_outlined;
  }
  if (lower.contains('supositorio')) {
    return Icons.medication_outlined;
  }
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

class _MedicationVisual extends StatelessWidget {
  const _MedicationVisual({
    required this.form,
    required this.imagePath,
    this.showCheckWhenNoImage = false,
    this.dimImage = false,
  });

  final String form;
  final String? imagePath;
  final bool showCheckWhenNoImage;
  final bool dimImage;

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.trim().isNotEmpty;
    if (hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Opacity(
          opacity: dimImage ? 0.55 : 1,
          child: Image.file(
            File(imagePath!),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _fallbackIcon(),
          ),
        ),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    if (showCheckWhenNoImage) {
      return const Icon(
        Icons.check_circle_outline_rounded,
        size: 32,
        color: Color(0xFF5EB98A),
      );
    }
    return Icon(
      _iconForMedication(form),
      size: 32,
      color: const Color(0xFF2F80ED),
      weight: _iconWeightForMedication(form),
    );
  }
}

String _formLabel(String form, int quantity) {
  if (quantity <= 1) return form.toLowerCase();

  final lower = form.toLowerCase();
  if (lower.endsWith('s')) return lower;
  if (lower.endsWith('z')) return '${lower.substring(0, lower.length - 1)}ces';
  return '${lower}s';
}

String _doseActionLabelForForm(String form) {
  final lower = form.toLowerCase();
  if (lower.contains('tableta') ||
      lower.contains('cápsula') ||
      lower.contains('capsula') ||
      lower.contains('jarabe') ||
      lower.contains('polvo')) {
    return 'ingesta';
  }
  if (lower.contains('inyec')) return 'inyección';
  if (lower.contains('gota')) return 'aplicación de gotas';
  if (lower.contains('crema')) return 'aplicación';
  if (lower.contains('spray') || lower.contains('inhalador')) {
    return 'inhalación';
  }
  if (lower.contains('parche')) return 'aplicación de parche';
  if (lower.contains('supositorio')) return 'aplicación de supositorio';
  return 'toma';
}

String _capitalizeFirst(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
