import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mis_medicamentos/db/local/medications_db.dart';
import 'package:mis_medicamentos/services/notifications_service.dart';

class AiChatService {
  AiChatService._();

  static final AiChatService instance = AiChatService._();

  static const _defaultModelName = 'openai/gpt-oss-120b';
  static const _configuredModelName = String.fromEnvironment(
    'GROQ_MODEL',
    defaultValue: _defaultModelName,
  );
  static const _configuredVisionModel = String.fromEnvironment(
    'GROQ_VISION_MODEL',
    defaultValue: '',
  );
  static const _apiKey = String.fromEnvironment('GROQ_API_KEY');
  static const _chatCompletionsUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const _systemInstruction =
      'Eres un asistente de medicamentos en español. '
      'Ayuda a organizar horarios de toma y explica con claridad. '
      'También ayuda al usuario cuando tenga dudas sobre dosis, forma de uso, horarios, olvidos de dosis y precauciones generales. '
      'Si falta contexto para responder, pide datos concretos antes de sugerir. '
      'No des diagnosticos ni sustituyas al medico. '
      'Para casos de riesgo, embarazo, lactancia, alergias, interacciones graves o sintomas intensos, recomienda consultar a un profesional de salud. '
      'Cuando escribas horas en mensajes para el usuario, usa formato de 12 horas con AM/PM '
      '(por ejemplo 8:00 AM, 4:30 PM), no formato 24 horas. '
      'Antes de agendar, solicita siempre el tipo de medicamento (forma farmacéutica) y la vía de administración. '
      'Si el usuario ya proporcionó un dato, no lo vuelvas a pedir; solicita únicamente los faltantes. '
      'Usa solo estas formas farmacéuticas válidas: Tableta, Cápsula, Jarabe, Inyección, Gotas, Crema, Polvo, Spray, Inhalador, Parche, Supositorio. '
      'Antes de agendar, solicita siempre fecha y hora de la primera dosis. '
      'Para tipos como jarabe, crema, gotas, spray o inhalador, solicita dias de tratamiento '
      'antes de agendar para poder calcular fecha de finalizacion. '
      'Para tabletas, cápsulas, polvos, inyecciones, parches y supositorios, '
      'solicita cuantas unidades totales tiene la persona para agendar correctamente. '
      'No uses la palabra "stock"; usa frases como "cantidad total" o "cuántas unidades tienes". '
      'No pidas al usuario que redacte instrucciones. Las instrucciones finales del medicamento deben ser redactadas por la IA. '
      'Si el usuario brinda una indicación adicional, intégrala en las instrucciones generadas. '
      'Si el usuario pide agendar, pide datos faltantes de forma breve. '
      'Cuando ya tengas datos suficientes para guardar, llama la función '
      '`agendar_medicamento`.';

  final List<Map<String, Object?>> _history = [];
  final List<DateTime> _recentRequestTimestamps = [];
  String _activeModelName = _configuredModelName;
  DateTime? _quotaBlockedUntil;
  static const _maxHistoryEntries = 18;
  static const _requestWindow = Duration(minutes: 1);
  static const _maxRequestsPerWindow = 12;
  static const List<String> _validMedicationForms = [
    'Tableta',
    'Cápsula',
    'Jarabe',
    'Inyección',
    'Gotas',
    'Crema',
    'Polvo',
    'Spray',
    'Inhalador',
    'Parche',
    'Supositorio',
  ];

