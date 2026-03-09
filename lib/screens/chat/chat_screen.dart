import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:mis_medicamentos/services/ai_chat_service.dart';
import 'package:mis_medicamentos/services/connectivity_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _maxAllowedMessages = 30;
  static const List<String> _welcomeOptions = [
    'Hola, soy tu asistente. Puedes escribirme algo como: "Agéndame paracetamol cada 8 horas".',
    '¡Hola! Estoy aquí para ayudarte con tus medicamentos. Ejemplo: "Recuérdame ibuprofeno cada 12 horas".',
    'Bienvenido. Si quieres, puedo ayudarte a agendar una medicina paso a paso.',
    'Hola, cuéntame qué medicamento necesitas organizar y te ayudo a programarlo.',
    '¡Hola! Puedo ayudarte con dosis, horarios y recordatorios de tus medicamentos.',
    'Hola, ¿quieres que agendemos un medicamento ahora mismo?',
    '¡Bienvenido! Puedo ayudarte a crear un horario de tomas claro y ordenado.',
    'Hola, si me dices el medicamento y la frecuencia, te ayudo a programarlo.',
    'Estoy listo para ayudarte con tus recordatorios de medicamentos.',
    '¡Hola! También puedo ayudarte si olvidaste una dosis.',
    'Cuéntame qué necesitas: agendar, editar o eliminar un medicamento.',
    'Hola, puedo ayudarte a organizar tus tomas por hora y por día.',
    'Si quieres, empezamos con el nombre del medicamento y la primera dosis.',
    '¡Hola! Puedo guiarte paso a paso para crear tu tratamiento.',
    'Estoy aquí para resolver dudas sobre horarios, dosis y uso general.',
    'Hola, dime qué medicamento tomas y te ayudo a dejarlo programado.',
    'Puedes pedirme cosas como: "Agéndame amoxicilina cada 8 horas".',
    '¡Hola! Si ya tienes datos del medicamento, te ayudo a guardarlo rápido.',
    'Puedo ayudarte a mantener tus tomas al día con recordatorios claros.',
    'Hola, ¿quieres que revisemos tus pendientes de hoy?',
    'También puedo ayudarte a marcar una toma como completada.',
    '¡Hola! Si necesitas cambiar un horario, te ayudo a editarlo.',
    'Estoy listo para ayudarte a organizar tu tratamiento sin complicaciones.',
    'Hola, dime qué necesitas y lo hacemos paso a paso.',
    'Puedes empezar escribiendo: nombre, dosis y cada cuánto lo tomas.',
    '¡Bienvenido! Te ayudo a crear recordatorios fáciles de seguir.',
    'Hola, si tienes dudas con la app, también te explico dónde tocar.',
    'Puedo ayudarte a programar tratamientos diarios o cada varios días.',
    '¡Hola! Si quieres, empezamos con la fecha y hora de la primera toma.',
    'Estoy aquí para ayudarte a no olvidar tus medicamentos.',
    'Hola, vamos a organizar tus medicinas de forma simple.',
    'Si me das los datos básicos, puedo dejar tu medicamento agendado.',
    '¡Hola! Te acompaño para configurar tus horarios de toma.',
    'Puedo ayudarte a mantener un plan de medicación más ordenado.',
    'Hola, ¿programamos tu próximo medicamento?',
  ];

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _tts = FlutterTts();
  bool _isSending = false;
  bool _isSigningIn = false;
  bool _isLoadingAccess = true;
  bool _isPersonalApiKeyActive = false;
  int _messagesUsed = 0;
  int _messageLimit = _maxAllowedMessages;
  int? _speakingAssistantIndex;
  int _assistantAudioToken = 0;
  StreamSubscription<User?>? _authSubscription;
  late final List<_ChatMessage> _messages;

  @override
  void initState() {
    super.initState();
    final welcome = _welcomeOptions[Random().nextInt(_welcomeOptions.length)]
        .trim();
    _messages = [_ChatMessage(text: welcome, fromUser: false)];
    _configureTts();
    _bootstrapChatAccess();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _tts.stop();
    AiChatService.instance.reset();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapChatAccess() async {
    await _refreshApiStatus();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _onAuthChanged(user);
    });
    await _onAuthChanged(FirebaseAuth.instance.currentUser);
  }

  Future<void> _onAuthChanged(User? user) async {
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoadingAccess = false;
        _messagesUsed = 0;
        _messageLimit = _maxAllowedMessages;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isLoadingAccess = true);
    await _refreshApiStatus();
    await _loadUsageForUser(user.uid);
  }

  Future<void> _refreshApiStatus() async {
    await AiChatService.instance.loadApiKeyPreferences();
    if (!mounted) return;
    setState(() {
      _isPersonalApiKeyActive =
          AiChatService.instance.hasPersonalApiKey &&
          AiChatService.instance.isUsingPersonalApiKey;
    });
  }

  Future<void> _loadUsageForUser(String uid) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final currentPeriod = _currentUsagePeriod();
    try {
      final doc = await ref.get();
      final rawUsage = doc.data()?['aiChatUsage'];
      final usage = rawUsage is Map ? rawUsage : const <String, dynamic>{};
      final storedPeriod = (usage['period'] as String?) ?? '';
      final isNewPeriod = storedPeriod != currentPeriod;
      final used = isNewPeriod
          ? 0
          : (usage['messagesUsed'] as num?)?.toInt() ?? 0;
      var max = (usage['maxMessages'] as num?)?.toInt() ?? _maxAllowedMessages;
      if (max <= 0) {
        max = _maxAllowedMessages;
      }

      if (rawUsage is! Map ||
          usage['maxMessages'] == null ||
          usage['period'] == null ||
          isNewPeriod) {
        await ref.set({
          'aiChatUsage': {
            'messagesUsed': used,
            'maxMessages': max,
            'period': currentPeriod,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      setState(() {
        _messagesUsed = used.clamp(0, max);
        _messageLimit = max;
        _isLoadingAccess = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingAccess = false;
        _messagesUsed = 0;
        _messageLimit = _maxAllowedMessages;
      });
    }
  }

  Future<void> _showStatusDialog({
    required String message,
    String title = 'Aviso',
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Entendido',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _signInWithGoogle() async {
    if (_isSigningIn) return;

    final hasInternet = await ConnectivityService.instance
        .hasInternetConnection();
    if (!hasInternet) {
      if (!mounted) return;
      await _showStatusDialog(
        title: 'Sin conexión',
        message:
            'No hay conexión a internet. Verifica tu red e inténtalo de nuevo.',
      );
      return;
    }

    setState(() => _isSigningIn = true);
    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      if (googleAuth.idToken == null) {
        throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'Google no devolvió un idToken.',
        );
      }
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on GoogleSignInException catch (error) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint(
          'Google Sign-In error: code=${error.code.name}, description=${error.description}',
        );
      }
      await _showStatusDialog(
        title: 'Error',
        message: 'No se pudo iniciar sesión con Google. Inténtalo de nuevo.',
      );
    } catch (error) {
      if (!mounted) return;
      await _showStatusDialog(
        title: 'Error',
        message: 'No se pudo iniciar sesión: $error',
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  Future<bool> _consumeUserQuota(String userId) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(userId);
    final currentPeriod = _currentUsagePeriod();
    try {
      final nextCount = await FirebaseFirestore.instance.runTransaction<int>((
        transaction,
      ) async {
        final snap = await transaction.get(ref);
        final rawUsage = snap.data()?['aiChatUsage'];
        final usage = rawUsage is Map ? rawUsage : const <String, dynamic>{};
        final storedPeriod = (usage['period'] as String?) ?? '';
        final used = storedPeriod == currentPeriod
            ? (usage['messagesUsed'] as num?)?.toInt() ?? 0
            : 0;
        var max =
            (usage['maxMessages'] as num?)?.toInt() ?? _maxAllowedMessages;
        if (max <= 0) {
          max = _maxAllowedMessages;
        }
        if (used >= max) {
          throw _MessageLimitReachedException(used: used, max: max);
        }
        final updated = used + 1;
        transaction.set(ref, {
          'aiChatUsage': {
            'messagesUsed': updated,
            'maxMessages': max,
            'period': currentPeriod,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
        return updated;
      });

      if (!mounted) return false;
      setState(() {
        _messagesUsed = nextCount;
      });
      return true;
    } on _MessageLimitReachedException catch (error) {
      if (!mounted) return false;
      setState(() {
        _messagesUsed = error.used;
        _messageLimit = error.max;
      });
      return false;
    } catch (_) {
      if (!mounted) return false;
      await _showStatusDialog(
        title: 'Error',
        message:
            'No se pudo actualizar tu contador de uso en la nube. Intenta de nuevo.',
      );
      return false;
    }
  }

  Future<void> _configureTts() async {
    await _tts.setLanguage('es-ES');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> _toggleAssistantAudio(int messageIndex, String text) async {
    final speakText = _ttsPlainText(text);
    if (speakText.isEmpty) return;

    if (_speakingAssistantIndex == messageIndex) {
      final token = ++_assistantAudioToken;
      await _tts.stop();
      if (!mounted || token != _assistantAudioToken) return;
      setState(() => _speakingAssistantIndex = null);
      return;
    }

    final token = ++_assistantAudioToken;
    await _tts.stop();
    if (!mounted || token != _assistantAudioToken) return;
    setState(() => _speakingAssistantIndex = messageIndex);

    try {
      await _tts.speak(speakText);
      if (!mounted || token != _assistantAudioToken) return;
      setState(() => _speakingAssistantIndex = null);
    } catch (_) {
      if (!mounted || token != _assistantAudioToken) return;
      setState(() => _speakingAssistantIndex = null);
    } finally {
      if (token == _assistantAudioToken) {
        _assistantAudioToken++;
      }
    }
  }

  String _ttsPlainText(String raw) {
    var text = raw;
    text = text.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');
    text = text.replaceAllMapped(
      RegExp(r'\*\*(.*?)\*\*', dotAll: true),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true), '');
    text = text.replaceAll('•', '-');
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _showStatusDialog(
        title: 'Inicia sesión',
        message: 'Debes iniciar sesión con Google para usar el asistente IA.',
      );
      return;
    }

    await _refreshApiStatus();
    final requiresPersonalApiNow =
        _messagesUsed >= _messageLimit && !_isPersonalApiKeyActive;
    if (requiresPersonalApiNow) {
      _appendAssistantNotice(
        'Alcanzaste el límite de $_messageLimit mensajes incluidos. '
        'Para continuar usando el Asistente IA, crea tu API key en https://console.groq.com/ '
        'y luego actívala en Ajustes > Asistente IA.',
      );
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(text: text, fromUser: true));
    });
    _scrollToBottom();

    final hasInternet = await ConnectivityService.instance
        .hasInternetConnection();
    if (!hasInternet) {
      _appendAssistantNotice(
        'No hay conexión a internet. Conéctate para que pueda responderte.',
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final reply = await AiChatService.instance.sendMessage(text);
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: reply, fromUser: false));
      });
      _scrollToBottom();
      if (!_isPersonalApiKeyActive) {
        unawaited(_recordUsageAfterSuccessfulSend(user.uid));
      }
    } catch (error) {
      if (!mounted) return;
      final details = error.toString();
      setState(() {
        _messages.add(
          _ChatMessage(
            text:
                'No pude conectarme con Groq. Verifica tu API key y configuración.\nDetalle: $details',
            fromUser: false,
          ),
        );
      });
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _currentUsagePeriod() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    return '${now.year}-$month';
  }

  void _appendAssistantNotice(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final last = _messages.isNotEmpty ? _messages.last : null;
    final isRepeatedNotice =
        last != null && !last.fromUser && last.text.trim() == trimmed;
    if (isRepeatedNotice) return;
    setState(() {
      _messages.add(_ChatMessage(text: trimmed, fromUser: false));
    });
    _scrollToBottom();
  }

  Future<void> _recordUsageAfterSuccessfulSend(String userId) async {
    final consumed = await _consumeUserQuota(userId);
    if (consumed || !mounted) return;
    _appendAssistantNotice(
      'Alcanzaste el límite de $_messageLimit mensajes incluidos. '
      'Para continuar usando el Asistente IA, crea tu API key en https://console.groq.com/ '
      'y luego actívala en Ajustes > Asistente IA.',
    );
  }

  Future<void> _showHelpDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Symbols.robot_2, size: 38, weight: 600),
                  const SizedBox(width: 10),
                  Image.asset('assets/groq.ico', width: 38, height: 38),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Cómo usar el asistente IA',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: const Text(
            'Puedes escribir en lenguaje natural para agendar medicamentos.\n\n'
            'Ejemplo: "Quiero agendar Ambroxol cada 8 horas, 10 ml, jarabe, primera dosis 8:00 AM, inicio 2026-03-07".\n\n'
            'El asistente te pedirá datos faltantes y, cuando estén completos, guardará el medicamento automáticamente.\n\n'
            'Powered by Groq AI.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Entendido',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showUsageDialog() {
    final remaining = (_messageLimit - _messagesUsed).clamp(0, _messageLimit);
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Uso del asistente',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Mensajes usados este mes: $_messagesUsed/$_messageLimit\n'
            'Mensajes restantes: $remaining\n\n'
            'Si quieres evitar este límite, activa tu API key personal en '
            'Ajustes > Asistente IA.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Entendido',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
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
                  tooltip: 'Atrás',
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          'Asistente IA',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: _showUsageDialog,
            icon: const Icon(Icons.bar_chart_rounded, size: 26),
            tooltip: 'Uso mensual',
          ),
          IconButton(
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline, size: 28),
            tooltip: 'Ayuda',
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            final user = snapshot.data;
            if (user != null && _isLoadingAccess) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF2F80ED)),
              );
            }

            return Column(
              children: [
                if (user == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE1E8F2)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Debes iniciar sesión con Google para usar el Asistente IA.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (isAndroid)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _isSigningIn
                                      ? null
                                      : _signInWithGoogle,
                                  icon: _isSigningIn
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Color(0xFF1F2B3A),
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Image.asset(
                                          'assets/google_logo.ico',
                                          width: 20,
                                          height: 20,
                                        ),
                                  label: Text(
                                    _isSigningIn
                                        ? 'Iniciando sesión...'
                                        : 'Iniciar sesión con Google',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1F2B3A),
                                    side: const BorderSide(
                                      color: Color(0xFFD3DCE9),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (_isSending && index == _messages.length) {
                        return const _TypingBubble();
                      }
                      final message = _messages[index];
                      final isUser = message.fromUser;
                      if (!isUser) {
                        return _AssistantMessageTile(
                          message: message,
                          isSpeaking: _speakingAssistantIndex == index,
                          onAudioTap: () =>
                              _toggleAssistantAudio(index, message.text),
                        );
                      }
                      return Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? const Color(0xFF2F80ED)
                                : const Color(0xFFFFFFFF),
                            borderRadius: BorderRadius.circular(14),
                            border: isUser
                                ? null
                                : Border.all(color: const Color(0xFFE1E8F2)),
                          ),
                          child: _MessageText(message: message),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          cursorColor: const Color(0xFF2F80ED),
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Escribe un mensaje...',
                            filled: true,
                            fillColor: const Color(0xFFF2F5FA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      FilledButton(
                        onPressed: _isSending
                            ? null
                            : (user == null ? () {} : _sendMessage),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2F80ED),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        child: Icon(
                          user == null
                              ? Icons.lock_rounded
                              : Icons.send_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

class _MessageText extends StatelessWidget {
  const _MessageText({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.fromUser;
    final baseStyle = TextStyle(
      color: isUser ? Colors.white : const Color(0xFF22344D),
      fontWeight: FontWeight.w500,
      height: 1.35,
      fontSize: 15,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.text.trim().isNotEmpty)
          isUser
              ? Text(message.text, style: baseStyle)
              : RichText(
                  text: TextSpan(
                    style: baseStyle,
                    children: _markdownSpans(
                      message.text,
                      baseStyle,
                      baseStyle.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
      ],
    );
  }
}

List<TextSpan> _markdownSpans(
  String text,
  TextStyle normalStyle,
  TextStyle boldStyle,
) {
  final spans = <TextSpan>[];
  final lines = text.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();

    if (trimmed == '---') {
      spans.add(
        TextSpan(
          text: '────────',
          style: normalStyle.copyWith(
            color: normalStyle.color?.withValues(alpha: 0.55),
          ),
        ),
      );
    } else {
      final headingMatch = RegExp(
        r'^(#{1,6})\s+(.+)$',
      ).firstMatch(line.trimLeft());
      var content = line;
      var lineStyle = normalStyle;

      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        content = headingMatch.group(2)!;
        final headingSize = switch (level) {
          1 => 21.0,
          2 => 19.0,
          3 => 17.0,
          4 => 16.0,
          _ => 15.0,
        };
        lineStyle = normalStyle.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: headingSize,
          height: 1.25,
          decoration: level >= 3 ? TextDecoration.underline : null,
          decorationThickness: level >= 3 ? 1.4 : null,
        );
      }

      spans.add(
        TextSpan(
          style: lineStyle,
          children: _inlineBoldSpans(
            content,
            lineStyle,
            lineStyle.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    if (i < lines.length - 1) {
      spans.add(TextSpan(text: '\n', style: normalStyle));
    }
  }

  if (spans.isEmpty) {
    spans.add(TextSpan(text: text, style: normalStyle));
  }
  return spans;
}

List<TextSpan> _inlineBoldSpans(
  String text,
  TextStyle normalStyle,
  TextStyle boldStyle,
) {
  final regex = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
  final spans = <TextSpan>[];
  var start = 0;

  for (final match in regex.allMatches(text)) {
    if (match.start > start) {
      spans.add(
        TextSpan(text: text.substring(start, match.start), style: normalStyle),
      );
    }
    final boldText = match.group(1);
    if (boldText != null && boldText.isNotEmpty) {
      spans.add(TextSpan(text: boldText, style: boldStyle));
    } else {
      spans.add(TextSpan(text: match.group(0), style: normalStyle));
    }
    start = match.end;
  }

  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start), style: normalStyle));
  }

  if (spans.isEmpty) {
    spans.add(TextSpan(text: text, style: normalStyle));
  }

  return spans;
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Symbols.robot_2, size: 26, weight: 600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 2),
                child: Text(
                  'Asistente IA',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2B3A),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.74,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE1E8F2)),
                ),
                child: const Text(
                  'Escribiendo...',
                  style: TextStyle(
                    color: Color(0xFF5F7190),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssistantMessageTile extends StatelessWidget {
  const _AssistantMessageTile({
    required this.message,
    required this.isSpeaking,
    required this.onAudioTap,
  });

  final _ChatMessage message;
  final bool isSpeaking;
  final VoidCallback onAudioTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Symbols.robot_2, size: 26, weight: 600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 2),
                child: Text(
                  'Asistente IA',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2B3A),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.74,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE1E8F2)),
                ),
                child: _MessageText(message: message),
              ),
              const SizedBox(height: 4),
              IconButton(
                tooltip: isSpeaking ? 'Detener audio' : 'Escuchar audio',
                onPressed: onAudioTap,
                icon: Icon(
                  isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up,
                  color: const Color(0xFF1A1A1A).withValues(alpha: 0.75),
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageLimitReachedException implements Exception {
  const _MessageLimitReachedException({required this.used, required this.max});

  final int used;
  final int max;
}
