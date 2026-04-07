import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ciaccola_frontend/models/chat_message.dart';
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/services/connection_manager.dart';
import 'package:ciaccola_frontend/services/database_service.dart';
import 'package:ciaccola_frontend/services/socket_signaling_service.dart';
import 'package:uuid/uuid.dart';

class ChatScreen extends StatefulWidget {
  final String token;
  final String currentUserId;
  final Contact contact;

  const ChatScreen({
    super.key,
    required this.token,
    required this.currentUserId,
    required this.contact,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _manager = ConnectionManager();
  final _signaling = SocketSignalingService(); // typing only
  final _db = DatabaseService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _uuid = const Uuid();

  final List<StreamSubscription> _subs = [];
  List<ChatMessage> _messages = [];
  String _status = 'Connecting...';
  bool _busy = true;
  bool _peerTyping = false;
  bool _typingSent = false;
  Timer? _typingStopTimer;
  Timer? _typingDisplayTimer;

  String get _roomId {
    final ids = [widget.currentUserId, widget.contact.id]..sort();
    return ids.join('_');
  }

  @override
  void initState() {
    super.initState();
    // Reflect current connection state immediately.
    _status = _manager.isChannelReady(widget.contact.id) ? 'Online' : 'Connecting...';
    _init();
  }

  Future<void> _init() async {
    await _loadMessages();
    _bindEvents();
    // If the channel is already open (e.g. we navigated away and back),
    // flush any messages that were queued while disconnected.
    await _manager.flushIfReady(widget.contact.id);
    if (mounted) setState(() => _busy = false);
  }

  // -------------------------------------------------------------------------
  // Event subscriptions
  // -------------------------------------------------------------------------

  void _listen<T>(Stream<T> stream, void Function(T) onData) {
    _subs.add(stream.listen(onData));
  }

  void _bindEvents() {
    // Filter manager events to this contact only.
    final contactEvents = _manager.events
        .where((e) => e.contactId == widget.contact.id);

    _listen(contactEvents, (event) async {
      if (!mounted) return;
      if (event is IncomingMessageEvent || event is MessagesDeliveredEvent) {
        await _loadMessages();
      } else if (event is MessageDeletedEvent) {
        await _loadMessages();
      } else if (event is PeerStateChangedEvent) {
        _updateStatusFromPeerState(event.state);
      } else if (event is ChannelStateChangedEvent) {
        _updateStatusFromChannelState(event.state);
      }
    });

    // Typing indicators are UI-only — stay in ChatScreen.
    _listen(_signaling.onTyping, (_) {
      if (!mounted) return;
      setState(() => _peerTyping = true);
      _typingDisplayTimer?.cancel();
      _typingDisplayTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _peerTyping = false);
      });
    });

    _listen(_signaling.onStopTyping, (_) {
      if (mounted) setState(() => _peerTyping = false);
    });
  }

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  void _updateStatusFromPeerState(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _setStatus('Online');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _setStatus('Peer offline');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _setStatus('Connection failed');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        _setStatus('Connecting...');
        break;
      default:
        break;
    }
  }

  void _updateStatusFromChannelState(RTCDataChannelState state) {
    if (state == RTCDataChannelState.RTCDataChannelOpen) {
      _setStatus('Online');
    } else if (state == RTCDataChannelState.RTCDataChannelClosing ||
        state == RTCDataChannelState.RTCDataChannelClosed) {
      _setStatus('Peer offline');
    }
  }

  // -------------------------------------------------------------------------
  // Message actions
  // -------------------------------------------------------------------------

  Future<void> _loadMessages() async {
    final items = await _db.getMessages(widget.contact.id);
    if (!mounted) return;
    setState(() => _messages = items);
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _typingStopTimer?.cancel();
    if (_typingSent) {
      _signaling.sendStopTyping(room: _roomId);
      _typingSent = false;
    }

    // Always save as queued first; mark delivered only after successful send.
    final message = ChatMessage(
      messageId: _uuid.v4(),
      contactId: widget.contact.id,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSentByMe: true,
      isQueued: true,
      deleted: false,
    );

    await _db.insertMessage(message);
    _controller.clear();

    if (_manager.isChannelReady(widget.contact.id)) {
      try {
        await _manager.sendJson(widget.contact.id, {
          'type': 'text',
          'messageId': message.messageId,
          'text': message.text,
          'timestamp': message.timestamp,
        });
        await _db.markMessageDelivered(message.messageId);
      } catch (_) {
        // Channel closed between the ready-check and send — stays queued,
        // will be flushed automatically when the channel reopens.
      }
    }

    await _loadMessages();
  }

  void _onTextChanged(String value) {
    if (!_signaling.connected) return;
    if (!_typingSent) {
      _signaling.sendTyping(room: _roomId);
      _typingSent = true;
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), () {
      _signaling.sendStopTyping(room: _roomId);
      _typingSent = false;
    });
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    await _db.deleteForMeAndHide(message.messageId);
    await _loadMessages();

    if (_manager.isChannelReady(widget.contact.id)) {
      await _manager.sendJson(widget.contact.id, {
        'type': 'delete',
        'messageId': message.messageId,
      });
    } else if (_signaling.connected) {
      _signaling.sendDelete(
        to: widget.contact.id,
        from: widget.currentUserId,
        messageId: message.messageId,
      );
    }
  }

  Future<void> _showDeleteDialog(ChatMessage message) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete for both'),
        content: const Text(
          'This removes the message from both devices when the peer receives the delete event.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) await _deleteMessage(message);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _typingStopTimer?.cancel();
    _typingDisplayTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    // Do NOT close/dispose the peer — ConnectionManager owns it.
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.contact.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _peerTyping ? 'Typing...' : _status,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length,
                    itemBuilder: (_, index) => _buildMessageBubble(_messages[index]),
                  ),
                ),
                _buildInputBar(),
              ],
            ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final mine = message.isSentByMe;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showDeleteDialog(message),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: mine ? Colors.blue.shade800 : Colors.grey.shade700,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(message.text, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 4),
              Text(
                message.isQueued ? 'Queued' : 'Sent',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  border: OutlineInputBorder(),
                ),
                onChanged: _onTextChanged,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _sendMessage,
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
