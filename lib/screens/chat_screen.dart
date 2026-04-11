import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:ciaccola_frontend/models/chat_message.dart';
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/configs/api_config.dart';
import 'package:ciaccola_frontend/widgets/user_avatar.dart';
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
  final _signaling = SocketSignalingService();
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

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isStartingRecording = false; // true while _startRecording() is in-flight
  bool _recordCancelled = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  double _dragOffset = 0;
  static const double _cancelThreshold = 80;

  String get _roomId {
    final ids = [widget.currentUserId, widget.contact.id]..sort();
    return ids.join('_');
  }

  bool get _isPremium => _manager.isPremium;

  @override
  void initState() {
    super.initState();
    _manager.activeChatContactId = widget.contact.id;
    _status = _manager.isChannelReady(widget.contact.id) ? 'Online' : 'Connecting...';
    _init();
  }

  Future<void> _init() async {
    await _loadMessages();
    _bindEvents();
    await _manager.flushIfReady(widget.contact.id);
    if (mounted) setState(() => _busy = false);
    _recorder.hasPermission().ignore();
  }

  void _listen<T>(Stream<T> stream, void Function(T) onData) {
    _subs.add(stream.listen(onData));
  }

  void _bindEvents() {
    final contactEvents =
        _manager.events.where((e) => e.contactId == widget.contact.id);

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
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _setStatus('Peer offline');
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _setStatus('Connection failed');
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        _setStatus('Connecting...');
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
      } catch (_) {}
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

  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  Future<void> _startRecording() async {
    if (_isRecording || _isStartingRecording) return;
    _isStartingRecording = true;

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied.')),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access microphone: $e')),
        );
      }
      _isStartingRecording = false;
      return;
    }

    final String path;
    if (kIsWeb) {
      path = '';
    } else {
      final dir = await getTemporaryDirectory();
      final ext = _isDesktop ? 'ogg' : 'aac';
      path = '${dir.path}/rec_${_uuid.v4()}.$ext';
    }
    final encoder = (kIsWeb || _isDesktop) ? AudioEncoder.opus : AudioEncoder.aacLc;

    try {
      await _recorder.start(
        RecordConfig(encoder: encoder, bitRate: 64000, sampleRate: 48000),
        path: path,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
      _isStartingRecording = false;
      return;
    }

    setState(() {
      _isRecording = true;
      _isStartingRecording = false;
      _recordCancelled = false;
      _recordSeconds = 0;
      _dragOffset = 0;
    });

    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() { _isRecording = false; _dragOffset = 0; });

    if (!send || path == null || _recordCancelled) {
      if (path != null && !kIsWeb) File(path).deleteSync();
      return;
    }

    await _sendAudio(path);
  }

  Future<void> _sendAudio(String filePath) async {
    final Uint8List bytes;
    if (kIsWeb) {
      final response = await http.get(Uri.parse(filePath));
      bytes = response.bodyBytes;
    } else {
      bytes = await File(filePath).readAsBytes();
    }
    final base64Audio = base64Encode(bytes);
    if (!kIsWeb) File(filePath).deleteSync();
    final messageId = _uuid.v4();
    final ts = DateTime.now().millisecondsSinceEpoch;

    final ext = filePath.endsWith('.ogg') ? 'ogg' : (filePath.endsWith('.aac') ? 'aac' : 'webm');
    final mime = ext == 'ogg' ? 'audio/ogg' : (ext == 'aac' ? 'audio/aac' : 'audio/webm');
    final localAudioPath = 'data:$mime;base64,$base64Audio';

    final message = ChatMessage(
      messageId: messageId,
      contactId: widget.contact.id,
      text: '',
      timestamp: ts,
      isSentByMe: true,
      isQueued: true,
      deleted: false,
      audioPath: localAudioPath,
    );

    await _db.insertMessage(message);

    if (_manager.isChannelReady(widget.contact.id)) {
      try {
        await _manager.sendJson(widget.contact.id, {
          'type': 'audio',
          'messageId': messageId,
          'audioBase64': base64Audio,
          'timestamp': ts,
        });
        await _db.markMessageDelivered(messageId);
      } catch (_) {}
    }

    await _loadMessages();
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    await _db.deleteForMeAndHide(message.messageId);
    await _loadMessages();

    http.delete(
      Uri.parse('${ApiConfig.baseHttpUrl}/api/messages/$_roomId/${message.messageId}'),
      headers: {'Authorization': 'Bearer ${widget.token}'},
    ).catchError((_) => http.Response('', 500));

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
        title: const Text('Delete message'),
        content: const Text(
          'This will delete the message for both you and the recipient.',
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
    if (_manager.activeChatContactId == widget.contact.id) {
      _manager.activeChatContactId = null;
    }
    for (final sub in _subs) {
      sub.cancel();
    }
    _typingStopTimer?.cancel();
    _typingDisplayTimer?.cancel();
    _recordTimer?.cancel();
    _recorder.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(
              name: widget.contact.name,
              photo: widget.contact.photo,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Text(widget.contact.name),
          ],
        ),
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
                    itemBuilder: (_, i) => _buildBubble(_messages[i]),
                  ),
                ),
                _buildInputBar(),
              ],
            ),
    );
  }

  String _formatBubbleTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildBubble(ChatMessage message) {
    final mine = message.isSentByMe;
    final theme = Theme.of(context);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: mine ? () => _showMessageOptions(message) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: mine ? theme.colorScheme.primary : theme.colorScheme.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              message.isAudio
                  ? _AudioPlayer(path: message.audioPath!)
                  : Text(message.text,
                      style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatBubbleTime(message.timestamp),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.white60),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.isQueued ? Icons.access_time : Icons.done_all,
                      size: 13,
                      color: Colors.white60,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete message',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteDialog(message);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    if (_isRecording) return _buildRecordingBar();

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
            if (_isPremium) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Hold to record',
                child: GestureDetector(
                  onTapDown: (_isRecording || _isStartingRecording) ? null : (_) => _startRecording(),
                  onLongPressEnd: (_) => _stopRecording(send: !_recordCancelled),
                  onTap: (_isRecording || _isStartingRecording) ? () => _stopRecording(send: true) : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingBar() {
    return SafeArea(
      top: false,
      child: GestureDetector(
        onHorizontalDragUpdate: (d) {
          setState(() => _dragOffset =
              (_dragOffset + d.delta.dx.abs()).clamp(0, _cancelThreshold + 10));
        },
        onHorizontalDragEnd: (_) =>
            _stopRecording(send: _dragOffset < _cancelThreshold),
        child: Container(
          height: 72,
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const _PulsingDot(),
              const SizedBox(width: 12),
              Text(
                _formatDuration(_recordSeconds),
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const Spacer(),
              // Cancel
              GestureDetector(
                onTap: () {
                  _recordCancelled = true;
                  _stopRecording(send: false);
                },
                child: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 28),
              ),
              const SizedBox(width: 16),
              // Send
              GestureDetector(
                onTap: () => _stopRecording(send: true),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _AudioPlayer extends StatefulWidget {
  final String path;
  const _AudioPlayer({required this.path});

  @override
  State<_AudioPlayer> createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<_AudioPlayer> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _playing = false; _position = Duration.zero; });
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () async {
            if (_playing) {
              await _player.pause();
            } else {
              final source = (widget.path.startsWith('data:') || widget.path.startsWith('blob:'))
                  ? UrlSource(widget.path)
                  : DeviceFileSource(widget.path);
              await _player.play(source);
            }
          },
          child: Icon(
            _playing ? Icons.pause_circle : Icons.play_circle,
            color: Colors.white,
            size: 36,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  trackHeight: 3,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: (v) async {
                    final pos = _duration * v;
                    await _player.seek(pos);
                  },
                  activeColor: Colors.white,
                  inactiveColor: Colors.white38,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${_fmt(_position)} / ${_fmt(_duration)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