  Future<String> sendMessage(
    String message, {
    Uint8List? imageBytes,
    String? imageMimeType,
  }) async {
    final now = DateTime.now();
    _cleanRecentRequests(now);

    if (_quotaBlockedUntil != null && now.isBefore(_quotaBlockedUntil!)) {
      final seconds = _quotaBlockedUntil!.difference(now).inSeconds + 1;
      return 'Se alcanzó el límite temporal de uso de IA. Intenta de nuevo en aproximadamente $seconds segundos.';
    }

    if (_recentRequestTimestamps.length >= _maxRequestsPerWindow) {
      final nextAllowedAt = _recentRequestTimestamps.first.add(_requestWindow);
      final waitSeconds = nextAllowedAt.difference(now).inSeconds + 1;
      _quotaBlockedUntil = nextAllowedAt;
      return 'Estás enviando mensajes muy rápido para el plan actual. Espera aproximadamente $waitSeconds segundos para continuar.';
    }

    _recentRequestTimestamps.add(now);
    if (_apiKey.trim().isEmpty) {
      return 'Falta configurar la API key de Groq. Inicia la app con '
          '--dart-define=GROQ_API_KEY=TU_API_KEY';
    }
    _activeModelName = _activeModelName.trim();
    if (_activeModelName.trim().isEmpty) {
      _activeModelName = _defaultModelName;
    }

    try {
      return await _sendWithTools(
        message,
        imageBytes: imageBytes,
        imageMimeType: imageMimeType,
      );
    } catch (error) {
      final rawError = error.toString();
      if (_isImageNotSupportedError(rawError)) {
        return 'El modelo actual no acepta imágenes. '
            'Configura un modelo multimodal con '
            '--dart-define=GROQ_VISION_MODEL=TU_MODELO_CON_VISION';
      }
      if (_isQuotaError(rawError)) {
        _setQuotaCooldown(rawError);
        return _buildQuotaMessage(rawError);
      }
      rethrow;
    }
  }

  void reset() {
    _activeModelName = _configuredModelName.trim().isEmpty
        ? _defaultModelName
        : _configuredModelName.trim();
    _history.clear();
    _quotaBlockedUntil = null;
  }

