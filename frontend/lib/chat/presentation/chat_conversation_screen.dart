import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:frontend/chat/data/chat_models.dart';
import 'package:frontend/chat/data/chat_repository.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/di/injection.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChatConversationScreen extends StatefulWidget {
  const ChatConversationScreen({
    super.key,
    required this.contact,
    required this.currentUserId,
  });

  final ChatContact contact;
  final String currentUserId;

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _repository = getIt<ChatRepository>();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isLoadingHistory = true;
  bool _isClosing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    if (_isConnecting || _isConnected) return;
    setState(() {
      _isConnecting = true;
      _isLoadingHistory = true;
      _error = null;
    });

    try {
      final initialHistory = await _repository.getHistory(widget.contact.id);
      if (!mounted) return;
      _addMessages(initialHistory);

      final channel = await _repository.connect(widget.contact.id);
      if (!mounted) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleSocketData,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _isConnected = false;
            _isLoadingHistory = false;
            _error = 'Chat connection failed. Try reconnecting.';
          });
        },
        onDone: () {
          if (!mounted || _isClosing) return;
          setState(() {
            _isConnected = false;
            _isLoadingHistory = false;
            _error ??= 'Chat disconnected. Reconnect to continue.';
          });
        },
      );
    } on ChatException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
        _error = error.message;
      });
    } on WebSocketChannelException {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
        _error =
            'Could not connect to chat. Check your connection and try again.';
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
        _error = error.message;
      });
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _handleSocketData(dynamic data) {
    if (data is! String) {
      setState(() => _error = 'Received an invalid chat response.');
      return;
    }

    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        setState(() => _error = 'Received an invalid chat response.');
        return;
      }
      switch (decoded['type']) {
        case 'ready':
          setState(() {
            _isConnected = true;
            _error = null;
          });
          _loadHistory();
        case 'message':
          final messageData = decoded['message'];
          if (messageData is! Map) {
            setState(() => _error = 'Received an invalid chat message.');
            return;
          }
          _addMessages([
            ChatMessage.fromJson(Map<String, dynamic>.from(messageData)),
          ]);
        case 'error':
          final detail = decoded['detail'];
          setState(() {
            _error = detail is String ? detail : 'Chat request failed.';
          });
      }
    } on FormatException {
      setState(() => _error = 'Received an invalid chat response.');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _repository.getHistory(widget.contact.id);
      if (!mounted) return;
      _addMessages(history);
    } on ChatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
      });
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  void _addMessages(Iterable<ChatMessage> newMessages) {
    final messagesById = {for (final message in _messages) message.id: message};
    for (final message in newMessages) {
      final isThisConversation =
          (message.senderId == widget.currentUserId &&
              message.recipientId == widget.contact.id) ||
          (message.senderId == widget.contact.id &&
              message.recipientId == widget.currentUserId);
      if (isThisConversation) messagesById[message.id] = message;
    }
    final sortedMessages = messagesById.values.toList()
      ..sort((first, second) => first.createdAt.compareTo(second.createdAt));
    setState(() {
      _messages
        ..clear()
        ..addAll(sortedMessages);
    });
    _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty || content.length > 4000 || !_isConnected) return;
    try {
      _channel?.sink.add(jsonEncode({'type': 'message', 'content': content}));
    } on StateError {
      setState(() {
        _isConnected = false;
        _error = 'Chat disconnected. Reconnect to continue.';
      });
      return;
    }
    _messageController.clear();
  }

  @override
  void dispose() {
    _isClosing = true;
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close());
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.contact.name),
            Text(
              _isConnected ? 'Connected' : 'Connecting…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _isConnected ? AppTheme.gold : AppTheme.muted,
              ),
            ),
          ],
        ),
        actions: [
          if (!_isConnected)
            IconButton(
              onPressed: _isConnecting ? null : _connect,
              tooltip: 'Reconnect',
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: _buildMessages()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: _isConnected,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 4000,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Write a message',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isConnected ? _sendMessage : null,
                    tooltip: 'Send message',
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_isLoadingHistory && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _isConnected
                ? 'Start the conversation with ${widget.contact.name}.'
                : 'Connect to start chatting.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMine = message.senderId == widget.currentUserId;
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMine ? AppTheme.goldDark : AppTheme.elevated,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(message.content),
                ),
                const SizedBox(height: 4),
                Text(
                  TimeOfDay.fromDateTime(message.createdAt.toLocal())
                      .format(context),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
