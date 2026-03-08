import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:mis_medicamentos/db/local/medications_db.dart';
import 'package:mis_medicamentos/services/notifications_service.dart';

class HomeCalendarScreen extends StatefulWidget {
  const HomeCalendarScreen({super.key});

  @override
  State<HomeCalendarScreen> createState() => _HomeCalendarScreenState();
}

class _HomeCalendarScreenState extends State<HomeCalendarScreen> {
  late DateTime _focusedMonth;
  late DateTime _selectedDate;
  late Future<_CalendarData> _monthFuture;
  _CalendarData? _lastLoadedData;
  final ScrollController _scrollController = ScrollController();
  bool _marking = false;
  String? _selectedAgendaKey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _monthFuture = _loadMonthData(_focusedMonth);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reloadMonth() async {
    setState(() {
      _selectedAgendaKey = null;
      _monthFuture = _loadMonthData(_focusedMonth);
    });
  }

  Future<void> _goToPreviousMonth() async {
    final previous = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    setState(() {
      _focusedMonth = previous;
      if (_selectedDate.year != previous.year ||
          _selectedDate.month != previous.month) {
        _selectedDate = DateTime(previous.year, previous.month, 1);
      }
      _selectedAgendaKey = null;
      _monthFuture = _loadMonthData(_focusedMonth);
    });
  }

  Future<void> _goToNextMonth() async {
    final next = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    setState(() {
      _focusedMonth = next;
      if (_selectedDate.year != next.year ||
          _selectedDate.month != next.month) {
        _selectedDate = DateTime(next.year, next.month, 1);
      }
      _selectedAgendaKey = null;
      _monthFuture = _loadMonthData(_focusedMonth);
    });
  }

