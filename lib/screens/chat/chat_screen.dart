import 'package:flutter/material.dart';
import 'package:mis_medicamentos/services/ai_chat_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      text:
          'Hola, soy tu asistente. Puedes escribirme algo como: "Agéndame paracetamol cada 8 horas".',
      fromUser: false,
    ),
  ];

  @override
  void dispose() {
    AiChatService.instance.reset();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(text: text, fromUser: true));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final reply = await AiChatService.instance.sendMessage(text);
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: reply, fromUser: false));
      });
      _scrollToBottom();
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

  Future<void> _showHelpDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image(
                image: AssetImage('assets/gpt.ico'),
                width: 38,
                height: 38,
                fit: BoxFit.contain,
              ),
              SizedBox(height: 10),
              Text(
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
            'Powered by ChatGPT of OpenAI.',
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
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline, size: 28),
            tooltip: 'Ayuda',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
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
                    return _AssistantMessageTile(message: message);
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
                    onPressed: _isSending ? null : _sendMessage,
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
                    child: const Icon(Icons.send_rounded, color: Colors.white),
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
          child: ClipOval(
            child: Image.asset(
              'assets/gpt.ico',
              width: 30,
              height: 30,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 2),
                child: Text(
                  'ChatGPT',
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
  const _AssistantMessageTile({required this.message});

  final _ChatMessage message;

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
          child: ClipOval(
            child: Image.asset(
              'assets/gpt.ico',
              width: 30,
              height: 30,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 2),
                child: Text(
                  'ChatGPT',
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
            ],
          ),
        ),
      ],
    );
  }
}
