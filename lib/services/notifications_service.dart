import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:mis_medicamentos/db/local/medications_db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  unawaited(NotificationsService.instance.handleNotificationResponse(response));
}

class DoseNotificationSchedule {
  const DoseNotificationSchedule({
    required this.key,
    required this.medicationName,
    required this.medicationForm,
    required this.scheduledAt,
  });

  final String key;
  final String medicationName;
  final String medicationForm;
  final DateTime scheduledAt;
}

class NotificationsService {
  NotificationsService._();

  static final NotificationsService instance = NotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<int> historyChangeToken = ValueNotifier<int>(0);
  bool _initialized = false;

  static const _androidChannelId = 'medications_channel';
  static const _androidChannelName = 'Medicamentos';
  static const _androidChannelDescription =
      'Avisos al crear y gestionar medicamentos';
  static const _androidNotificationIcon = 'app_icon';
  static const _androidNotificationIconFallback = 'app_icon';
  static const _doseRemindersEnabledKey = 'dose_reminders_enabled';
  static const _doseReminderSoundUriKey = 'dose_reminder_sound_uri';
  static const _soundPickerChannelName = 'mis_medicamentos/system_sound';
  static const _defaultSoundLabel = 'Predeterminado del sistema';
  static const _dosePayloadPrefix = 'dose:';
  static const _actionMarkDoseTaken = 'dose_mark_taken';
  static const _actionSnoozeDose = 'dose_snooze_10m';
  String _resolvedAndroidNotificationIcon = _androidNotificationIcon;
  String _resolvedAndroidChannelId = _androidChannelId;
  String? _selectedReminderSoundUri;
  final MethodChannel _soundPickerChannel = const MethodChannel(
    _soundPickerChannelName,
  );

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      await _initializePluginWithIcon(_androidNotificationIcon);
      _resolvedAndroidNotificationIcon = _androidNotificationIcon;
    } on PlatformException catch (error) {
      if (error.code != 'invalid_icon') rethrow;
      try {
        await _initializePluginWithIcon(_androidNotificationIconFallback);
        _resolvedAndroidNotificationIcon = _androidNotificationIconFallback;
      } on PlatformException catch (fallbackError) {
        if (fallbackError.code != 'invalid_icon') rethrow;
        await _initializePluginWithIcon(_androidNotificationIcon);
        _resolvedAndroidNotificationIcon = _androidNotificationIcon;
      }
    }
    await _loadAndApplyReminderSoundConfiguration();

    _initialized = true;
  }

  Future<void> showMedicationScheduled({
    required String medicationName,
    String? medicationForm,
    required DateTime firstDoseAt,
  }) async {
    await initialize();

    final androidDetails = _buildAndroidNotificationDetails(
      importance: Importance.high,
      priority: Priority.high,
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: firstDoseAt.millisecondsSinceEpoch ~/ 1000,
      title: 'Medicamento agendado',
      body: '$medicationName • Siguiente toma: ${_formatDateTime(firstDoseAt)}',
      notificationDetails: details,
    );
    await _recordNotificationShown(
      title: 'Medicamento agendado',
      body: '$medicationName • Siguiente toma: ${_formatDateTime(firstDoseAt)}',
      medicationForm: medicationForm,
      payload: null,
    );
  }

  Future<void> showMedicationFinished({
    required String medicationName,
    String? medicationForm,
  }) async {
    await initialize();

    final androidDetails = _buildAndroidNotificationDetails(
      importance: Importance.high,
      priority: Priority.high,
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Medicamento finalizado',
      body: '$medicationName • Tratamiento marcado como finalizado',
      notificationDetails: details,
    );
    await _recordNotificationShown(
      title: 'Medicamento finalizado',
      body: '$medicationName • Tratamiento marcado como finalizado',
      medicationForm: medicationForm,
      payload: null,
    );
  }

  Future<void> showMedicationUpdated({
    required String medicationName,
    String? medicationForm,
  }) async {
    await initialize();

    final androidDetails = _buildAndroidNotificationDetails(
      importance: Importance.high,
      priority: Priority.high,
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Medicamento actualizado',
      body: '$medicationName • Cambios guardados correctamente',
      notificationDetails: details,
    );
    await _recordNotificationShown(
      title: 'Medicamento actualizado',
      body: '$medicationName • Cambios guardados correctamente',
      medicationForm: medicationForm,
      payload: null,
    );
  }

  Future<void> showMedicationDeleted({
    required String medicationName,
    String? medicationForm,
  }) async {
    await initialize();

    final androidDetails = _buildAndroidNotificationDetails(
      importance: Importance.high,
      priority: Priority.high,
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Medicamento eliminado',
      body: '$medicationName • Se eliminó del registro',
      notificationDetails: details,
    );
    await _recordNotificationShown(
      title: 'Medicamento eliminado',
      body: '$medicationName • Se eliminó del registro',
      medicationForm: medicationForm,
      payload: null,
    );
  }

  Future<void> syncTodayDoseNotifications({
    required List<DoseNotificationSchedule> doses,
  }) async {
    await initialize();

    final enabled = await isDoseRemindersEnabled();
    if (!enabled) {
      await _cancelAllDoseReminders();
      return;
    }

    final now = DateTime.now();
    final pending = await _plugin.pendingNotificationRequests();
    final targetById = <int, DoseNotificationSchedule>{};

    for (final dose in doses) {
      if (!dose.scheduledAt.isAfter(now)) continue;
      targetById[_doseNotificationId(dose.key)] = dose;
    }

    for (final request in pending) {
      if (!_isDosePendingRequest(request)) continue;
      if (!targetById.containsKey(request.id)) {
        await _plugin.cancel(id: request.id);
      }
    }

    for (final entry in targetById.entries) {
      final dose = entry.value;
      final details = NotificationDetails(
        android: _buildAndroidNotificationDetails(
          importance: Importance.high,
          priority: Priority.high,
          actions: const [
            AndroidNotificationAction(
              _actionMarkDoseTaken,
              'Marcar completa',
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              _actionSnoozeDose,
              'Posponer 10 min',
              cancelNotification: true,
            ),
          ],
        ),
      );

      await _plugin.zonedSchedule(
        id: entry.key,
        scheduledDate: tz.TZDateTime.from(dose.scheduledAt.toUtc(), tz.UTC),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: 'Es hora de tu medicamento',
        body: '${dose.medicationName} • ${_formatTime(dose.scheduledAt)}',
        payload: '$_dosePayloadPrefix${dose.key}',
      );
      await _recordDoseReminderScheduled(dose);
    }
  }

  Future<void> syncTodayDoseNotificationsFromDatabase() async {
    final enabled = await isDoseRemindersEnabled();
    if (!enabled) {
      await syncTodayDoseNotifications(doses: const []);
      return;
    }

    final db = AppDatabase.instance;
    final medications = await db.getMedications();
    final logs = await db.getDoseLogs(status: 'taken');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final takenKeys = <String>{};
    for (final log in logs) {
      final medicationId = log['medication_id'];
      final scheduledAtRaw = log['scheduled_at']?.toString();
      if (medicationId is! int || scheduledAtRaw == null) continue;
      final scheduledAt = DateTime.tryParse(scheduledAtRaw);
      if (scheduledAt == null) continue;
      if (!_isSameDay(scheduledAt, now)) continue;
      takenKeys.add('${medicationId}_${_dateTimeKey(scheduledAt)}');
    }

    final doses = <DoseNotificationSchedule>[];
    for (final medication in medications) {
      final status = medication['status']?.toString() ?? 'active';
      if (status != 'active') continue;
      if (!_isMedicationReminderEnabled(medication)) continue;

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

      final medicationName = medication['name']?.toString() ?? 'Medicamento';
      final medicationForm = medication['form']?.toString() ?? '';
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
        if (takenKeys.contains(key)) continue;
        doses.add(
          DoseNotificationSchedule(
            key: key,
            medicationName: medicationName,
            medicationForm: medicationForm,
            scheduledAt: scheduledAt,
          ),
        );
      }
    }

    await syncTodayDoseNotifications(doses: doses);
  }

  Future<bool> isDoseRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_doseRemindersEnabledKey) ?? true;
  }

  Future<bool> chooseReminderSoundFromSystem() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    await initialize();
    final pickedUri = await _soundPickerChannel.invokeMethod<String>(
      'pickSystemNotificationSound',
      {'currentUri': _selectedReminderSoundUri},
    );
    if (pickedUri == null) {
      return false;
    }
    await _saveReminderSoundUri(pickedUri);
    await _loadAndApplyReminderSoundConfiguration();
    await syncTodayDoseNotificationsFromDatabase();
    return true;
  }

  Future<void> resetReminderSoundToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_doseReminderSoundUriKey);
    await _loadAndApplyReminderSoundConfiguration();
    await syncTodayDoseNotificationsFromDatabase();
  }

  Future<String> getReminderSoundLabel() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'No disponible en este dispositivo';
    }
    final uri = await _readReminderSoundUri();
    if (uri == null || uri.isEmpty) {
      return _defaultSoundLabel;
    }
    try {
      final label = await _soundPickerChannel.invokeMethod<String>(
        'getRingtoneTitle',
        {'uri': uri},
      );
      final trimmed = label?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    } catch (_) {
      // Fallback if ringtone title lookup fails.
    }
    return 'Tono personalizado';
  }

  Future<void> setDoseRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_doseRemindersEnabledKey, enabled);
    if (enabled) {
      await syncTodayDoseNotificationsFromDatabase();
    } else {
      await _cancelAllDoseReminders();
    }
  }

  Future<void> _cancelAllDoseReminders() async {
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (!_isDosePendingRequest(request)) continue;
      await _plugin.cancel(id: request.id);
    }
  }

  bool _isDosePendingRequest(PendingNotificationRequest request) {
    final payload = request.payload?.trim();
    return payload != null && payload.startsWith(_dosePayloadPrefix);
  }

  Future<bool> requestNotificationsPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    await initialize();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestExactAlarmsPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    await initialize();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      final granted = await androidPlugin?.requestExactAlarmsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initializePluginWithIcon(String iconName) async {
    final androidSettings = AndroidInitializationSettings(iconName);
    final initializationSettings = InitializationSettings(
      android: androidSettings,
    );
    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  AndroidNotificationDetails _buildAndroidNotificationDetails({
    required Importance importance,
    required Priority priority,
    List<AndroidNotificationAction> actions = const [],
  }) {
    return AndroidNotificationDetails(
      _resolvedAndroidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDescription,
      icon: _resolvedAndroidNotificationIcon,
      importance: importance,
      priority: priority,
      sound: _androidSoundForUri(_selectedReminderSoundUri),
      actions: actions,
    );
  }

  AndroidNotificationSound? _androidSoundForUri(String? uri) {
    final trimmed = uri?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return UriAndroidNotificationSound(trimmed);
  }

  Future<void> _loadAndApplyReminderSoundConfiguration() async {
    _selectedReminderSoundUri = await _readReminderSoundUri();
    _resolvedAndroidChannelId = _channelIdForSound(_selectedReminderSoundUri);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return;
    await androidPlugin.createNotificationChannel(
      AndroidNotificationChannel(
        _resolvedAndroidChannelId,
        _androidChannelName,
        description: _androidChannelDescription,
        importance: Importance.high,
        playSound: true,
        sound: _androidSoundForUri(_selectedReminderSoundUri),
        enableVibration: true,
      ),
    );
  }

  String _channelIdForSound(String? uri) {
    final trimmed = uri?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _androidChannelId;
    }
    var hash = 0;
    for (final code in trimmed.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return '${_androidChannelId}_$hash';
  }

  Future<String?> _readReminderSoundUri() async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_doseReminderSoundUriKey)?.trim();
    if (uri == null || uri.isEmpty) return null;
    return uri;
  }

  Future<void> _saveReminderSoundUri(String uri) async {
    final trimmed = uri.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_doseReminderSoundUriKey, trimmed);
  }

  int _doseNotificationId(String key) {
    var hash = 0;
    for (final code in key.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> _recordNotificationShown({
    required String title,
    required String body,
    required String? medicationForm,
    required String? payload,
  }) async {
    await AppDatabase.instance.createNotificationLog({
      'event_key': null,
      'title': title,
      'body': body,
      'kind': 'shown',
      'medication_form': medicationForm,
      'scheduled_at': null,
      'payload': payload,
    });
    historyChangeToken.value++;
  }

  Future<void> _recordDoseReminderScheduled(
    DoseNotificationSchedule dose,
  ) async {
    await AppDatabase.instance.upsertNotificationLogByEventKey(
      eventKey: '$_dosePayloadPrefix${dose.key}',
      title: 'Es hora de tu medicamento',
      body: '${dose.medicationName} • ${_formatTime(dose.scheduledAt)}',
      kind: 'scheduled',
      medicationForm: dose.medicationForm,
      scheduledAt: dose.scheduledAt.toIso8601String(),
      payload: '$_dosePayloadPrefix${dose.key}',
    );
    historyChangeToken.value++;
  }

  Future<void> handleNotificationResponse(NotificationResponse response) async {
    final payload = response.payload?.trim() ?? '';
    if (!payload.startsWith(_dosePayloadPrefix)) return;

    final actionId = response.actionId?.trim();
    if (actionId == null || actionId.isEmpty) return;

    final doseKey = payload.substring(_dosePayloadPrefix.length).trim();
    final dose = _parseDoseKey(doseKey);
    if (dose == null) return;

    if (actionId == _actionMarkDoseTaken) {
      await _handleMarkDoseTakenAction(dose);
      return;
    }
    if (actionId == _actionSnoozeDose) {
      await _handleSnoozeDoseAction(dose);
    }
  }

  Future<void> _handleMarkDoseTakenAction(_DosePayloadData dose) async {
    final medication = await _findMedicationById(dose.medicationId);
    if (medication == null) return;

    final medicationName = medication['name']?.toString() ?? 'Medicamento';
    final medicationForm = medication['form']?.toString();
    final intakeQtyRaw =
        (medication['intake_quantity'] as num?)?.toDouble() ?? 1.0;
    final intakeQuantity = intakeQtyRaw <= 0 ? 1 : intakeQtyRaw.ceil();

    final marked = await AppDatabase.instance.markDoseAsTaken(
      medicationId: dose.medicationId,
      scheduledAt: dose.scheduledAt,
      intakeQuantity: intakeQuantity,
    );
    if (!marked) return;

    await _plugin.cancel(id: _doseNotificationId(dose.key));
    await AppDatabase.instance.createNotificationLog({
      'event_key': null,
      'title': 'Toma completada',
      'body': '$medicationName • ${_formatTime(dose.scheduledAt)}',
      'kind': 'action_taken',
      'medication_form': medicationForm,
      'scheduled_at': dose.scheduledAt.toIso8601String(),
      'payload': '$_dosePayloadPrefix${dose.key}',
    });
    historyChangeToken.value++;
    await syncTodayDoseNotificationsFromDatabase();
  }

  Future<void> _handleSnoozeDoseAction(_DosePayloadData dose) async {
    if (await _isDoseAlreadyTaken(dose)) return;

    final medication = await _findMedicationById(dose.medicationId);
    final rawName = medication?['name']?.toString().trim();
    final medicationName = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : 'Medicamento';
    final medicationForm = medication?['form']?.toString();
    final snoozedAt = DateTime.now().add(const Duration(minutes: 10));

    final details = NotificationDetails(
      android: _buildAndroidNotificationDetails(
        importance: Importance.high,
        priority: Priority.high,
        actions: const [
          AndroidNotificationAction(
            _actionMarkDoseTaken,
            'Marcar completa',
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            _actionSnoozeDose,
            'Posponer 10 min',
            cancelNotification: true,
          ),
        ],
      ),
    );

    await _plugin.zonedSchedule(
      id: _doseNotificationId(dose.key),
      scheduledDate: tz.TZDateTime.from(snoozedAt.toUtc(), tz.UTC),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      title: 'Es hora de tu medicamento',
      body: '$medicationName • Pospuesto 10 min',
      payload: '$_dosePayloadPrefix${dose.key}',
    );
    await AppDatabase.instance.createNotificationLog({
      'event_key': null,
      'title': 'Recordatorio pospuesto',
      'body': '$medicationName • Nuevo aviso: ${_formatTime(snoozedAt)}',
      'kind': 'action_snoozed',
      'medication_form': medicationForm,
      'scheduled_at': snoozedAt.toIso8601String(),
      'payload': '$_dosePayloadPrefix${dose.key}',
    });
    historyChangeToken.value++;
  }

  Future<Map<String, Object?>?> _findMedicationById(int medicationId) async {
    final medications = await AppDatabase.instance.getMedications();
    for (final medication in medications) {
      if (medication['id'] == medicationId) {
        return medication;
      }
    }
    return null;
  }

  Future<bool> _isDoseAlreadyTaken(_DosePayloadData dose) async {
    final takenLogs = await AppDatabase.instance.getDoseLogs(status: 'taken');
    final targetScheduledAt = dose.scheduledAt.toIso8601String();
    for (final log in takenLogs) {
      final medicationId = log['medication_id'];
      final scheduledAtRaw = log['scheduled_at']?.toString();
      if (medicationId is! int || scheduledAtRaw == null) continue;
      if (medicationId != dose.medicationId) continue;
      if (scheduledAtRaw == targetScheduledAt) return true;
    }
    return false;
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final isPm = value.hour >= 12;
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final hour = hour12.toString();
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = isPm ? 'PM' : 'AM';
    return '$day/$month $hour:$minute $suffix';
  }

  String _formatTime(DateTime value) {
    final isPm = value.hour >= 12;
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final hour = hour12.toString();
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = isPm ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
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

  bool _isMedicationReminderEnabled(Map<String, Object?> medication) {
    final reminderMinutes =
        (medication['reminder_minutes_before'] as num?)?.toInt() ?? 0;
    final reminderSound = (medication['reminder_sound'] as num?)?.toInt() ?? 0;
    final reminderVibration =
        (medication['reminder_vibration'] as num?)?.toInt() ?? 0;
    return reminderMinutes > 0 || reminderSound == 1 || reminderVibration == 1;
  }

  _DosePayloadData? _parseDoseKey(String value) {
    final trimmed = value.trim();
    final separator = trimmed.indexOf('_');
    if (separator <= 0 || separator >= trimmed.length - 1) return null;

    final medicationId = int.tryParse(trimmed.substring(0, separator));
    if (medicationId == null) return null;
    final scheduledAt = _parseDoseDateTime(trimmed.substring(separator + 1));
    if (scheduledAt == null) return null;

    return _DosePayloadData(
      key: trimmed,
      medicationId: medicationId,
      scheduledAt: scheduledAt,
    );
  }

  DateTime? _parseDoseDateTime(String value) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    return DateTime(year, month, day, hour, minute);
  }
}

class _DosePayloadData {
  const _DosePayloadData({
    required this.key,
    required this.medicationId,
    required this.scheduledAt,
  });

  final String key;
  final int medicationId;
  final DateTime scheduledAt;
}