  Future<void> _markTaken(_CalendarEntry entry) async {
    if (_marking || entry.takenAt != null) return;
    final shouldProceed = await _showConfirmMarkDialog(entry);
    if (shouldProceed != true) return;

    setState(() => _marking = true);
    try {
      final marked = await AppDatabase.instance.markDoseAsTaken(
        medicationId: entry.medicationId,
        scheduledAt: entry.scheduledAt,
        intakeQuantity: entry.intakeQuantity,
      );
      if (!mounted) return;
      if (!marked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esa toma ya estaba marcada')),
        );
      }
      await _reloadMonth();
      await NotificationsService.instance
          .syncTodayDoseNotificationsFromDatabase();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo marcar la toma')),
      );
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<bool?> _showConfirmMarkDialog(_CalendarEntry entry) async {
    if (!mounted) return false;
    final action = _doseActionLabelForForm(entry.form);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            'Confirmar $action',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            '¿Confirmar $action de "${entry.name}" a las ${_to12h(entry.scheduledAt)}?',
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
    final homeBg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: homeBg,
      appBar: AppBar(
        backgroundColor: homeBg,
        surfaceTintColor: homeBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 52,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Center(
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  splashRadius: 18,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                  color: const Color(0xFF1C2A43),
                ),
              ),
            ),
          ),
        ),
        title: const Text('Calendario'),
      ),
      body: FutureBuilder<_CalendarData>(
        future: _monthFuture,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _lastLoadedData = snapshot.data;
          }

          final data = snapshot.data ?? _lastLoadedData;
          if (data == null && snapshot.hasError) {
            return const Center(
              child: Text('No se pudo cargar el calendario.'),
            );
          }
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final agenda = data.entriesByDay[_selectedDate.day] ?? const [];
          final dayMarkerStatus = data.dayMarkerStatus;

          return Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CalendarCard(
                      focusedMonth: _focusedMonth,
                      selectedDate: _selectedDate,
                      dayMarkerStatus: dayMarkerStatus,
                      onDayTap: (date) {
                        setState(() {
                          _selectedDate = date;
                          _selectedAgendaKey = null;
                        });
                      },
                      onPreviousMonth: _goToPreviousMonth,
                      onNextMonth: _goToNextMonth,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Agenda diaria',
                            style: TextStyle(
                              fontSize: 32 / 1.6,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: null,
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFFE3ECF8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: Text(
                            _formatDateShort(_selectedDate),
                            style: TextStyle(
                              color: Color(0xFF2F80ED),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (agenda.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'No hay tomas programadas para este día.',
                          style: TextStyle(
                            color: Color(0xFF5E6F87),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      ...agenda.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _AgendaCard(
                            entry: entry,
                            disabled: _marking,
                            selected: _selectedAgendaKey == entry.key,
                            onTap: () {
                              if (entry.takenAt != null) return;
                              setState(() {
                                _selectedAgendaKey = entry.key;
                              });
                            },
                            onMarkTaken: _selectedAgendaKey == entry.key
                                ? () => _markTaken(entry)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<_CalendarData> _loadMonthData(DateTime month) async {
    final db = AppDatabase.instance;
    final now = DateTime.now();
    final medications = await db.getMedications();
    final logs = await db.getDoseLogs(status: 'taken');
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
      takenByKey['${medicationId}_${_dateTimeKey(scheduledAt)}'] = takenAt;
    }

    final monthStart = DateTime(month.year, month.month, 1);
    final monthEndExclusive = DateTime(month.year, month.month + 1, 1);
    final entriesByDay = <int, List<_CalendarEntry>>{};

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
      final dayInterval = _dayIntervalFromFrequencyRule(
        medication['frequency_rule']?.toString(),
      );
      final endDateRaw = medication['end_date']?.toString().trim();
      final endDate = (endDateRaw == null || endDateRaw.isEmpty)
          ? null
          : DateTime.tryParse(endDateRaw);
      final endDateExclusive = endDate == null
          ? null
          : DateTime(endDate.year, endDate.month, endDate.day + 1);
      if (endDateExclusive != null && !firstDoseAt.isBefore(endDateExclusive)) {
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

      final medicationName = medication['name']?.toString() ?? 'Medicamento';
      final medicationForm = medication['form']?.toString() ?? 'dosis';
      final medicationDose =
          (medication['dose_amount'] as num?)?.toDouble() ?? 0;
      final medicationUnit = medication['dose_unit']?.toString() ?? '';
      final photoPath = photoPaths[medicationId];

      var totalGenerated = 0;
      var cursorDay = DateTime(
        firstDoseAt.year,
        firstDoseAt.month,
        firstDoseAt.day,
      );
      var guard = 0;

      while (cursorDay.isBefore(monthEndExclusive) && guard < 20000) {
        if (endDateExclusive != null && !cursorDay.isBefore(endDateExclusive)) {
          break;
        }
        guard++;
        for (final minute in scheduleMinutes) {
          final scheduledAt = DateTime(
            cursorDay.year,
            cursorDay.month,
            cursorDay.day,
            minute ~/ 60,
            minute % 60,
          );
          if (scheduledAt.isBefore(firstDoseAt)) continue;
          if (endDateExclusive != null &&
              !scheduledAt.isBefore(endDateExclusive)) {
            continue;
          }
          if (totalDoses != null && totalGenerated >= totalDoses) break;

          totalGenerated++;
          if (scheduledAt.isBefore(monthStart) ||
              !scheduledAt.isBefore(monthEndExclusive)) {
            continue;
          }

          final day = scheduledAt.day;
          final key = '${medicationId}_${_dateTimeKey(scheduledAt)}';
          final entry = _CalendarEntry(
            medicationId: medicationId,
            name: medicationName,
            form: medicationForm,
            imagePath: photoPath,
            doseAmount: medicationDose,
            doseUnit: medicationUnit,
            intakeQuantity: intakeQty,
            scheduledAt: scheduledAt,
            takenAt: takenByKey[key],
            isOverdue: scheduledAt.isBefore(now),
            isNow:
                !scheduledAt.isBefore(now) &&
                (scheduledAt.difference(now).inMinutes).abs() <= 20,
          );
          entriesByDay.putIfAbsent(day, () => []).add(entry);
        }
        if (totalDoses != null && totalGenerated >= totalDoses) break;
        cursorDay = cursorDay.add(Duration(days: dayInterval));
      }
    }

    for (final list in entriesByDay.values) {
      list.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    }

    final dayMarkerStatus = <int, _DayMarkerStatus>{};
    entriesByDay.forEach((day, list) {
      final hasOverdue = list.any((e) => e.takenAt == null && e.isOverdue);
      if (hasOverdue) {
        dayMarkerStatus[day] = _DayMarkerStatus.overdue;
        return;
      }

      final allCompleted =
          list.isNotEmpty && list.every((e) => e.takenAt != null);
      dayMarkerStatus[day] = allCompleted
          ? _DayMarkerStatus.completed
          : _DayMarkerStatus.pending;
    });

    return _CalendarData(entriesByDay, dayMarkerStatus);
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.focusedMonth,
    required this.selectedDate,
    required this.dayMarkerStatus,
    required this.onDayTap,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final Map<int, _DayMarkerStatus> dayMarkerStatus;
  final ValueChanged<DateTime> onDayTap;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(
      focusedMonth.year,
      focusedMonth.month,
    );
    final offset = firstDay.weekday % 7;
    final monthTitle = DateFormat('MMMM yyyy', 'es_ES').format(focusedMonth);
    final title = '${monthTitle[0].toUpperCase()}${monthTitle.substring(1)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22 / 1.4,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Row(
            children: [
              _WeekdayLabel('D'),
              _WeekdayLabel('L'),
              _WeekdayLabel('M'),
              _WeekdayLabel('M'),
              _WeekdayLabel('J'),
              _WeekdayLabel('V'),
              _WeekdayLabel('S'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final dayNumber = index - offset + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const SizedBox.shrink();
              }
              final date = DateTime(
                focusedMonth.year,
                focusedMonth.month,
                dayNumber,
              );
              final selected =
                  date.year == selectedDate.year &&
                  date.month == selectedDate.month &&
                  date.day == selectedDate.day;
              final markerStatus = dayMarkerStatus[dayNumber];
              final hasMarker = markerStatus != null;
              final markerColor = markerStatus == _DayMarkerStatus.overdue
                  ? const Color(0xFFD93B3B)
                  : markerStatus == _DayMarkerStatus.completed
                  ? const Color(0xFF5EB98A)
                  : const Color(0xFF2F80ED);

              return InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onDayTap(date),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF2F80ED)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF0D203F),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (hasMarker)
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: markerColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF8E9DB2),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AgendaCard extends StatelessWidget {
  const _AgendaCard({
    required this.entry,
    required this.onMarkTaken,
    required this.disabled,
    required this.selected,
    required this.onTap,
  });

  final _CalendarEntry entry;
  final VoidCallback? onMarkTaken;
  final bool disabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final taken = entry.takenAt != null;
    if (taken) {
      final takenAt = entry.takenAt ?? entry.scheduledAt;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD5DEE9)),
        ),
        child: Row(
          children: [
            _AgendaIconBox(
              form: entry.form,
              imagePath: entry.imagePath,
              taken: true,
            ),
            const SizedBox(width: 12),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFF2F80ED) : Colors.transparent,
              width: 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x16000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              _AgendaIconBox(
                form: entry.form,
                imagePath: entry.imagePath,
                taken: taken,
              ),
              const SizedBox(width: 12),
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
                        if (entry.isOverdue || entry.isNow)
                          const SizedBox(width: 8),
                        if (entry.isOverdue)
                          const _OverdueBadge()
                        else if (entry.isNow)
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
                          Icons.calendar_today_outlined,
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
              if (selected) ...[
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: disabled ? null : onMarkTaken,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: disabled
                            ? const Color(0xFF8CB8F2)
                            : const Color(0xFF2F80ED),
                      ),
                      child: disabled
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 28,
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

class _AgendaIconBox extends StatelessWidget {
  const _AgendaIconBox({
    required this.form,
    required this.imagePath,
    required this.taken,
  });

  final String form;
  final String? imagePath;
  final bool taken;

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.trim().isNotEmpty;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: taken ? const Color(0xFFDDF1E7) : const Color(0xFFEAF1F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Opacity(
                opacity: taken ? 0.55 : 1,
                child: Image.file(
                  File(imagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _icon(),
                ),
              ),
            )
          : _icon(),
    );
  }

  Widget _icon() {
    if (taken) {
      return const Icon(
        Icons.check_circle_outline_rounded,
        size: 30,
        color: Color(0xFF5EB98A),
      );
    }
    return Icon(
      _iconForMedication(form),
      color: const Color(0xFF2F80ED),
      weight: _iconWeightForMedication(form),
    );
  }
}

class _CalendarData {
  const _CalendarData(this.entriesByDay, this.dayMarkerStatus);

  final Map<int, List<_CalendarEntry>> entriesByDay;
  final Map<int, _DayMarkerStatus> dayMarkerStatus;
}

enum _DayMarkerStatus { pending, completed, overdue }

class _CalendarEntry {
  const _CalendarEntry({
    required this.medicationId,
    required this.name,
    required this.form,
    required this.imagePath,
    required this.doseAmount,
    required this.doseUnit,
    required this.intakeQuantity,
    required this.scheduledAt,
    required this.takenAt,
    required this.isOverdue,
    required this.isNow,
  });

  final int medicationId;
  final String name;
  final String form;
  final String? imagePath;
  final double doseAmount;
  final String doseUnit;
  final int intakeQuantity;
  final DateTime scheduledAt;
  final DateTime? takenAt;
  final bool isOverdue;
  final bool isNow;

  String get key => '${medicationId}_${_dateTimeKey(scheduledAt)}';
}

String _to12h(DateTime dt) {
  final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final minute = dt.minute.toString().padLeft(2, '0');
  final suffix = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
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

String _formatDateShort(DateTime dt) {
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  return '$day/$month';
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

int _dayIntervalFromFrequencyRule(String? rawRule) {
  final rule = (rawRule ?? '').trim().toLowerCase();
  final match = RegExp(r'^every_(\d+)_days$').firstMatch(rule);
  if (match == null) return 1;
  final parsed = int.tryParse(match.group(1) ?? '');
  if (parsed == null || parsed < 2) return 1;
  return parsed;
}

String _dateTimeKey(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
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
  if (lower.contains('spray') || lower.contains('inhalador')) return Icons.air;
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

String _formLabel(String form, int quantity) {
  if (quantity <= 1) return form.toLowerCase();
  final lower = form.toLowerCase();
  if (lower.endsWith('s')) return lower;
  if (lower.endsWith('z')) return '${lower.substring(0, lower.length - 1)}ces';
  if (lower.endsWith('ción')) {
    return '${lower.substring(0, lower.length - 4)}ciones';
  }
  if (lower.endsWith('ión')) {
    return '${lower.substring(0, lower.length - 3)}iones';
  }
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