  Future<String> _sendWithTools(
    String userMessage, {
    Uint8List? imageBytes,
    String? imageMimeType,
  }) async {
    final hasImage = imageBytes != null && imageBytes.isNotEmpty;
    final requestModel = _resolveModelForRequest(hasImage: hasImage);
    if (requestModel == null) {
      return 'Para enviar fotos necesitas configurar un modelo multimodal en Groq. '
          'Inicia la app con --dart-define=GROQ_VISION_MODEL=TU_MODELO_CON_VISION';
    }

    final baseLength = _history.length;
    final modelReadyUserMessage = _enhanceUserMessageForModel(userMessage);
    final userContent = _buildUserContent(
      text: modelReadyUserMessage,
      imageBytes: imageBytes,
      imageMimeType: imageMimeType,
    );
    if (userContent == null) {
      return 'Escribe un mensaje o adjunta una imagen.';
    }
    _history.add({'role': 'user', 'content': userContent});
    _trimHistory();

    try {
      final assistantMessage = await _createChatCompletion(requestModel);
      final calls = _extractToolCalls(assistantMessage);
      if (calls.isEmpty) {
        final text = _extractAssistantText(assistantMessage);
        if (text == null || text.isEmpty) {
          return 'No pude generar una respuesta. Intenta de nuevo.';
        }
        _history.add({'role': 'assistant', 'content': text});
        _trimHistory();
        return _normalizeAssistantTimeFormat(text);
      }

      _history.add({
        'role': 'assistant',
        'content': assistantMessage['content'],
        'tool_calls': calls.map((call) => call.toOpenAiJson()).toList(),
      });
      _trimHistory();

      final results = <Map<String, Object?>>[];
      for (final call in calls) {
        final result = await _dispatchFunctionCall(call);
        results.add(result);
        _history.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'name': call.name,
          'content': jsonEncode(result),
        });
        _trimHistory();
      }
      return _functionResultsToUserMessage(calls, results);
    } catch (_) {
      if (_history.length > baseLength) {
        _history.removeRange(baseLength, _history.length);
      }
      rethrow;
    }
  }

  String? _resolveModelForRequest({required bool hasImage}) {
    if (!hasImage) return _activeModelName;
    final visionModel = _configuredVisionModel.trim();
    if (visionModel.isNotEmpty) return visionModel;
    return null;
  }

  Object? _buildUserContent({
    required String text,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) {
    final trimmed = text.trim();
    if (imageBytes == null || imageBytes.isEmpty) {
      return trimmed.isEmpty ? null : trimmed;
    }

    final parts = <Map<String, Object?>>[];
    if (trimmed.isNotEmpty) {
      parts.add({'type': 'text', 'text': trimmed});
    }
    final mime = (imageMimeType == null || imageMimeType.trim().isEmpty)
        ? 'image/jpeg'
        : imageMimeType.trim();
    parts.add({
      'type': 'image_url',
      'image_url': {'url': 'data:$mime;base64,${base64Encode(imageBytes)}'},
    });
    return parts.isEmpty ? null : parts;
  }

  Future<Map<String, Object?>> _createChatCompletion(String model) async {
    final url = Uri.parse(_chatCompletionsUrl);
    final client = HttpClient();
    try {
      final request = await client.postUrl(url);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final payload = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': '$_systemInstruction ${_todayContextForModel()}',
          },
          ..._history,
        ],
        'tools': [_medicationTool()],
        'tool_choice': 'auto',
      });
      request.add(utf8.encode(payload));

      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(responseText);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Respuesta invalida de Groq.');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _extractApiErrorMessage(decoded) ?? responseText;
        throw Exception('Groq API error ${response.statusCode}: $message');
      }

      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw Exception('Groq no devolvio candidatos.');
      }
      final first = choices.first;
      if (first is! Map<String, dynamic>) {
        throw Exception('Respuesta de Groq con formato no soportado.');
      }
      final message = first['message'];
      if (message is! Map<String, dynamic>) {
        throw Exception('Groq no devolvio un mensaje de asistente valido.');
      }
      return message.map((key, value) => MapEntry(key, value as Object?));
    } finally {
      client.close(force: true);
    }
  }

  String? _extractApiErrorMessage(Map<String, dynamic> payload) {
    final error = payload['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message']?.toString().trim();
      if (message != null && message.isNotEmpty) return message;
    }
    return null;
  }

  String? _extractAssistantText(Map<String, Object?> message) {
    final content = message['content'];
    if (content is String) {
      return content.trim();
    }
    if (content is List) {
      final chunks = <String>[];
      for (final part in content) {
        if (part is Map) {
          final type = part['type']?.toString();
          final text = part['text']?.toString() ?? '';
          if (type == 'text' && text.trim().isNotEmpty) {
            chunks.add(text.trim());
          }
        }
      }
      if (chunks.isNotEmpty) return chunks.join('\n').trim();
    }
    return null;
  }

  List<_ToolCall> _extractToolCalls(Map<String, Object?> assistantMessage) {
    final rawToolCalls = assistantMessage['tool_calls'];
    if (rawToolCalls is! List) return const [];

    final calls = <_ToolCall>[];
    for (final rawCall in rawToolCalls) {
      if (rawCall is! Map) continue;
      final id = rawCall['id']?.toString().trim() ?? '';
      final function = rawCall['function'];
      if (id.isEmpty || function is! Map) continue;
      final name = function['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;

      final rawArgs = function['arguments']?.toString().trim() ?? '{}';
      Map<String, Object?> args = const <String, Object?>{};
      if (rawArgs.isNotEmpty) {
        try {
          final parsed = jsonDecode(rawArgs);
          if (parsed is Map<String, dynamic>) {
            args = parsed.map((key, value) => MapEntry(key, value as Object?));
          }
        } catch (_) {
          args = const <String, Object?>{};
        }
      }
      calls.add(_ToolCall(id: id, name: name, args: args));
    }
    return calls;
  }

  Future<Map<String, Object?>> _dispatchFunctionCall(_ToolCall call) async {
    if (call.name == 'agendar_medicamento') {
      return _handleScheduleMedication(call.args);
    }
    return {'ok': false, 'error': 'Función no soportada: ${call.name}'};
  }

  Map<String, Object?> _medicationTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'agendar_medicamento',
        'description':
            'Crea un medicamento en la base local con su horario de tomas.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Nombre del medicamento'},
            'dose_amount': {
              'type': 'number',
              'description': 'Dosis por toma, por ejemplo 1 o 500',
            },
            'dose_unit': {
              'type': 'string',
              'description': 'Unidad de dosis, por ejemplo mg, ml, gotas',
            },
            'form': {
              'type': 'string',
              'enum': _validMedicationForms,
              'description':
                  'Forma farmacéutica. Valores válidos: Tableta, Cápsula, Jarabe, Inyección, Gotas, Crema, Polvo, Spray, Inhalador, Parche, Supositorio',
            },
            'route': {
              'type': 'string',
              'description': 'Vía de administración, por ejemplo Oral',
            },
            'frequency_rule': {
              'type': 'string',
              'enum': [
                'every_24_hours',
                'every_12_hours',
                'every_8_hours',
                'every_6_hours',
                'custom_times',
              ],
              'description': 'Frecuencia del tratamiento',
            },
            'first_dose_time': {
              'type': 'string',
              'description':
                  'Hora de primera toma. Acepta HH:mm o h:mm AM/PM (ej. 23:00, 11:00 PM)',
            },
            'start_date': {
              'type': 'string',
              'description':
                  'Fecha de la primera dosis en formato YYYY-MM-DD (obligatorio)',
            },
            'duration_days': {
              'anyOf': [
                {'type': 'integer'},
                {'type': 'null'},
              ],
              'description':
                  'Días de duración. Obligatorio para jarabe, crema, gotas, spray e inhalador.',
            },
            'total_units': {
              'anyOf': [
                {'type': 'number'},
                {'type': 'null'},
              ],
              'description':
                  'Cantidad total disponible de unidades (ej. tabletas, cápsulas, parches, inyecciones, supositorios, sobres). '
                  'Obligatorio para tableta/cápsula/polvo/inyección/parche/supositorio.',
            },
            'intake_quantity': {
              'anyOf': [
                {'type': 'number'},
                {'type': 'null'},
              ],
              'description':
                  'Cantidad de unidades por toma. Valor por defecto 1',
            },
            'instructions': {
              'type': ['string', 'null'],
              'description':
                  'Indicaciones adicionales dadas por el usuario para incorporarlas en las instrucciones finales',
            },
            'custom_times': {
              'anyOf': [
                {
                  'type': 'array',
                  'items': {
                    'type': 'string',
                    'description': 'Hora HH:mm o h:mm AM/PM',
                  },
                },
                {'type': 'null'},
              ],
              'description': 'Lista de horas si frequency_rule es custom_times',
            },
          },
          'required': [
            'name',
            'dose_amount',
            'dose_unit',
            'form',
            'route',
            'frequency_rule',
            'first_dose_time',
            'start_date',
          ],
        },
      },
    };
  }

  Future<Map<String, Object?>> _handleScheduleMedication(
    Map<String, Object?> args,
  ) async {
    final name = (args['name']?.toString() ?? '').trim();
    if (name.isEmpty) {
      return {'ok': false, 'error': 'name es obligatorio'};
    }

    final doseAmount = (args['dose_amount'] as num?)?.toDouble();
    if (doseAmount == null || doseAmount <= 0) {
      return {'ok': false, 'error': 'dose_amount debe ser mayor que 0'};
    }

    final doseUnit = (args['dose_unit']?.toString() ?? '').trim();
    if (doseUnit.isEmpty) {
      return {'ok': false, 'error': 'dose_unit es obligatorio'};
    }

    final formRaw = (args['form']?.toString() ?? '').trim();
    if (formRaw.isEmpty) {
      return {'ok': false, 'error': 'form es obligatorio'};
    }
    final form = _normalizeMedicationForm(formRaw);
    if (form == null) {
      return {
        'ok': false,
        'error':
            'form no válido. Debe ser uno de: ${_validMedicationForms.join(', ')}',
      };
    }

    final route = (args['route']?.toString() ?? '').trim();
    if (route.isEmpty) {
      return {'ok': false, 'error': 'route es obligatorio'};
    }
    final frequencyRule = (args['frequency_rule']?.toString() ?? '').trim();
    if (frequencyRule.isEmpty) {
      return {'ok': false, 'error': 'frequency_rule es obligatorio'};
    }

    final firstDoseTimeRaw = (args['first_dose_time']?.toString() ?? '').trim();
    final firstDoseTime = _parseHourMinute(firstDoseTimeRaw);
    if (firstDoseTime == null) {
      return {
        'ok': false,
        'error': 'first_dose_time debe tener formato HH:mm o h:mm AM/PM',
      };
    }

    final startDateRaw = (args['start_date']?.toString() ?? '').trim();
    if (startDateRaw.isEmpty) {
      return {'ok': false, 'error': 'start_date es obligatorio'};
    }
    final startDate = DateTime.tryParse(startDateRaw)?.toLocal();
    if (startDate == null) {
      return {'ok': false, 'error': 'start_date debe tener formato YYYY-MM-DD'};
    }

    final durationDays = (args['duration_days'] as num?)?.toInt();
    final requiresDurationDays = _requiresDurationDaysForForm(form);
    if (requiresDurationDays && (durationDays == null || durationDays <= 0)) {
      return {
        'ok': false,
        'error':
            'duration_days es obligatorio para este tipo de medicamento (jarabe/crema/gotas/spray/inhalador).',
      };
    }

    final requiresTotalUnits = _requiresTotalUnitsForForm(form);
    final totalUnits = (args['total_units'] as num?)?.toDouble();
    if (requiresTotalUnits && (totalUnits == null || totalUnits <= 0)) {
      return {
        'ok': false,
        'error':
            'total_units es obligatorio para este tipo de medicamento. Indica cuántas unidades totales tienes.',
      };
    }

    final intakeQuantity = ((args['intake_quantity'] as num?)?.toDouble() ?? 1)
        .clamp(1, 50);
    final userNotes = (args['instructions']?.toString() ?? '').trim();
    final customTimes =
        (args['custom_times'] as List?)
            ?.map((e) => e?.toString() ?? '')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];

    final scheduleTimes = _buildScheduleTimes(
      frequencyRule: frequencyRule,
      firstDoseTime: firstDoseTime,
      customTimes: customTimes,
    );
    if (scheduleTimes.isEmpty) {
      return {'ok': false, 'error': 'No se pudo calcular el horario'};
    }
    final endDate = durationDays == null
        ? null
        : DateTime(
            startDate.year,
            startDate.month,
            startDate.day,
          ).add(Duration(days: durationDays - 1));
    final generatedInstructions = _buildGeneratedInstructions(
      form: form,
      route: route,
      doseAmount: doseAmount,
      doseUnit: doseUnit,
      times: scheduleTimes,
      endDate: endDate,
      userNotes: userNotes,
    );
    final firstDoseAt = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      firstDoseTime.$1,
      firstDoseTime.$2,
    );

    final medicationId = await AppDatabase.instance.createMedication({
      'name': name,
      'active_ingredient': null,
      'dose_amount': doseAmount,
      'dose_unit': doseUnit,
      'form': form,
      'route': route,
      'status': 'active',
      'instructions': generatedInstructions,
      'diagnosis': null,
      'prescribed_by': null,
      'first_dose_at': firstDoseAt.toIso8601String(),
      'start_date': _toIsoDate(startDate),
      'end_date': endDate == null ? null : _toIsoDate(endDate),
      'indefinite': durationDays == null ? 1 : 0,
      'frequency_rule': frequencyRule,
      'days_of_week': '1,2,3,4,5,6,7',
      'stock_current': totalUnits,
      'stock_initial': totalUnits,
      'stock_minimum': null,
      'intake_quantity': intakeQuantity,
      'reminder_minutes_before': 15,
      'reminder_sound': 1,
      'reminder_vibration': 1,
      'interactions_notes': null,
      'side_effects_notes': null,
      'notes': null,
    }, times: scheduleTimes);

    if (await NotificationsService.instance.isDoseRemindersEnabled()) {
      await NotificationsService.instance.showMedicationScheduled(
        medicationName: name,
        medicationForm: form,
        firstDoseAt: firstDoseAt,
      );
    }
    await NotificationsService.instance
        .syncTodayDoseNotificationsFromDatabase();

    return {
      'ok': true,
      'medication_id': medicationId,
      'name': name,
      'frequency_rule': frequencyRule,
      'times': scheduleTimes,
      'start_date': _toIsoDate(startDate),
      'end_date': endDate == null ? null : _toIsoDate(endDate),
      'total_units': totalUnits,
    };
  }

  String _buildGeneratedInstructions({
    required String form,
    required String route,
    required double doseAmount,
    required String doseUnit,
    required List<String> times,
    required DateTime? endDate,
    required String userNotes,
  }) {
    final doseText = doseAmount % 1 == 0
        ? doseAmount.toInt().toString()
        : doseAmount.toString();
    final scheduleText = times
        .map(_normalizeAssistantTimeFormat)
        .join(', ')
        .trim();
    final endText = endDate == null
        ? 'Mantener el esquema hasta nueva indicación médica.'
        : 'Mantener el esquema hasta ${_toIsoDate(endDate)}.';

    final lines = <String>[
      'Administrar $doseText $doseUnit por toma, forma $form, vía $route.',
      'Horarios sugeridos: $scheduleText.',
      endText,
    ];

    final cleanedNotes = userNotes.trim();
    if (cleanedNotes.isNotEmpty) {
      final compact = cleanedNotes.replaceAll(RegExp(r'\s+'), ' ');
      final truncated = compact.length > 140
          ? '${compact.substring(0, 140)}...'
          : compact;
      lines.add('Nota del usuario: $truncated.');
    }

    return lines.take(4).join('\n');
  }

  List<String> _buildScheduleTimes({
    required String frequencyRule,
    required (int, int) firstDoseTime,
    required List<String> customTimes,
  }) {
    final minutes = (firstDoseTime.$1 * 60) + firstDoseTime.$2;
    switch (frequencyRule) {
      case 'every_24_hours':
        return [_toHourMinute(minutes)];
      case 'every_12_hours':
        return List.generate(
          2,
          (index) => _toHourMinute((minutes + (index * 720)) % 1440),
        );
      case 'every_8_hours':
        return List.generate(
          3,
          (index) => _toHourMinute((minutes + (index * 480)) % 1440),
        );
      case 'every_6_hours':
        return List.generate(
          4,
          (index) => _toHourMinute((minutes + (index * 360)) % 1440),
        );
      case 'custom_times':
        final parsed =
            customTimes
                .map(_parseHourMinute)
                .whereType<(int, int)>()
                .map((t) => _toHourMinute((t.$1 * 60) + t.$2))
                .toSet()
                .toList()
              ..sort();
        if (parsed.isNotEmpty) return parsed;
        return [_toHourMinute(minutes)];
      default:
        return [_toHourMinute(minutes)];
    }
  }

  (int, int)? _parseHourMinute(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    final amPmMatch = RegExp(
      r'^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (amPmMatch != null) {
      final hourRaw = int.tryParse(amPmMatch.group(1)!);
      final minuteRaw = int.tryParse(amPmMatch.group(2) ?? '00');
      if (hourRaw == null || minuteRaw == null) return null;
      if (hourRaw < 1 || hourRaw > 12 || minuteRaw < 0 || minuteRaw > 59) {
        return null;
      }
      final isPm = amPmMatch.group(3)!.toLowerCase() == 'p';
      final hour24 = (hourRaw % 12) + (isPm ? 12 : 0);
      return (hour24, minuteRaw);
    }

    final parts = normalized.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  String _toHourMinute(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final minute = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _toIsoDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$year-$month-$day';
  }

  String _enhanceUserMessageForModel(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return text;

    final hints = <String>[];
    final form = _extractFormFromText(text);
    if (form != null) {
      hints.add('forma farmacéutica: $form');
    }
    final route = _extractRouteFromText(text);
    if (route != null) {
      hints.add('vía: $route');
    }
    final firstDoseTime = _extractTimeFromText(text);
    if (firstDoseTime != null) {
      hints.add('hora primera dosis: $firstDoseTime');
    }
    final startDate = _extractDateFromText(text);
    if (startDate != null) {
      hints.add('fecha primera dosis: $startDate');
    }

    if (hints.isEmpty) return text;
    return '$text\n\n[Datos detectados automáticamente: ${hints.join('; ')}]';
  }

  String? _extractFormFromText(String text) {
    final lowered = text.toLowerCase();
    const candidates = <String>[
      'tableta',
      'tabletas',
      'capsula',
      'cápsula',
      'capsulas',
      'cápsulas',
      'jarabe',
      'inyeccion',
      'inyección',
      'inyectable',
      'ampolla',
      'vial',
      'gota',
      'gotas',
      'crema',
      'polvo',
      'spray',
      'inhalador',
      'parche',
      'parches',
      'supositorio',
      'supositorios',
    ];
    for (final candidate in candidates) {
      final escaped = RegExp.escape(candidate);
      final regex = RegExp('\\b$escaped\\b', caseSensitive: false);
      if (regex.hasMatch(lowered)) {
        return _normalizeMedicationForm(candidate);
      }
    }
    return null;
  }

  String? _extractRouteFromText(String text) {
    final lowered = text.toLowerCase();
    const aliases = <String, String>{
      'oral': 'Oral',
      'intramuscular': 'Intramuscular',
      'intravenosa': 'Intravenosa',
      'subcutanea': 'Subcutánea',
      'subcutánea': 'Subcutánea',
      'topica': 'Tópica',
      'tópica': 'Tópica',
      'inhalatoria': 'Inhalatoria',
      'nasal': 'Nasal',
      'oftalmica': 'Oftálmica',
      'oftálmica': 'Oftálmica',
      'otica': 'Ótica',
      'ótica': 'Ótica',
      'sublingual': 'Sublingual',
      'bucal': 'Bucal (sin tragar)',
      'masticable': 'Masticable',
      'efervescente': 'Efervescente',
      'rectal': 'Rectal',
      'vaginal': 'Vaginal',
    };
    for (final entry in aliases.entries) {
      final regex = RegExp('\\b${RegExp.escape(entry.key)}\\b');
      if (regex.hasMatch(lowered)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _extractTimeFromText(String text) {
    final match = RegExp(
      r'\b\d{1,2}(?::\d{2})?\s*[ap]\.?m\.?\b|\b\d{1,2}:\d{2}\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final parsed = _parseHourMinute(match.group(0)!);
    if (parsed == null) return null;
    return _toHourMinute((parsed.$1 * 60) + parsed.$2);
  }

  String? _extractDateFromText(String text) {
    final iso = RegExp(r'\b\d{4}-\d{2}-\d{2}\b').firstMatch(text)?.group(0);
    if (iso != null) return iso;

    final lowered = text.toLowerCase();
    final now = DateTime.now();
    if (RegExp(r'\bhoy\b').hasMatch(lowered)) {
      return _toIsoDate(now);
    }
    if (RegExp(r'\bmañana\b|\bmanana\b').hasMatch(lowered)) {
      return _toIsoDate(now.add(const Duration(days: 1)));
    }
    return null;
  }

  String? _normalizeMedicationForm(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    const aliases = <String, String>{
      'tableta': 'Tableta',
      'tabletas': 'Tableta',
      'capsula': 'Cápsula',
      'cápsula': 'Cápsula',
      'capsulas': 'Cápsula',
      'cápsulas': 'Cápsula',
      'jarabe': 'Jarabe',
      'inyeccion': 'Inyección',
      'inyección': 'Inyección',
      'inyectable': 'Inyección',
      'ampolla': 'Inyección',
      'vial': 'Inyección',
      'gota': 'Gotas',
      'gotas': 'Gotas',
      'crema': 'Crema',
      'polvo': 'Polvo',
      'spray': 'Spray',
      'inhalador': 'Inhalador',
      'parche': 'Parche',
      'parches': 'Parche',
      'supositorio': 'Supositorio',
      'supositorios': 'Supositorio',
    };

    final mapped = aliases[normalized];
    if (mapped == null) return null;
    return _validMedicationForms.contains(mapped) ? mapped : null;
  }

  bool _requiresDurationDaysForForm(String form) {
    final lower = form.toLowerCase();
    return lower.contains('gota') ||
        lower.contains('jarabe') ||
        lower.contains('crema') ||
        lower.contains('spray') ||
        lower.contains('inhalador');
  }

  bool _requiresTotalUnitsForForm(String form) {
    final lower = form.toLowerCase();
    return lower.contains('tableta') ||
        lower.contains('cápsula') ||
        lower.contains('capsula') ||
        lower.contains('polvo') ||
        lower.contains('inyec') ||
        lower.contains('parche') ||
        lower.contains('supositorio');
  }

  String _todayContextForModel() {
    final now = DateTime.now();
    final yyyy = now.year.toString().padLeft(4, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return 'Contexto de fecha: hoy es $yyyy-$mm-$dd (formato YYYY-MM-DD).';
  }

  String _normalizeAssistantTimeFormat(String text) {
    final timeRegex = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
    return text.replaceAllMapped(timeRegex, (match) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final isPm = hour >= 12;
      final hour12 = hour % 12 == 0 ? 12 : hour % 12;
      final minuteText = minute.toString().padLeft(2, '0');
      final suffix = isPm ? 'PM' : 'AM';
      return '$hour12:$minuteText $suffix';
    });
  }

  String _functionResultToUserMessage(
    String functionName,
    Map<String, Object?> result,
  ) {
    final ok = result['ok'] == true;
    if (!ok) {
      final error = (result['error']?.toString() ?? 'Dato faltante').trim();
      return 'Para continuar, necesito este dato: $error';
    }

    if (functionName == 'agendar_medicamento') {
      final name = (result['name']?.toString() ?? 'medicamento').trim();
      final startDate = result['start_date']?.toString() ?? '';
      final endDate = result['end_date']?.toString() ?? '';
      final times =
          (result['times'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final timesText = times.isEmpty
          ? ''
          : '\nHorarios: ${times.map(_normalizeAssistantTimeFormat).join(', ')}.';
      final endText = endDate.isEmpty
          ? 'sin fecha de finalización definida.'
          : 'hasta $endDate.';
      return 'Listo. Agendé $name desde $startDate $endText$timesText';
    }

    return 'Listo. Acción completada.';
  }

  String _functionResultsToUserMessage(
    List<_ToolCall> calls,
    List<Map<String, Object?>> results,
  ) {
    if (calls.isEmpty || results.isEmpty) {
      return 'No pude procesar la acción solicitada.';
    }

    for (var i = 0; i < calls.length && i < results.length; i++) {
      if (results[i]['ok'] != true) {
        return _functionResultToUserMessage(calls[i].name, results[i]);
      }
    }

    return _functionResultToUserMessage(calls.first.name, results.first);
  }

  bool _isQuotaError(String rawError) {
    final message = rawError.toLowerCase();
    return message.contains('quota exceeded') ||
        message.contains('insufficient_quota') ||
        message.contains('429') ||
        message.contains('too many requests') ||
        message.contains('exceeded your current quota') ||
        message.contains('rate limit') ||
        message.contains('resource_exhausted');
  }

  bool _isImageNotSupportedError(String rawError) {
    final message = rawError.toLowerCase();
    return message.contains('image') &&
        (message.contains('not support') ||
            message.contains('unsupported') ||
            message.contains('invalid image') ||
            message.contains('vision'));
  }

  void _setQuotaCooldown(String rawError) {
    final lower = rawError.toLowerCase();
    final match = RegExp(
      r'please retry in\s+([0-9]+(?:\.[0-9]+)?)s',
    ).firstMatch(lower);
    final retrySeconds = match == null
        ? (_isHardQuotaError(rawError) ? 120 : 60)
        : (double.tryParse(match.group(1) ?? '') ?? 60).ceil();
    _quotaBlockedUntil = DateTime.now().add(
      Duration(seconds: retrySeconds.clamp(5, 600)),
    );
  }

  String _buildQuotaMessage(String rawError) {
    final now = DateTime.now();
    final wait = _quotaBlockedUntil == null
        ? 60
        : (_quotaBlockedUntil!.difference(now).inSeconds + 1);
    if (_isHardQuotaError(rawError)) {
      return 'La cuota de Groq para este proyecto está agotada en este momento. '
          'No es un fallo del chat. Espera un rato para que se libere cupo o revisa tu plan/facturación en Groq. '
          'Vuelve a intentar en aproximadamente $wait segundos.';
    }
    return 'Se alcanzó el límite temporal de uso de IA. Intenta de nuevo en aproximadamente $wait segundos.';
  }

  bool _isHardQuotaError(String rawError) {
    final message = rawError.toLowerCase();
    return message.contains('check your plan and billing details') ||
        message.contains('insufficient_quota') ||
        message.contains('credit') ||
        message.contains('out of quota');
  }

  void _cleanRecentRequests(DateTime now) {
    _recentRequestTimestamps.removeWhere(
      (timestamp) => now.difference(timestamp) >= _requestWindow,
    );
  }

  void _trimHistory() {
    if (_history.length <= _maxHistoryEntries) return;
    _history.removeRange(0, _history.length - _maxHistoryEntries);
  }
}

class _ToolCall {
  _ToolCall({required this.id, required this.name, required this.args});

  final String id;
  final String name;
  final Map<String, Object?> args;

  Map<String, Object?> toOpenAiJson() {
    return {
      'id': id,
      'type': 'function',
      'function': {'name': name, 'arguments': jsonEncode(args)},
    };
  }
}
