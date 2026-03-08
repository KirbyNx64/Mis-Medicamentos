import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:mis_medicamentos/db/local/medications_db.dart';
import 'package:mis_medicamentos/services/notifications_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiChatService {
  AiChatService._();

  static final AiChatService instance = AiChatService._();

  static const List<String> _prioritizedTextModels = [
    'openai/gpt-oss-120b',
    'meta-llama/llama-4-scout-17b-16e-instruct',
    'moonshotai/kimi-k2-instruct-0905',
    'qwen/qwen3-32b',
    'llama-3.3-70b-versatile',
  ];
  static const _configuredVisionModel = String.fromEnvironment(
    'GROQ_VISION_MODEL',
    defaultValue: '',
  );
  static const _appApiKey = String.fromEnvironment('GROQ_API_KEY');
  static const _chatCompletionsUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const _prefUsePersonalApiKey = 'ai.use_personal_api_key';
  static const _prefPersonalApiKey = 'ai.personal_api_key';
  static const _systemInstruction =
      'Eres un asistente de medicamentos en español. '
      'Ayuda a organizar horarios de toma y explica con claridad. '
      'También ayuda al usuario cuando tenga dudas sobre dosis, forma de uso, horarios, olvidos de dosis y precauciones generales. '
      'Además, responde dudas de uso de la app con pasos claros y breves: cómo agendar un medicamento manualmente, cómo editarlo, cómo eliminarlo, dónde ver todos los medicamentos y cómo marcarlo como finalizado. '
      'Cuando una duda sea de navegación dentro de la app, responde con instrucciones paso a paso orientadas a pantallas y botones. '
      'Mapa de navegación de esta app: en la barra inferior existen Inicio, Medicina, Historial y Ajustes. '
      'Para ver todos los medicamentos: abrir pestaña Medicina (lista con tabs Activos y Finalizados). '
      'Para crear manualmente: en Medicina tocar el botón + flotante, se abre Nuevo medicamento, completar formulario y tocar Guardar medicamento. '
      'Para editar: en Medicina, en la tarjeta del medicamento tocar botón de editar (ícono lápiz), cambiar datos y tocar Guardar cambios. '
      'Para eliminar: abrir editar medicamento y tocar Eliminar. '
      'Para marcar como finalizado: abrir editar medicamento y activar el switch Marcar como finalizado, luego Guardar cambios; también se puede mover entre tabs Activos/Finalizados en Medicina para verificar el estado. '
      'Para ver detalles: en la tarjeta del medicamento tocar Ver Detalles. '
      'Para marcar una dosis como tomada/aplicada/completada desde Inicio: en la sección Próximas, tocar la tarjeta de la dosis y confirmar la acción cuando aparezca el botón de confirmar. '
      'Para marcar una dosis desde Calendario: en Inicio tocar Ver calendario, seleccionar el día, tocar la dosis y confirmar. '
      'Para revisar avance diario: en Inicio, usar la tarjeta Progreso de hoy (barra de progreso) que muestra porcentaje y tomas completadas del día. '
      'Para ver historial de notificaciones: abrir la pestaña Historial (muestra el historial de notificaciones). '
      'En Ajustes se puede iniciar sesión con Google (cuenta personal) para sincronizar/guardar datos en la nube, activar o desactivar recordatorios, cambiar tono de notificación y eliminar datos de la app. '
      'Si falta contexto para responder, pide datos concretos antes de sugerir. '
      'No des diagnosticos ni sustituyas al medico. '
      'Deja claro que eres solo un asistente informativo y no un médico. '
      'Si hay una emergencia o síntomas graves, indica de forma directa que debe acudir de inmediato a su médico o a un servicio de urgencias. '
      'Para casos de riesgo, embarazo, lactancia, alergias, interacciones graves o sintomas intensos, recomienda consultar a un profesional de salud. '
      'Cuando escribas horas en mensajes para el usuario, usa formato de 12 horas con AM/PM '
      '(por ejemplo 8:00 AM, 4:30 PM), no formato 24 horas. '
      'No uses tablas (ni Markdown ni ASCII) en las respuestas; usa listas o párrafos breves. '
      'Nunca muestres nombres de campos técnicos, claves JSON o parámetros internos '
      '(por ejemplo duration_days, frequency_rule, start_date, indefinite). '
      'Si falta un dato, pídeselo al usuario con lenguaje simple y cotidiano. '
      'Antes de agendar, solicita siempre el tipo de medicamento (forma farmacéutica) y la vía de administración. '
      'Si el usuario ya proporcionó un dato, no lo vuelvas a pedir; solicita únicamente los faltantes. '
      'Usa solo estas formas farmacéuticas válidas: Tableta, Cápsula, Jarabe, Inyección, Gotas, Crema, Polvo, Spray, Inhalador, Parche, Supositorio. '
      'Antes de agendar, solicita siempre fecha y hora de la primera dosis. '
      'También puedes programar frecuencias como "cada 2 días" usando la regla every_n_days. '
      'Para tipos como jarabe, crema, gotas, spray o inhalador, solicita dias de tratamiento '
      'antes de agendar para poder calcular fecha de finalizacion. '
      'Para tabletas, cápsulas, polvos, inyecciones, parches y supositorios, '
      'solicita cuantas unidades totales tiene la persona para agendar correctamente, '
      'excepto si el usuario indica que es un tratamiento de por vida/sin cantidad total definida. '
      'No uses la palabra "stock"; usa frases como "cantidad total" o "cuántas unidades tienes". '
      'No pidas al usuario que redacte instrucciones. Las instrucciones finales del medicamento deben ser redactadas por la IA. '
      'Si el usuario brinda una indicación adicional, intégrala en las instrucciones generadas. '
      'Si el usuario lo pide, también puedes editar o eliminar medicamentos existentes usando las funciones disponibles. '
      'Si el usuario desea marcar una toma como completada, primero usa la función para listar pendientes de hoy, muestra las opciones con número y luego marca solo la opción que el usuario elija. '
      'Si el usuario pide agendar, pide datos faltantes de forma breve. '
      'Cuando ya tengas datos suficientes para guardar, llama la función '
      '`agendar_medicamento`.';

  final List<Map<String, Object?>> _history = [];
  final List<DateTime> _recentRequestTimestamps = [];
  final Map<int, _PendingDoseOption> _pendingDoseOptionsById = {};
  bool _preferencesLoaded = false;
  bool _usePersonalApiKey = false;
  String _personalApiKey = '';
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
    await _loadPreferencesIfNeeded();
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
    final selectedApiKey = _selectedApiKey;
    if (selectedApiKey.isEmpty) {
      return 'Falta configurar la API key de Groq. Inicia la app con '
          '--dart-define=GROQ_API_KEY=TU_API_KEY o guarda tu API key personal en Ajustes.';
    }
    try {
      return await _sendWithTools(
        message,
        apiKey: selectedApiKey,
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
    _history.clear();
    _pendingDoseOptionsById.clear();
    _quotaBlockedUntil = null;
  }

  bool get hasPersonalApiKey => _personalApiKey.trim().isNotEmpty;
  bool get isUsingPersonalApiKey => _usePersonalApiKey;

  Future<void> loadApiKeyPreferences() => _loadPreferencesIfNeeded();

  Future<void> setUsePersonalApiKey(bool value) async {
    await _loadPreferencesIfNeeded();
    _usePersonalApiKey = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefUsePersonalApiKey, value);
  }

  Future<void> savePersonalApiKey(String apiKey) async {
    await _loadPreferencesIfNeeded();
    _personalApiKey = apiKey.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPersonalApiKey, _personalApiKey);
  }

  Future<void> clearPersonalApiKey() async {
    await _loadPreferencesIfNeeded();
    _personalApiKey = '';
    _usePersonalApiKey = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefPersonalApiKey);
    await prefs.setBool(_prefUsePersonalApiKey, false);
  }

  Future<String?> validatePersonalApiKey(String apiKey) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      return 'La API key está vacía.';
    }
    try {
      String? lastRetryableModelError;
      for (final model in _textModelsForFailover()) {
        try {
          await _createChatCompletion(
            model,
            apiKey: trimmedKey,
            includeTools: false,
            overrideMessages: const [
              {'role': 'user', 'content': 'Responde con OK'},
            ],
            maxTokens: 4,
          );
          return null;
        } catch (error) {
          final raw = error.toString();
          if (raw.contains('401') || raw.toLowerCase().contains('invalid')) {
            return 'La API key no es válida.';
          }
          if (_isRetryableModelFailoverError(raw)) {
            lastRetryableModelError = raw;
            continue;
          }
          if (raw.contains('429')) {
            return 'La API key está válida pero alcanzó su límite temporal.';
          }
          return 'No se pudo validar la API key: $raw';
        }
      }
      if (lastRetryableModelError != null) {
        return 'La API key parece válida, pero ninguno de los modelos priorizados respondió.';
      }
      return null;
    } catch (error) {
      final raw = error.toString();
      if (raw.contains('401') || raw.toLowerCase().contains('invalid')) {
        return 'La API key no es válida.';
      }
      if (raw.contains('429')) {
        return 'La API key está válida pero alcanzó su límite temporal.';
      }
      return 'No se pudo validar la API key: $raw';
    }
  }

  Future<String> _sendWithTools(
    String userMessage, {
    required String apiKey,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) async {
    final hasImage = imageBytes != null && imageBytes.isNotEmpty;
    final requestModels = _resolveModelsForRequest(hasImage: hasImage);
    if (requestModels.isEmpty) {
      return 'Para enviar fotos necesitas configurar un modelo multimodal en Groq. '
          'Inicia la app con --dart-define=GROQ_VISION_MODEL=TU_MODELO_CON_VISION';
    }

    String? lastQuotaError;
    String? lastRetryableModelError;
    for (final requestModel in requestModels) {
      try {
        final response = await _sendWithToolsOnModel(
          userMessage,
          apiKey: apiKey,
          model: requestModel,
          imageBytes: imageBytes,
          imageMimeType: imageMimeType,
        );
        return response;
      } catch (error) {
        final rawError = error.toString();
        if (_isQuotaError(rawError)) {
          lastQuotaError = rawError;
          continue;
        }
        if (_isRetryableModelFailoverError(rawError)) {
          lastRetryableModelError = rawError;
          continue;
        }
        rethrow;
      }
    }

    if (lastQuotaError != null) {
      throw Exception(lastQuotaError);
    }
    if (lastRetryableModelError != null) {
      throw Exception(
        'Ninguno de los modelos priorizados respondió correctamente. '
        'Detalle: $lastRetryableModelError',
      );
    }
    throw Exception(
      'No fue posible obtener respuesta de los modelos configurados.',
    );
  }

  Future<String> _sendWithToolsOnModel(
    String userMessage, {
    required String apiKey,
    required String model,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) async {
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
      final assistantMessage = await _createChatCompletion(
        model,
        apiKey: apiKey,
      );
      final calls = _extractToolCalls(assistantMessage);
      if (calls.isEmpty) {
        final text = _extractAssistantText(assistantMessage);
        if (text == null || text.isEmpty) {
          return 'No pude generar una respuesta. Intenta de nuevo.';
        }
        final processedText = _postProcessAssistantText(text);
        _history.add({'role': 'assistant', 'content': processedText});
        _trimHistory();
        return processedText;
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

  List<String> _resolveModelsForRequest({required bool hasImage}) {
    if (!hasImage) return _textModelsForFailover();
    final visionModel = _configuredVisionModel.trim();
    if (visionModel.isNotEmpty) return [visionModel];
    return const [];
  }

  List<String> _textModelsForFailover() {
    final candidates = _prioritizedTextModels;
    final models = <String>[];
    for (final rawModel in candidates) {
      final model = rawModel.trim();
      if (model.isEmpty || models.contains(model)) continue;
      models.add(model);
    }
    return models;
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

  Future<Map<String, Object?>> _createChatCompletion(
    String model, {
    required String apiKey,
    bool includeTools = true,
    List<Map<String, Object?>>? overrideMessages,
    int? maxTokens,
  }) async {
    final url = Uri.parse(_chatCompletionsUrl);
    final client = HttpClient();
    try {
      final request = await client.postUrl(url);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final payloadMap = <String, Object?>{
        'model': model,
        'messages':
            overrideMessages ??
            [
              {
                'role': 'system',
                'content': '$_systemInstruction ${_todayContextForModel()}',
              },
              ..._history,
            ],
      };
      if (includeTools) {
        payloadMap['tools'] = [
          _medicationTool(),
          _editMedicationTool(),
          _deleteMedicationTool(),
          _listPendingDosesTool(),
          _markPendingDoseTakenTool(),
        ];
        payloadMap['tool_choice'] = 'auto';
      }
      if (maxTokens != null) {
        payloadMap['max_tokens'] = maxTokens;
      }
      final payload = jsonEncode(payloadMap);
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

  Future<void> _loadPreferencesIfNeeded() async {
    if (_preferencesLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _usePersonalApiKey = prefs.getBool(_prefUsePersonalApiKey) ?? false;
    _personalApiKey = prefs.getString(_prefPersonalApiKey) ?? '';
    _preferencesLoaded = true;
  }

  String get _selectedApiKey {
    final personal = _personalApiKey.trim();
    if (_usePersonalApiKey && personal.isNotEmpty) {
      return personal;
    }
    return _appApiKey.trim();
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
    if (call.name == 'editar_medicamento') {
      return _handleEditMedication(call.args);
    }
    if (call.name == 'eliminar_medicamento') {
      return _handleDeleteMedication(call.args);
    }
    if (call.name == 'listar_pendientes_hoy') {
      return _handleListPendingDosesToday();
    }
    if (call.name == 'marcar_pendiente_como_tomado') {
      return _handleMarkPendingDoseAsTaken(call.args);
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
                'every_n_days',
              ],
              'description': 'Frecuencia del tratamiento',
            },
            'every_n_days': {
              'anyOf': [
                {'type': 'integer'},
                {'type': 'null'},
              ],
              'description':
                  'Obligatorio si frequency_rule es every_n_days. Debe ser 2 o mayor.',
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
            'indefinite': {
              'anyOf': [
                {'type': 'boolean'},
                {'type': 'null'},
              ],
              'description':
                  'Indica si el tratamiento es de por vida o sin fecha final definida.',
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

  Map<String, Object?> _editMedicationTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'editar_medicamento',
        'description':
            'Edita un medicamento existente usando id o nombre como referencia.',
        'parameters': {
          'type': 'object',
          'properties': {
            'medication_id': {
              'anyOf': [
                {'type': 'integer'},
                {'type': 'null'},
              ],
              'description': 'ID del medicamento a editar',
            },
            'medication_name': {
              'type': ['string', 'null'],
              'description':
                  'Nombre del medicamento a editar (si no se conoce el id)',
            },
            'name': {
              'type': ['string', 'null'],
            },
            'dose_amount': {
              'anyOf': [
                {'type': 'number'},
                {'type': 'null'},
              ],
            },
            'dose_unit': {
              'type': ['string', 'null'],
            },
            'form': {
              'type': ['string', 'null'],
              'enum': [..._validMedicationForms, null],
            },
            'route': {
              'type': ['string', 'null'],
            },
            'frequency_rule': {
              'type': ['string', 'null'],
              'enum': [
                'every_24_hours',
                'every_12_hours',
                'every_8_hours',
                'every_6_hours',
                'custom_times',
                'every_n_days',
                null,
              ],
            },
            'every_n_days': {
              'anyOf': [
                {'type': 'integer'},
                {'type': 'null'},
              ],
            },
            'first_dose_time': {
              'type': ['string', 'null'],
            },
            'start_date': {
              'type': ['string', 'null'],
            },
            'duration_days': {
              'anyOf': [
                {'type': 'integer'},
                {'type': 'null'},
              ],
            },
            'indefinite': {
              'anyOf': [
                {'type': 'boolean'},
                {'type': 'null'},
              ],
            },
            'total_units': {
              'anyOf': [
                {'type': 'number'},
                {'type': 'null'},
              ],
            },
            'intake_quantity': {
              'anyOf': [
                {'type': 'number'},
                {'type': 'null'},
              ],
            },
            'instructions': {
              'type': ['string', 'null'],
              'description':
                  'Indicaciones nuevas dadas por el usuario para incluir en las instrucciones generadas',
            },
            'custom_times': {
              'anyOf': [
                {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
                {'type': 'null'},
              ],
            },
            'status': {
              'type': ['string', 'null'],
              'enum': ['active', 'finished', null],
            },
          },
          'required': [],
        },
      },
    };
  }

  Map<String, Object?> _deleteMedicationTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'eliminar_medicamento',
        'description':
            'Elimina un medicamento existente usando id o nombre como referencia.',
        'parameters': {
          'type': 'object',
          'properties': {
            'medication_id': {
              'anyOf': [
                {'type': 'integer'},
                {'type': 'null'},
              ],
              'description': 'ID del medicamento a eliminar',
            },
            'medication_name': {
              'type': ['string', 'null'],
              'description':
                  'Nombre del medicamento a eliminar (si no se conoce el id)',
            },
          },
          'required': [],
        },
      },
    };
  }

  Map<String, Object?> _listPendingDosesTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'listar_pendientes_hoy',
        'description':
            'Obtiene las tomas pendientes para hoy y devuelve opciones numeradas para que el usuario elija cuál marcar como tomada.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []},
      },
    };
  }

  Map<String, Object?> _markPendingDoseTakenTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'marcar_pendiente_como_tomado',
        'description':
            'Marca como tomada una dosis pendiente de hoy usando el option_id devuelto por listar_pendientes_hoy.',
        'parameters': {
          'type': 'object',
          'properties': {
            'option_id': {
              'type': 'integer',
              'description': 'Número de opción elegido por el usuario',
            },
          },
          'required': ['option_id'],
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
    final frequencyRuleRaw = (args['frequency_rule']?.toString() ?? '').trim();
    if (frequencyRuleRaw.isEmpty) {
      return {'ok': false, 'error': 'frequency_rule es obligatorio'};
    }
    final everyNDays = (args['every_n_days'] as num?)?.toInt();
    final frequencyRule = _normalizeFrequencyRule(
      frequencyRuleRaw,
      everyNDays: everyNDays,
    );
    if (frequencyRule == null) {
      return {
        'ok': false,
        'error':
            'frequency_rule no válido. Usa every_24_hours, every_12_hours, every_8_hours, every_6_hours, custom_times o every_n_days (con every_n_days >= 2).',
      };
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

    final indefinite = _parseLooseBool(args['indefinite']) ?? false;
    final requestedDurationDays = (args['duration_days'] as num?)?.toInt();
    final durationDays = indefinite ? null : requestedDurationDays;
    final requiresDurationDays = _requiresDurationDaysForForm(form);
    if (requiresDurationDays &&
        !indefinite &&
        (durationDays == null || durationDays <= 0)) {
      return {
        'ok': false,
        'error':
            'duration_days es obligatorio para este tipo de medicamento (jarabe/crema/gotas/spray/inhalador), salvo que sea tratamiento de por vida (indefinite=true).',
      };
    }

    final requiresTotalUnits = _requiresTotalUnitsForForm(form);
    final totalUnits = (args['total_units'] as num?)?.toDouble();
    if (requiresTotalUnits &&
        !indefinite &&
        (totalUnits == null || totalUnits <= 0)) {
      return {
        'ok': false,
        'error':
            'total_units es obligatorio para este tipo de medicamento, salvo que sea tratamiento de por vida (indefinite=true).',
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
      'indefinite': indefinite || durationDays == null ? 1 : 0,
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
      'action': 'created',
      'medication_id': medicationId,
      'name': name,
      'form': form,
      'route': route,
      'status': 'active',
      'dose_amount': doseAmount,
      'dose_unit': doseUnit,
      'intake_quantity': intakeQuantity,
      'indefinite': indefinite || durationDays == null ? 1 : 0,
      'frequency_rule': frequencyRule,
      'times': scheduleTimes,
      'start_date': _toIsoDate(startDate),
      'end_date': endDate == null ? null : _toIsoDate(endDate),
      'total_units': totalUnits,
    };
  }

  Future<Map<String, Object?>> _handleEditMedication(
    Map<String, Object?> args,
  ) async {
    final target = await _resolveMedicationTarget(args);
    if (target['ok'] != true) return target;

    final medication = target['medication'] as Map<String, Object?>;
    final medicationId = (medication['id'] as num?)?.toInt();
    if (medicationId == null) {
      return {'ok': false, 'error': 'No se pudo determinar el medicamento.'};
    }

    final currentSchedules = await AppDatabase.instance.getMedicationSchedules(
      medicationId,
    );
    final existingTimes = currentSchedules
        .map((row) => row['time_of_day']?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();

    final updatedName = (args['name']?.toString() ?? '').trim();
    final name = updatedName.isEmpty
        ? (medication['name']?.toString().trim() ?? '')
        : updatedName;
    if (name.isEmpty) return {'ok': false, 'error': 'name es obligatorio'};

    final updatedDoseAmount = (args['dose_amount'] as num?)?.toDouble();
    final currentDoseAmount = (medication['dose_amount'] as num?)?.toDouble();
    final doseAmount = updatedDoseAmount ?? currentDoseAmount;
    if (doseAmount == null || doseAmount <= 0) {
      return {'ok': false, 'error': 'dose_amount debe ser mayor que 0'};
    }

    final updatedDoseUnit = (args['dose_unit']?.toString() ?? '').trim();
    final doseUnit = updatedDoseUnit.isEmpty
        ? (medication['dose_unit']?.toString().trim() ?? '')
        : updatedDoseUnit;
    if (doseUnit.isEmpty) {
      return {'ok': false, 'error': 'dose_unit es obligatorio'};
    }

    final updatedFormRaw = (args['form']?.toString() ?? '').trim();
    final currentFormRaw = medication['form']?.toString().trim() ?? '';
    final formCandidate = updatedFormRaw.isEmpty
        ? currentFormRaw
        : updatedFormRaw;
    final form = _normalizeMedicationForm(formCandidate);
    if (form == null) {
      return {
        'ok': false,
        'error':
            'form no válido. Debe ser uno de: ${_validMedicationForms.join(', ')}',
      };
    }

    final updatedRoute = (args['route']?.toString() ?? '').trim();
    final route = updatedRoute.isEmpty
        ? (medication['route']?.toString().trim() ?? '')
        : updatedRoute;
    if (route.isEmpty) return {'ok': false, 'error': 'route es obligatorio'};

    final updatedFrequencyRule = (args['frequency_rule']?.toString() ?? '')
        .trim();
    final everyNDays = (args['every_n_days'] as num?)?.toInt();
    final frequencyRule = updatedFrequencyRule.isEmpty
        ? (medication['frequency_rule']?.toString().trim() ?? '')
        : _normalizeFrequencyRule(updatedFrequencyRule, everyNDays: everyNDays);
    if (frequencyRule == null || frequencyRule.isEmpty) {
      return {'ok': false, 'error': 'frequency_rule es obligatorio'};
    }

    final startDateRaw = (args['start_date']?.toString() ?? '').trim();
    final currentStartDateRaw =
        medication['start_date']?.toString().trim() ?? '';
    final finalStartDateRaw = startDateRaw.isEmpty
        ? currentStartDateRaw
        : startDateRaw;
    final startDate = DateTime.tryParse(finalStartDateRaw)?.toLocal();
    if (startDate == null) {
      return {'ok': false, 'error': 'start_date debe tener formato YYYY-MM-DD'};
    }

    final firstDoseTimeRaw = (args['first_dose_time']?.toString() ?? '').trim();
    (int, int)? firstDoseTime;
    if (firstDoseTimeRaw.isNotEmpty) {
      firstDoseTime = _parseHourMinute(firstDoseTimeRaw);
    } else {
      final currentFirstDoseAtRaw =
          medication['first_dose_at']?.toString().trim() ?? '';
      final currentFirstDoseAt = DateTime.tryParse(
        currentFirstDoseAtRaw,
      )?.toLocal();
      if (currentFirstDoseAt != null) {
        firstDoseTime = (currentFirstDoseAt.hour, currentFirstDoseAt.minute);
      } else if (existingTimes.isNotEmpty) {
        firstDoseTime = _parseHourMinute(existingTimes.first);
      }
    }
    if (firstDoseTime == null) {
      return {
        'ok': false,
        'error': 'first_dose_time debe tener formato HH:mm o h:mm AM/PM',
      };
    }

    final currentEndDateRaw = medication['end_date']?.toString().trim() ?? '';
    int? durationDays;
    final updatedDurationDays = (args['duration_days'] as num?)?.toInt();
    final updatedIndefinite = _parseLooseBool(args['indefinite']);
    final currentIndefinite = (medication['indefinite'] as num?)?.toInt() == 1;
    final isIndefinite = updatedIndefinite ?? currentIndefinite;
    if (updatedDurationDays != null) {
      durationDays = updatedDurationDays;
    } else {
      final currentEndDate = DateTime.tryParse(currentEndDateRaw)?.toLocal();
      if (currentEndDate != null) {
        durationDays =
            currentEndDate
                .difference(
                  DateTime(startDate.year, startDate.month, startDate.day),
                )
                .inDays +
            1;
      }
    }
    if (isIndefinite) {
      durationDays = null;
    }
    final requiresDurationDays = _requiresDurationDaysForForm(form);
    if (requiresDurationDays &&
        !isIndefinite &&
        (durationDays == null || durationDays <= 0)) {
      return {
        'ok': false,
        'error':
            'duration_days es obligatorio para este tipo de medicamento (jarabe/crema/gotas/spray/inhalador), salvo que sea tratamiento de por vida (indefinite=true).',
      };
    }

    final currentStock = (medication['stock_current'] as num?)?.toDouble();
    final updatedTotalUnits = (args['total_units'] as num?)?.toDouble();
    final totalUnits = updatedTotalUnits ?? currentStock;
    final requiresTotalUnits = _requiresTotalUnitsForForm(form);
    if (requiresTotalUnits &&
        !isIndefinite &&
        (totalUnits == null || totalUnits <= 0)) {
      return {
        'ok': false,
        'error':
            'total_units es obligatorio para este tipo de medicamento, salvo que sea tratamiento de por vida (indefinite=true).',
      };
    }

    final intakeQuantity =
        ((args['intake_quantity'] as num?)?.toDouble() ??
                (medication['intake_quantity'] as num?)?.toDouble() ??
                1)
            .clamp(1, 50);

    final customTimes =
        (args['custom_times'] as List?)
            ?.map((e) => e?.toString() ?? '')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final shouldRebuildTimes =
        updatedFrequencyRule.isNotEmpty ||
        firstDoseTimeRaw.isNotEmpty ||
        customTimes.isNotEmpty;

    final scheduleTimes = shouldRebuildTimes
        ? _buildScheduleTimes(
            frequencyRule: frequencyRule,
            firstDoseTime: firstDoseTime,
            customTimes: customTimes,
          )
        : (existingTimes.isEmpty
              ? _buildScheduleTimes(
                  frequencyRule: frequencyRule,
                  firstDoseTime: firstDoseTime,
                  customTimes: customTimes,
                )
              : existingTimes);

    if (scheduleTimes.isEmpty) {
      return {'ok': false, 'error': 'No se pudo calcular el horario'};
    }

    final statusRaw = (args['status']?.toString() ?? '').trim().toLowerCase();
    final status = statusRaw == 'finished' || statusRaw == 'active'
        ? statusRaw
        : (medication['status']?.toString().trim().isNotEmpty ?? false)
        ? medication['status']!.toString().trim()
        : 'active';

    final endDate = durationDays == null
        ? null
        : DateTime(
            startDate.year,
            startDate.month,
            startDate.day,
          ).add(Duration(days: durationDays - 1));
    final userNotes = (args['instructions']?.toString() ?? '').trim();
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

    await AppDatabase.instance.updateMedication(medicationId, {
      'name': name,
      'dose_amount': doseAmount,
      'dose_unit': doseUnit,
      'form': form,
      'route': route,
      'status': status,
      'instructions': generatedInstructions,
      'first_dose_at': firstDoseAt.toIso8601String(),
      'start_date': _toIsoDate(startDate),
      'end_date': endDate == null ? null : _toIsoDate(endDate),
      'indefinite': isIndefinite || durationDays == null ? 1 : 0,
      'frequency_rule': frequencyRule,
      'days_of_week': '1,2,3,4,5,6,7',
      'stock_current': totalUnits,
      'stock_initial': totalUnits,
      'intake_quantity': intakeQuantity,
      'updated_at': DateTime.now().toIso8601String(),
    }, times: scheduleTimes);

    if (status == 'finished') {
      await NotificationsService.instance.showMedicationFinished(
        medicationName: name,
        medicationForm: form,
      );
    } else {
      await NotificationsService.instance.showMedicationUpdated(
        medicationName: name,
        medicationForm: form,
      );
    }
    await NotificationsService.instance
        .syncTodayDoseNotificationsFromDatabase();

    return {
      'ok': true,
      'medication_id': medicationId,
      'name': name,
      'action': 'updated',
      'form': form,
      'route': route,
      'status': status,
      'dose_amount': doseAmount,
      'dose_unit': doseUnit,
      'intake_quantity': intakeQuantity,
      'indefinite': isIndefinite || durationDays == null ? 1 : 0,
      'frequency_rule': frequencyRule,
      'times': scheduleTimes,
      'start_date': _toIsoDate(startDate),
      'end_date': endDate == null ? null : _toIsoDate(endDate),
    };
  }

  Future<Map<String, Object?>> _handleDeleteMedication(
    Map<String, Object?> args,
  ) async {
    final target = await _resolveMedicationTarget(args);
    if (target['ok'] != true) return target;

    final medication = target['medication'] as Map<String, Object?>;
    final medicationId = (medication['id'] as num?)?.toInt();
    if (medicationId == null) {
      return {'ok': false, 'error': 'No se pudo determinar el medicamento.'};
    }
    final name = medication['name']?.toString().trim() ?? 'medicamento';
    final form = medication['form']?.toString().trim();

    await AppDatabase.instance.deleteMedication(medicationId);
    await NotificationsService.instance.showMedicationDeleted(
      medicationName: name,
      medicationForm: (form == null || form.isEmpty) ? null : form,
    );
    await NotificationsService.instance
        .syncTodayDoseNotificationsFromDatabase();
    return {
      'ok': true,
      'action': 'deleted',
      'medication_id': medicationId,
      'name': name,
    };
  }

  Future<Map<String, Object?>> _handleListPendingDosesToday() async {
    final pending = await _getPendingDosesToday();
    _pendingDoseOptionsById
      ..clear()
      ..addEntries(pending.map((dose) => MapEntry(dose.optionId, dose)));

    final options = pending
        .map(
          (dose) => {
            'option_id': dose.optionId,
            'medication_id': dose.medicationId,
            'medication_name': dose.name,
            'scheduled_at': dose.scheduledAt.toIso8601String(),
            'scheduled_time': _normalizeAssistantTimeFormat(
              _toHourMinute(
                (dose.scheduledAt.hour * 60) + dose.scheduledAt.minute,
              ),
            ),
            'dose': '${_formatDoseValue(dose.doseAmount)} ${dose.doseUnit}',
          },
        )
        .toList(growable: false);

    return {
      'ok': true,
      'action': 'list_pending_today',
      'count': options.length,
      'options': options,
    };
  }

  Future<Map<String, Object?>> _handleMarkPendingDoseAsTaken(
    Map<String, Object?> args,
  ) async {
    final optionId = (args['option_id'] as num?)?.toInt();
    if (optionId == null || optionId <= 0) {
      return {'ok': false, 'error': 'option_id inválido.'};
    }

    var selected = _pendingDoseOptionsById[optionId];
    if (selected == null) {
      final refreshed = await _getPendingDosesToday();
      _pendingDoseOptionsById
        ..clear()
        ..addEntries(refreshed.map((dose) => MapEntry(dose.optionId, dose)));
      selected = _pendingDoseOptionsById[optionId];
      if (selected == null) {
        return {
          'ok': false,
          'error':
              'No encontré esa opción pendiente. Solicita la lista de pendientes de hoy nuevamente.',
        };
      }
    }

    final marked = await AppDatabase.instance.markDoseAsTaken(
      medicationId: selected.medicationId,
      scheduledAt: selected.scheduledAt,
      intakeQuantity: selected.intakeQuantity,
    );
    if (!marked) {
      return {
        'ok': false,
        'error':
            'Esa dosis ya estaba marcada como tomada. Puedes pedir la lista actualizada.',
      };
    }

    _pendingDoseOptionsById.remove(optionId);
    await NotificationsService.instance
        .syncTodayDoseNotificationsFromDatabase();
    return {
      'ok': true,
      'action': 'marked_taken',
      'option_id': optionId,
      'medication_id': selected.medicationId,
      'name': selected.name,
      'scheduled_at': selected.scheduledAt.toIso8601String(),
    };
  }

  Future<Map<String, Object?>> _resolveMedicationTarget(
    Map<String, Object?> args,
  ) async {
    final medications = await AppDatabase.instance.getMedications();
    if (medications.isEmpty) {
      return {'ok': false, 'error': 'No hay medicamentos registrados.'};
    }

    final medicationId = (args['medication_id'] as num?)?.toInt();
    if (medicationId != null) {
      for (final row in medications) {
        if ((row['id'] as num?)?.toInt() == medicationId) {
          return {'ok': true, 'medication': row};
        }
      }
      return {
        'ok': false,
        'error': 'No encontré medicamento con id $medicationId.',
      };
    }

    final medicationName = (args['medication_name']?.toString() ?? '').trim();
    if (medicationName.isEmpty) {
      return {
        'ok': false,
        'error':
            'Necesito medication_id o medication_name para identificar el medicamento.',
      };
    }

    final normalized = medicationName.toLowerCase();
    final exact = medications.where((row) {
      final name = row['name']?.toString().trim().toLowerCase() ?? '';
      return name == normalized;
    }).toList();
    if (exact.length == 1) return {'ok': true, 'medication': exact.first};
    if (exact.length > 1) {
      final names = exact
          .take(5)
          .map(
            (row) => '${row['name']} (id ${(row['id'] as num?)?.toInt() ?? 0})',
          )
          .join(', ');
      return {
        'ok': false,
        'error':
            'Hay varios medicamentos con ese nombre. Indica el id. Opciones: $names',
      };
    }

    final partial = medications.where((row) {
      final name = row['name']?.toString().trim().toLowerCase() ?? '';
      return name.contains(normalized);
    }).toList();
    if (partial.length == 1) return {'ok': true, 'medication': partial.first};
    if (partial.length > 1) {
      final names = partial
          .take(5)
          .map(
            (row) => '${row['name']} (id ${(row['id'] as num?)?.toInt() ?? 0})',
          )
          .join(', ');
      return {
        'ok': false,
        'error':
            'Coincidencias múltiples. Indica el id del medicamento. Opciones: $names',
      };
    }

    return {
      'ok': false,
      'error': 'No encontré un medicamento que coincida con "$medicationName".',
    };
  }

  Future<List<_PendingDoseOption>> _getPendingDosesToday() async {
    final db = AppDatabase.instance;
    final medications = await db.getMedications();
    final logs = await db.getDoseLogs(status: 'taken');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final takenByKey = <String>{};
    for (final log in logs) {
      final medicationId = log['medication_id'];
      final scheduledAtRaw = log['scheduled_at']?.toString();
      if (medicationId is! int || scheduledAtRaw == null) continue;
      final scheduledAt = DateTime.tryParse(scheduledAtRaw);
      if (scheduledAt == null) continue;
      final key = '${medicationId}_${_dateTimeKey(scheduledAt)}';
      takenByKey.add(key);
    }

    final pending = <_PendingDoseOption>[];
    for (final medication in medications) {
      final status = medication['status']?.toString() ?? 'active';
      if (status != 'active') continue;

      final medicationId = medication['id'];
      if (medicationId is! int) continue;

      final schedules = await db.getMedicationSchedules(medicationId);
      final scheduleMinutes = <int>[];
      for (final schedule in schedules) {
        final timeText = schedule['time_of_day']?.toString();
        if (timeText == null || !_isValidHourMinuteText(timeText)) continue;
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
      final dayInterval = _frequencyDayInterval(
        medication['frequency_rule']?.toString(),
      );

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

      final name = medication['name']?.toString() ?? 'Medicamento';
      final doseAmount = (medication['dose_amount'] as num?)?.toDouble() ?? 0;
      final doseUnit = medication['dose_unit']?.toString() ?? '';
      final form = medication['form']?.toString() ?? '';

      for (final minute in scheduleMinutes) {
        final scheduledAt = DateTime(
          today.year,
          today.month,
          today.day,
          minute ~/ 60,
          minute % 60,
        );
        final scheduledDay = DateTime(
          scheduledAt.year,
          scheduledAt.month,
          scheduledAt.day,
        );
        final firstDay = DateTime(
          firstDoseAt.year,
          firstDoseAt.month,
          firstDoseAt.day,
        );
        final dayDiff = scheduledDay.difference(firstDay).inDays;
        if (dayDiff < 0 || dayDiff % dayInterval != 0) continue;
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
            dayInterval: dayInterval,
          );
          if (ordinal > totalDoses) continue;
        }

        final key = '${medicationId}_${_dateTimeKey(scheduledAt)}';
        if (takenByKey.contains(key)) continue;
        pending.add(
          _PendingDoseOption(
            optionId: 0,
            medicationId: medicationId,
            name: name,
            form: form,
            doseAmount: doseAmount,
            doseUnit: doseUnit,
            intakeQuantity: intakeQty,
            scheduledAt: scheduledAt,
          ),
        );
      }
    }

    pending.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    for (var i = 0; i < pending.length; i++) {
      pending[i] = pending[i].copyWith(optionId: i + 1);
    }
    return pending;
  }

  int _doseOrdinalForSchedule({
    required List<int> scheduleMinutes,
    required DateTime firstDoseAt,
    required DateTime scheduledAt,
    required int dayInterval,
  }) {
    if (scheduleMinutes.isEmpty) return 1;
    final dayStart = DateTime(
      scheduledAt.year,
      scheduledAt.month,
      scheduledAt.day,
    );
    final currentMinute = (scheduledAt.hour * 60) + scheduledAt.minute;
    final indexToday = scheduleMinutes.indexOf(currentMinute);
    final dosesPerDay = scheduleMinutes.length;
    if (indexToday < 0) {
      return 1;
    }

    final firstDayStart = DateTime(
      firstDoseAt.year,
      firstDoseAt.month,
      firstDoseAt.day,
    );
    final firstMinute = (firstDoseAt.hour * 60) + firstDoseAt.minute;
    final firstIndex = scheduleMinutes.lastIndexWhere((m) => m <= firstMinute);
    final firstDayDoseIndex = firstIndex < 0 ? 0 : firstIndex;

    final dayDiff = dayStart.difference(firstDayStart).inDays;
    if (dayDiff < 0) {
      return 0;
    }
    if (dayDiff % dayInterval != 0) {
      return 0;
    }
    final intervalIndex = dayDiff ~/ dayInterval;
    if (intervalIndex == 0) {
      return (indexToday - firstDayDoseIndex) + 1;
    }

    final firstDayCount = dosesPerDay - firstDayDoseIndex;
    return firstDayCount + ((intervalIndex - 1) * dosesPerDay) + indexToday + 1;
  }

  bool _isValidHourMinuteText(String value) {
    return RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value);
  }

  String _dateTimeKey(DateTime value) {
    final yyyy = value.year.toString().padLeft(4, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '$yyyy$mm$dd$hh$min';
  }

  String _formatDoseValue(double value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toString();
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
    final everyNDaysMatch = RegExp(
      r'^every_(\d+)_days$',
    ).firstMatch(frequencyRule.toLowerCase().trim());
    if (everyNDaysMatch != null) {
      return [_toHourMinute(minutes)];
    }

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

  String? _normalizeFrequencyRule(String rawRule, {int? everyNDays}) {
    final rule = rawRule.trim().toLowerCase();
    if (rule.isEmpty) return null;
    if (rule == 'daily') return 'every_24_hours';
    if (rule.startsWith('custom_times')) return 'custom_times';
    if (rule == 'every_24_hours' ||
        rule == 'every_12_hours' ||
        rule == 'every_8_hours' ||
        rule == 'every_6_hours') {
      return rule;
    }
    if (rule == 'every_n_days') {
      if (everyNDays == null || everyNDays < 2) return null;
      return 'every_${everyNDays}_days';
    }
    final intervalMatch = RegExp(r'^every_(\d+)_days$').firstMatch(rule);
    if (intervalMatch != null) {
      final parsed = int.tryParse(intervalMatch.group(1)!);
      if (parsed == null || parsed < 2) return null;
      return 'every_${parsed}_days';
    }
    return null;
  }

  int _frequencyDayInterval(String? rawRule) {
    final rule = (rawRule ?? '').trim().toLowerCase();
    final match = RegExp(r'^every_(\d+)_days$').firstMatch(rule);
    if (match == null) return 1;
    final parsed = int.tryParse(match.group(1) ?? '');
    if (parsed == null || parsed < 2) return 1;
    return parsed;
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

  bool? _parseLooseBool(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) return null;
    if (text == 'true' || text == '1' || text == 'si' || text == 'sí') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no') {
      return false;
    }
    return null;
  }

  String _todayContextForModel() {
    final now = DateTime.now();
    final dateIso = DateFormat('yyyy-MM-dd').format(now);
    final time24 = DateFormat('HH:mm').format(now);
    final time12 = DateFormat('h:mm a').format(now);
    final utcOffset = now.timeZoneOffset;
    final offsetSign = utcOffset.isNegative ? '-' : '+';
    final offsetHours = utcOffset.inHours.abs().toString().padLeft(2, '0');
    final offsetMinutes = (utcOffset.inMinutes.abs() % 60).toString().padLeft(
      2,
      '0',
    );
    final offsetText = '$offsetSign$offsetHours:$offsetMinutes';
    return 'Contexto temporal actual: '
        'hoy es $dateIso (YYYY-MM-DD), '
        'hora local $time24 (24h) / $time12 (12h), '
        'zona horaria ${now.timeZoneName} (UTC$offsetText).';
  }

  String _normalizeAssistantTimeFormat(String text) {
    final timeRegex = RegExp(
      r'\b([01]?\d|2[0-3]):([0-5]\d)\b(?!\s*[AaPp]\.?\s*[Mm]\.?)',
    );
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

  String _postProcessAssistantText(String text) {
    final withoutTables = _convertMarkdownTablesToBullets(text);
    return _normalizeAssistantTimeFormat(withoutTables);
  }

  String _convertMarkdownTablesToBullets(String text) {
    final lines = text.split('\n');
    final output = <String>[];
    var i = 0;

    while (i < lines.length) {
      if (i + 1 < lines.length &&
          _looksLikeTableRow(lines[i]) &&
          _isMarkdownTableSeparator(lines[i + 1])) {
        final headers = _parseTableCells(lines[i]);
        i += 2;

        while (i < lines.length && _looksLikeTableRow(lines[i])) {
          final cells = _parseTableCells(lines[i]);
          if (cells.isEmpty) {
            i++;
            continue;
          }

          if (headers.length == cells.length && headers.isNotEmpty) {
            final pairs = <String>[];
            for (var j = 0; j < cells.length; j++) {
              pairs.add('${headers[j]}: ${cells[j]}');
            }
            output.add('- ${pairs.join('; ')}');
          } else {
            output.add('- ${cells.join(' | ')}');
          }
          i++;
        }
        continue;
      }

      output.add(lines[i]);
      i++;
    }

    return output.join('\n');
  }

  bool _looksLikeTableRow(String line) {
    if (!line.contains('|')) return false;
    return _parseTableCells(line).length >= 2;
  }

  bool _isMarkdownTableSeparator(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) {
      trimmed = trimmed.substring(1);
    }
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final parts = trimmed.split('|').map((part) => part.trim()).toList();
    if (parts.isEmpty) return false;
    return parts.every((part) => RegExp(r'^:?-{3,}:?$').hasMatch(part));
  }

  List<String> _parseTableCells(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) {
      trimmed = trimmed.substring(1);
    }
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.split('|').map((cell) => cell.trim()).toList();
  }

  String _functionResultToUserMessage(
    String functionName,
    Map<String, Object?> result,
  ) {
    final ok = result['ok'] == true;
    if (!ok) {
      final error = (result['error']?.toString() ?? 'Dato faltante').trim();
      return _friendlyToolErrorForUser(error);
    }

    if (functionName == 'agendar_medicamento') {
      return _buildMedicationSummaryMessage(
        result: result,
        title: 'Medicamento agendado',
      );
    }

    if (functionName == 'editar_medicamento') {
      return _buildMedicationSummaryMessage(
        result: result,
        title: 'Medicamento actualizado',
      );
    }

    if (functionName == 'eliminar_medicamento') {
      final name = (result['name']?.toString() ?? 'medicamento').trim();
      return 'Listo. Eliminé $name.';
    }

    if (functionName == 'listar_pendientes_hoy') {
      final count = (result['count'] as num?)?.toInt() ?? 0;
      if (count <= 0) {
        return 'No hay tomas pendientes para hoy.';
      }
      final options =
          (result['options'] as List?)
              ?.whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList() ??
          const <Map<String, Object?>>[];
      final lines = <String>['Estas son las tomas pendientes de hoy:'];
      for (final option in options) {
        final id = option['option_id']?.toString() ?? '?';
        final name = option['medication_name']?.toString() ?? 'Medicamento';
        final time = option['scheduled_time']?.toString() ?? '';
        final dose = option['dose']?.toString() ?? '';
        lines.add('$id. $name - $time - $dose');
      }
      lines.add('Indícame el número de opción para marcarla como completada.');
      return lines.join('\n');
    }

    if (functionName == 'marcar_pendiente_como_tomado') {
      final name = (result['name']?.toString() ?? 'medicamento').trim();
      final scheduledAt = result['scheduled_at']?.toString() ?? '';
      final dt = DateTime.tryParse(scheduledAt);
      final timeText = dt == null
          ? ''
          : _normalizeAssistantTimeFormat(
              _toHourMinute(dt.hour * 60 + dt.minute),
            );
      return timeText.isEmpty
          ? 'Listo. Marqué la toma de $name como completada.'
          : 'Listo. Marqué la toma de $name de las $timeText como completada.';
    }

    return 'Listo. Acción completada.';
  }

  String _friendlyToolErrorForUser(String rawError) {
    final error = rawError.trim();
    final lower = error.toLowerCase();

    if (lower.contains('duration_days es obligatorio')) {
      return 'Para continuar: ¿cuántos días durará el tratamiento? Si es de por vida, también puedo dejarlo sin fecha de finalización.';
    }
    if (lower.contains('total_units es obligatorio')) {
      return 'Para continuar: ¿cuántas unidades tienes en total de este medicamento?';
    }
    if (lower.contains('name es obligatorio')) {
      return 'Para continuar: ¿cuál es el nombre del medicamento?';
    }
    if (lower.contains('dose_amount debe ser mayor que 0')) {
      return 'Para continuar: ¿qué cantidad corresponde en cada toma o aplicación?';
    }
    if (lower.contains('dose_unit es obligatorio')) {
      return 'Para continuar: ¿en qué unidad va la dosis (por ejemplo mg, ml, gotas o puffs)?';
    }
    if (lower.contains('form es obligatorio')) {
      return 'Para continuar: ¿qué tipo de medicamento es (tableta, cápsula, jarabe, crema, etc.)?';
    }
    if (lower.contains('form no válido')) {
      return 'Para continuar: dime el tipo de medicamento usando una opción común como tableta, cápsula, jarabe, inyección, gotas, crema, polvo, spray, inhalador, parche o supositorio.';
    }
    if (lower.contains('route es obligatorio')) {
      return 'Para continuar: ¿por qué vía se administra (oral, tópica, inhalatoria, etc.)?';
    }
    if (lower.contains('frequency_rule es obligatorio')) {
      return 'Para continuar: ¿cada cuánto debes tomarlo o aplicarlo?';
    }
    if (lower.contains('frequency_rule no válido')) {
      return 'Para continuar: indícame la frecuencia en palabras simples, por ejemplo "cada 8 horas", "cada 12 horas" o "cada 2 días".';
    }
    if (lower.contains('first_dose_time debe tener formato')) {
      return 'Para continuar: ¿a qué hora será la primera dosis?';
    }
    if (lower.contains('start_date es obligatorio')) {
      return 'Para continuar: ¿en qué fecha iniciarás el tratamiento?';
    }
    if (lower.contains('start_date debe tener formato')) {
      return 'Para continuar: indícame la fecha de inicio en formato YYYY-MM-DD, por ejemplo 2026-03-08.';
    }
    if (lower.contains('no se pudo calcular el horario')) {
      return 'No pude calcular el horario con esos datos. ¿Quieres que lo configure cada 8, 12 o 24 horas?';
    }

    return error.isEmpty
        ? 'Para continuar, me falta un dato importante.'
        : 'Para continuar, me falta este dato: $error';
  }

  String _buildMedicationSummaryMessage({
    required Map<String, Object?> result,
    required String title,
  }) {
    final name = (result['name']?.toString() ?? 'Medicamento').trim();
    final form = (result['form']?.toString() ?? '').trim();
    final route = (result['route']?.toString() ?? '').trim();
    final statusRaw = (result['status']?.toString() ?? 'active').trim();
    final statusLabel = statusRaw == 'finished' ? 'FINALIZADO' : 'EN CURSO';
    final doseAmount = (result['dose_amount'] as num?)?.toDouble();
    final doseUnit = _shortDoseUnit(result['dose_unit']?.toString() ?? '');
    final frequencyRule = (result['frequency_rule']?.toString() ?? '').trim();
    final startDate = (result['start_date']?.toString() ?? '').trim();
    final endDate = (result['end_date']?.toString() ?? '').trim();
    final times =
        (result['times'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final timesText = times.isEmpty
        ? 'Sin horario definido'
        : times.map(_normalizeAssistantTimeFormat).join(', ');
    final frequencyLabel = _frequencyLabelForAssistant(frequencyRule);
    final scheduleTitle = _scheduleTitleForAssistant(form);
    final doseText = doseAmount == null
        ? form.toLowerCase()
        : '${_formatDoseValue(doseAmount)}$doseUnit • ${_pluralizeForAssistant(form)}';
    final startLabel = _formatAssistantDateLabel(startDate);
    final endLabel = endDate.isEmpty
        ? 'Sin fecha de finalización'
        : _formatAssistantDateLabel(endDate);
    final routeLabel = route.isEmpty ? 'No especificada' : route;

    final lines = <String>[
      '### $title',
      '#### $name  **$statusLabel**',
      '',
      '**DOSIS**',
      '**$doseText**',
      '',
      '**FRECUENCIA**',
      frequencyLabel,
      '',
      '**$scheduleTitle**',
      timesText,
      '',
      '**INICIO**',
      startLabel,
      '',
      '**FIN**',
      endLabel,
      '',
      '**VÍA**',
      routeLabel,
    ];
    return lines.join('\n');
  }

  String _shortDoseUnit(String fullUnit) {
    final trimmed = fullUnit.trim();
    if (trimmed.isEmpty) return '';
    final index = trimmed.indexOf(' ');
    return index > 0 ? trimmed.substring(0, index) : trimmed;
  }

  String _pluralizeForAssistant(String form) {
    final lower = form.trim().toLowerCase();
    if (lower.isEmpty) return 'dosis';
    if (lower.endsWith('s')) return lower;
    if (lower.endsWith('ción')) {
      return '${lower.substring(0, lower.length - 4)}ciones';
    }
    if (lower.endsWith('ión')) {
      return '${lower.substring(0, lower.length - 3)}iones';
    }
    if (lower.endsWith('z')) {
      return '${lower.substring(0, lower.length - 1)}ces';
    }
    return '${lower}s';
  }

  String _scheduleTitleForAssistant(String form) {
    final lower = form.toLowerCase();
    if (lower.contains('inyec') ||
        lower.contains('parche') ||
        lower.contains('crema') ||
        lower.contains('spray') ||
        lower.contains('inhalador') ||
        lower.contains('gota')) {
      return 'HORAS DE APLICACIÓN';
    }
    if (lower.contains('supositorio')) return 'HORAS DE DOSIS';
    return 'HORAS DE TOMA';
  }

  String _frequencyLabelForAssistant(String ruleRaw) {
    final rule = ruleRaw.trim().toLowerCase();
    if (rule == 'daily' || rule == 'every_24_hours') return 'Cada 24 horas';
    if (rule == 'every_12_hours') return 'Cada 12 horas';
    if (rule == 'every_8_hours') return 'Cada 8 horas';
    if (rule == 'every_6_hours') return 'Cada 6 horas';
    final everyNDaysMatch = RegExp(r'^every_(\d+)_days$').firstMatch(rule);
    if (everyNDaysMatch != null) {
      final days = int.tryParse(everyNDaysMatch.group(1) ?? '');
      if (days != null && days >= 2) return 'Cada $days días';
    }
    if (rule.startsWith('custom_times')) return 'Horas personalizadas';
    return ruleRaw.trim().isEmpty ? 'Sin frecuencia' : ruleRaw;
  }

  String _formatAssistantDateLabel(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.isEmpty) return 'No definido';
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return trimmed;
    final formatted = DateFormat("EEEE, d 'de' MMMM", 'es_ES').format(parsed);
    if (formatted.isEmpty) return trimmed;
    return '${formatted[0].toUpperCase()}${formatted.substring(1)}';
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

  bool _isRetryableModelFailoverError(String rawError) {
    final message = rawError.toLowerCase();
    if (message.contains('groq api error 404') ||
        message.contains('groq api error 408') ||
        message.contains('groq api error 500') ||
        message.contains('groq api error 502') ||
        message.contains('groq api error 503') ||
        message.contains('groq api error 504')) {
      return true;
    }
    if (message.contains('temporarily unavailable') ||
        message.contains('timeout') ||
        message.contains('upstream error') ||
        message.contains('overloaded') ||
        message.contains('capacity')) {
      return true;
    }
    if (message.contains('model') &&
        (message.contains('not found') ||
            message.contains('does not exist') ||
            message.contains('unsupported') ||
            message.contains('not support') ||
            message.contains('decommissioned') ||
            message.contains('not active') ||
            message.contains('not available'))) {
      return true;
    }
    return false;
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

class _PendingDoseOption {
  _PendingDoseOption({
    required this.optionId,
    required this.medicationId,
    required this.name,
    required this.form,
    required this.doseAmount,
    required this.doseUnit,
    required this.intakeQuantity,
    required this.scheduledAt,
  });

  int optionId;
  final int medicationId;
  final String name;
  final String form;
  final double doseAmount;
  final String doseUnit;
  final int intakeQuantity;
  final DateTime scheduledAt;

  _PendingDoseOption copyWith({int? optionId}) {
    return _PendingDoseOption(
      optionId: optionId ?? this.optionId,
      medicationId: medicationId,
      name: name,
      form: form,
      doseAmount: doseAmount,
      doseUnit: doseUnit,
      intakeQuantity: intakeQuantity,
      scheduledAt: scheduledAt,
    );
  }
}
