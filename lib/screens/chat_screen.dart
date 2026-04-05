import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ciaccola_frontend/models/chat_message.dart';
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/services/database_service.dart';
import 'package:ciaccola_frontend/services/socket_signaling_service.dart';
import 'package:ciaccola_frontend/services/webrtc_service.dart';
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
  final _db = DatabaseService();
  final _signaling = SocketSignalingService();
  final _webrtc = WebRtcService();
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
  bool _offerSent = false;
  late bool _isInitiator;

  String get _roomId {
    final ids = [widget.currentUserId, widget.contact.id]..sort();
    return ids.join('_');
  }

  @override
  void initState() {
    super.initState();
    _isInitiator = widget.currentUserId.compareTo(widget.contact.id) < 0;
    _init();
  }

  Future<void> _init() async {
    await _loadMessages();
    await _webrtc.init(createDataChannel: true);
    _bindWebRtc();
    _bindSignaling();
    if (!_signaling.connected) {
      _signaling.connect(token: widget.token);
    }
    _signaling.joinRoom(_roomId);
    if (mounted) setState(() => _busy = false);
  }

  void _bindWebRtc() {
    _subs.add(_webrtc.onCandidate.listen((candidate) {
      _signaling.sendIceCandidate(
        room: _roomId,
        from: widget.currentUserId,
        candidate: candidate.toMap(),
      );
    }));

    _subs.add(_webrtc.onState.listen((state) async {
      if (!mounted) return;
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          setState(() => _status = 'Online');
          await _flushQueuedMessages();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          setState(() => _status = 'Peer offline');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          setState(() => _status = 'Connection failed');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          setState(() => _status = 'Connecting...');
          break;
        default:
          break;
      }
    }));

    _subs.add(_webrtc.onChannelState.listen((state) async {
      if (!mounted) return;
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        setState(() => _status = 'Online');
        await _flushQueuedMessages();
      } else if (state == RTCDataChannelState.RTCDataChannelClosing ||
          state == RTCDataChannelState.RTCDataChannelClosed) {
        setState(() => _status = 'Peer offline');
      }
    }));

    _subs.add(_webrtc.onMessage.listen((payload) async {
      final type = payload['type']?.toString() ?? 'text';
      if (type == 'text') {
        final message = ChatMessage(
          messageId: payload['messageId'].toString(),
          contactId: widget.contact.id,
          text: payload['text'].toString(),
          timestamp: payload['timestamp'] is int
              ? payload['timestamp'] as int
              : DateTime.now().millisecondsSinceEpoch,
          isSentByMe: false,
          isQueued: false,
          deleted: false,
        );
        await _db.insertMessage(message);
        await _loadMessages();
      } else if (type == 'delete') {
        await _db.deleteForMeAndHide(payload['messageId'].toString());
        await _loadMessages();
      }
    }));
  }

  void _bindSignaling() {
    _subs.add(_signaling.onConnect.listen((_) async {
      debugPrint('[ChatScreen] signaling connected in room $_roomId');
      if (mounted) setState(() => _status = 'Signaling connected');
    }));

    _subs.add(_signaling.onRoomJoined.listen((joinedRoom) async {
      if (joinedRoom == _roomId && _isInitiator && !_offerSent) {
        _offerSent = true;
        final offer = await _webrtc.createOffer();
        debugPrint('[ChatScreen] sending local offer after joining room');
        _signaling.sendOffer(room: _roomId, from: widget.currentUserId, offer: offer);
      }
    }));

    _subs.add(_signaling.onUserJoined.listen((data) async {
      final joinedId = data['userId']?.toString();
      debugPrint('[ChatScreen] peer joined room: $joinedId');
      if (joinedId == widget.contact.id && _isInitiator) {
        final offer = await _webrtc.createOffer();
        debugPrint('[ChatScreen] sending offer because peer joined');
        _signaling.sendOffer(room: _roomId, from: widget.currentUserId, offer: offer);
        _offerSent = true;
      }
    }));

    _subs.add(_signaling.onDisconnect.listen((_) {
      if (mounted) setState(() => _status = 'Signaling offline');
    }));

    _subs.add(_signaling.onOffer.listen((data) async {
      final from = data['from']?.toString();
      debugPrint('[ChatScreen] offer event from $from: $data');
      if (from != null && from != widget.contact.id) return;
      try {
        await _webrtc.applyRemoteOffer(data);
        final answer = await _webrtc.createAnswer();
        debugPrint('[ChatScreen] sending answer');
        _signaling.sendAnswer(room: _roomId, from: widget.currentUserId, answer: answer);
      } catch (e, st) {
        debugPrint('[ChatScreen] offer handling failed: $e');
        debugPrint(st.toString());
      }
    }));

    _subs.add(_signaling.onAnswer.listen((data) async {
      final from = data['from']?.toString();
      debugPrint('[ChatScreen] answer event from $from: $data');
      if (from != null && from != widget.contact.id) return;
      try {
        await _webrtc.applyRemoteAnswer(data);
      } catch (e, st) {
        debugPrint('[ChatScreen] answer handling failed: $e');
        debugPrint(st.toString());
      }
    }));

    _subs.add(_signaling.onCandidate.listen((data) async {
      final from = data['from']?.toString();
      debugPrint('[ChatScreen] candidate event from $from: $data');
      if (from != null && from != widget.contact.id) return;
      try {
        await _webrtc.addRemoteCandidate(data);
      } catch (e, st) {
        debugPrint('[ChatScreen] remote candidate failed: $e');
        debugPrint(st.toString());
      }
    }));

    _subs.add(_signaling.onTyping.listen((username) {
      if (!mounted) return;
      setState(() {
        _peerTyping = true;
      });
      _typingDisplayTimer?.cancel();
      _typingDisplayTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _peerTyping = false);
      });
    }));

    _subs.add(_signaling.onStopTyping.listen((_) {
      if (!mounted) return;
      setState(() => _peerTyping = false);
    }));

    _subs.add(_signaling.onDelete.listen((data) async {
      if (data['from']?.toString() != widget.contact.id) return;
      await _db.deleteForMeAndHide(data['messageId'].toString());
      await _loadMessages();
    }));
  }

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

    final message = ChatMessage(
      messageId: _uuid.v4(),
      contactId: widget.contact.id,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSentByMe: true,
      isQueued: !_webrtc.isReady,
      deleted: false,
    );

    await _db.insertMessage(message);
    _controller.clear();
    await _loadMessages();

    if (_webrtc.isReady) {
      debugPrint('[ChatScreen] sending message over data channel: ${message.messageId}');
      await _webrtc.sendJson({
        'type': 'text',
        'messageId': message.messageId,
        'text': message.text,
        'timestamp': message.timestamp,
      });
      await _db.markMessageDelivered(message.messageId);
      await _loadMessages();
    } else {
      debugPrint('[ChatScreen] data channel not ready, queuing message: ${message.messageId}');
    }
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

  Future<void> _flushQueuedMessages() async {
    final queued = await _db.getQueuedMessages(widget.contact.id);
    for (final message in queued) {
      if (!_webrtc.isReady) break;
      await _webrtc.sendJson({
        'type': 'text',
        'messageId': message.messageId,
        'text': message.text,
        'timestamp': message.timestamp,
      });
      await _db.markMessageDelivered(message.messageId);
    }
    await _loadMessages();
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    await _db.deleteForMeAndHide(message.messageId);
    await _loadMessages();

    if (_webrtc.isReady) {
      await _webrtc.sendJson({'type': 'delete', 'messageId': message.messageId});
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
        content: const Text('This removes the message from both devices when the peer receives the delete event.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await _deleteMessage(message);
    }
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
    _webrtc.close();
    _webrtc.dispose();
    super.dispose();
  }

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
                    itemBuilder: (_, index) {
                      final message = _messages[index];
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
                              crossAxisAlignment:
                                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.text,
                                  style: const TextStyle(color: Colors.white),
                                ),
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
                    },
                  ),
                ),
                SafeArea(
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
                ),
              ],
            ),
    );
  }
}
