import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ciaccola_frontend/models/chat_message.dart';
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/services/database_service.dart';
import 'package:ciaccola_frontend/services/socket_signaling_service.dart';
import 'package:ciaccola_frontend/services/webrtc_service.dart';

abstract class ConnectionEvent {
  final String contactId;
  const ConnectionEvent(this.contactId);
}

class IncomingMessageEvent extends ConnectionEvent {
  final ChatMessage message;
  IncomingMessageEvent(this.message) : super(message.contactId);
}

class MessageDeletedEvent extends ConnectionEvent {
  final String messageId;
  const MessageDeletedEvent({required String contactId, required this.messageId})
      : super(contactId);
}

class MessagesDeliveredEvent extends ConnectionEvent {
  const MessagesDeliveredEvent(super.contactId);
}

class ContactOfflineEvent extends ConnectionEvent {
  const ContactOfflineEvent(super.contactId);
}

class ContactInviteReceivedEvent extends ConnectionEvent {
  final String fromUsername;
  ContactInviteReceivedEvent(this.fromUsername) : super(fromUsername);
}

class ContactAcceptedEvent extends ConnectionEvent {
  final String byUsername;
  ContactAcceptedEvent(this.byUsername) : super(byUsername);
}

class PeerStateChangedEvent extends ConnectionEvent {
  final RTCPeerConnectionState state;
  const PeerStateChangedEvent({required String contactId, required this.state})
      : super(contactId);
}

class ChannelStateChangedEvent extends ConnectionEvent {
  final RTCDataChannelState state;
  const ChannelStateChangedEvent({required String contactId, required this.state})
      : super(contactId);
}

class TypingEvent extends ConnectionEvent {
  const TypingEvent(super.contactId);
}

class StopTypingEvent extends ConnectionEvent {
  const StopTypingEvent(super.contactId);
}

class ConnectionManager {
  static final _instance = ConnectionManager._internal();
  factory ConnectionManager() => _instance;
  ConnectionManager._internal();

  final _signaling = SocketSignalingService();
  final _db = DatabaseService();

  String? _currentUserId;
  String? _token;

  final Map<String, WebRtcService> _peers = {};

  final Map<String, String> _rooms = {};

  final Map<String, bool> _isInitiator = {};

  final Set<String> _offerSent = {};

  final Set<String> _sendingOffer = {};

  final List<StreamSubscription> _subs = [];

  final Map<String, List<StreamSubscription>> _peerSubs = {};

  final _eventsController = StreamController<ConnectionEvent>.broadcast();

  Stream<ConnectionEvent> get events => _eventsController.stream;

  bool get isRunning => _currentUserId != null;
  String? get currentUserId => _currentUserId;

  String? activeChatContactId;

  bool isPremium = false;

  Future<void> start({
    required String currentUserId,
    required String token,
    required List<Contact> contacts,
  }) async {
    if (_currentUserId != null) {
      for (final c in contacts) {
        if (!_rooms.containsKey(c.id)) _addContact(c);
      }
      return;
    }

    _currentUserId = currentUserId;
    _token = token;
    await _db.switchUser(currentUserId);

    if (!_signaling.connected) {
      _signaling.connect(token: token);
    }

    _bindSignaling();

    _signaling.joinRoom('user_$currentUserId');

    for (final contact in contacts) {
      _addContact(contact);
    }
  }

  void addContact(Contact contact) {
    if (_currentUserId == null) return;
    if (!_rooms.containsKey(contact.id)) _addContact(contact);
  }

  void reconnect(String token) {
    if (_currentUserId == null) return;
    if (_signaling.connected) return;
    _signaling.connect(token: token);
    _signaling.joinRoom('user_$_currentUserId');
    for (final roomId in _rooms.values) {
      _signaling.joinRoom(roomId);
    }
  }

  void stop() {
    if (_currentUserId != null) {
      for (final entry in _rooms.entries) {
        _signaling.sendUserOffline(room: entry.value, from: _currentUserId!);
      }
    }

    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();

    for (final subs in _peerSubs.values) {
      for (final s in subs) {
        s.cancel();
      }
    }
    _peerSubs.clear();

    for (final peer in _peers.values) {
      peer.dispose();
    }
    _peers.clear();
    _rooms.clear();
    _isInitiator.clear();
    _offerSent.clear();
    _sendingOffer.clear();
    _currentUserId = null;
    _token = null;

    _signaling.disconnect();
  }

  WebRtcService? getPeer(String contactId) => _peers[contactId];

  bool isChannelReady(String contactId) =>
      _peers[contactId]?.isReady ?? false;

  Future<void> flushIfReady(String contactId) async {
    final peer = _peers[contactId];
    if (peer != null && peer.isReady) {
      await _flushQueuedMessages(contactId, peer);
    }
  }

  void sendTyping(String contactId) {
    final room = _rooms[contactId];
    if (room == null) return;
    _signaling.sendTyping(room: room);
  }

  void sendStopTyping(String contactId) {
    final room = _rooms[contactId];
    if (room == null) return;
    _signaling.sendStopTyping(room: room);
  }

  Future<void> sendDeleteMessage(String contactId, String messageId) async {
    if (isChannelReady(contactId)) {
      await sendJson(contactId, {'type': 'delete', 'messageId': messageId});
    } else if (_signaling.connected && _currentUserId != null) {
      _signaling.sendDelete(
        to: contactId,
        from: _currentUserId!,
        messageId: messageId,
      );
    }
  }

  Future<String> _saveIncomingAudio(String messageId, String base64Data) async {
    if (kIsWeb) {
      return 'data:audio/ogg;base64,$base64Data';
    }
    final dir = await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/audio_$messageId.ogg');
    await file.writeAsBytes(base64Decode(base64Data));
    return file.path;
  }

  Future<void> sendJson(String contactId, Map<String, dynamic> payload) async {
    final peer = _peers[contactId];
    if (peer == null || !peer.isReady) throw Exception('Data channel not open');
    await peer.sendJson(payload);
  }

  void _addContact(Contact contact) {
    final ids = [_currentUserId!, contact.id]..sort();
    final roomId = ids.join('_');
    _rooms[contact.id] = roomId;
    _isInitiator[contact.id] = _currentUserId!.compareTo(contact.id) < 0;
    _signaling.joinRoom(roomId);
  }

  String? _contactIdForRoom(String room) {
    for (final entry in _rooms.entries) {
      if (entry.value == room) return entry.key;
    }
    return null;
  }

  Future<WebRtcService> _getOrCreatePeer(String contactId) async {
    if (_peers.containsKey(contactId)) return _peers[contactId]!;
    final peer = WebRtcService();
    final isInit = _isInitiator[contactId] ?? false;
    await peer.init(createDataChannel: isInit);
    _peers[contactId] = peer;
    _bindPeer(contactId, peer);
    return peer;
  }

  void _cancelPeerSubs(String contactId) {
    final subs = _peerSubs.remove(contactId);
    if (subs != null) {
      for (final s in subs) {
        s.cancel();
      }
    }
  }

  void _bindPeer(String contactId, WebRtcService peer) {
    _cancelPeerSubs(contactId);
    final subs = <StreamSubscription>[];
    _peerSubs[contactId] = subs;

    subs.add(peer.onCandidate.listen((candidate) {
      final room = _rooms[contactId];
      if (room == null || _currentUserId == null) return;
      _signaling.sendIceCandidate(
        room: room,
        from: _currentUserId!,
        candidate: candidate.toMap(),
      );
    }));

    subs.add(peer.onState.listen((state) {
      _emit(PeerStateChangedEvent(contactId: contactId, state: state));
    }));

    subs.add(peer.onChannelState.listen((state) async {
      _emit(ChannelStateChangedEvent(contactId: contactId, state: state));
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        await _flushQueuedMessages(contactId, peer);
      }
    }));

    subs.add(peer.onMessage.listen((payload) async {
      final type = payload['type']?.toString() ?? 'text';
      final ts = payload['timestamp'] is int
          ? payload['timestamp'] as int
          : DateTime.now().millisecondsSinceEpoch;

      if (type == 'text') {
        final message = ChatMessage(
          messageId: payload['messageId'].toString(),
          contactId: contactId,
          text: payload['text'].toString(),
          timestamp: ts,
          isSentByMe: false,
          isQueued: false,
          deleted: false,
        );
        await _db.insertMessage(message);
        _emit(IncomingMessageEvent(message));
      } else if (type == 'audio') {
        final audioPath = await _saveIncomingAudio(
          payload['messageId'].toString(),
          payload['audioBase64'].toString(),
        );
        final message = ChatMessage(
          messageId: payload['messageId'].toString(),
          contactId: contactId,
          text: '',
          timestamp: ts,
          isSentByMe: false,
          isQueued: false,
          deleted: false,
          audioPath: audioPath,
        );
        await _db.insertMessage(message);
        _emit(IncomingMessageEvent(message));
      } else if (type == 'delete') {
        final messageId = payload['messageId'].toString();
        await _db.deleteForMeAndHide(messageId);
        _emit(MessageDeletedEvent(contactId: contactId, messageId: messageId));
      }
    }));
  }

  Future<void> _flushQueuedMessages(String contactId, WebRtcService peer) async {
    final queued = await _db.getQueuedMessages(contactId);
    for (final message in queued) {
      if (!peer.isReady) break;
      if (message.isAudio && message.audioPath != null) {
        final dataUri = message.audioPath!;
        final comma = dataUri.indexOf(',');
        if (comma != -1) {
          await peer.sendJson({
            'type': 'audio',
            'messageId': message.messageId,
            'audioBase64': dataUri.substring(comma + 1),
            'timestamp': message.timestamp,
          });
        }
      } else {
        await peer.sendJson({
          'type': 'text',
          'messageId': message.messageId,
          'text': message.text,
          'timestamp': message.timestamp,
        });
      }
      await _db.markMessageDelivered(message.messageId);
    }
    if (queued.isNotEmpty) {
      _emit(MessagesDeliveredEvent(contactId));
    }
  }
  Future<void> _sendOffer(String contactId) async {
    if (_sendingOffer.contains(contactId)) return;
    _sendingOffer.add(contactId);
    _offerSent.add(contactId);
    try {
      final peer = await _getOrCreatePeer(contactId);
      if (_peers[contactId] != peer) return;
      final offer = await peer.createOffer();
      _signaling.sendOffer(
        room: _rooms[contactId]!,
        from: _currentUserId!,
        offer: offer,
      );
    } finally {
      _sendingOffer.remove(contactId);
    }
  }

  void _bindSignaling() {
    _subs.add(_signaling.onRoomJoined.listen((room) async {
      final contactId = _contactIdForRoom(room);
      if (contactId == null) return;
      if (_isInitiator[contactId] == true && !_offerSent.contains(contactId)) {
        await _sendOffer(contactId);
      }
    }));

    _subs.add(_signaling.onUserJoined.listen((data) async {
      final joinedId = data['userId']?.toString();
      if (joinedId == null || !_rooms.containsKey(joinedId)) return;
      if (_isInitiator[joinedId] == true) {
        if (_sendingOffer.contains(joinedId)) return;
        _cancelPeerSubs(joinedId);
        final old = _peers.remove(joinedId);
        old?.dispose();
        _offerSent.remove(joinedId);
        await _sendOffer(joinedId);
      }
    }));

    _subs.add(_signaling.onOffer.listen((data) async {
      final from = data['from']?.toString();
      if (from == null || !_rooms.containsKey(from)) return;
      try {
        final peer = await _getOrCreatePeer(from);
        await peer.applyRemoteOffer(data);
        final answer = await peer.createAnswer();
        _signaling.sendAnswer(
          room: _rooms[from]!,
          from: _currentUserId!,
          answer: answer,
        );
      } catch (e) {
        debugPrint('[ConnectionManager] offer handling failed: $e');
      }
    }));

    _subs.add(_signaling.onAnswer.listen((data) async {
      final from = data['from']?.toString();
      if (from == null || !_peers.containsKey(from)) return;
      try {
        await _peers[from]!.applyRemoteAnswer(data);
      } catch (e) {
        debugPrint('[ConnectionManager] answer handling failed: $e');
      }
    }));

    _subs.add(_signaling.onCandidate.listen((data) async {
      final from = data['from']?.toString();
      if (from == null || !_peers.containsKey(from)) return;
      try {
        await _peers[from]!.addRemoteCandidate(data);
      } catch (e) {
        debugPrint('[ConnectionManager] remote candidate failed: $e');
      }
    }));

    _subs.add(_signaling.onContactInvite.listen((data) {
      final fromUsername = data['from']?.toString() ?? '';
      if (fromUsername.isEmpty) return;
      _emit(ContactInviteReceivedEvent(fromUsername));
    }));

    _subs.add(_signaling.onContactAccepted.listen((data) {
      final byUsername = data['by']?.toString() ?? '';
      if (byUsername.isEmpty) return;
      _emit(ContactAcceptedEvent(byUsername));
    }));

    _subs.add(_signaling.onTyping.listen((room) {
      final contactId = _contactIdForRoom(room);
      if (contactId == null) return;
      _emit(TypingEvent(contactId));
    }));

    _subs.add(_signaling.onStopTyping.listen((room) {
      final contactId = _contactIdForRoom(room);
      if (contactId == null) return;
      _emit(StopTypingEvent(contactId));
    }));

    _subs.add(_signaling.onUserOffline.listen((data) {
      final from = data['from']?.toString();
      if (from == null || !_rooms.containsKey(from)) return;
      _emit(ContactOfflineEvent(from));
    }));

    _subs.add(_signaling.onDisconnect.listen((_) async {
      if (_currentUserId == null || _token == null) return;
      await Future.delayed(const Duration(seconds: 3));
      if (_currentUserId == null || _token == null) return;
      reconnect(_token!);
    }));

    _subs.add(_signaling.onDelete.listen((data) async {
      final from = data['from']?.toString();
      if (from == null || !_rooms.containsKey(from)) return;
      final messageId = data['messageId']?.toString();
      if (messageId == null) return;
      await _db.deleteForMeAndHide(messageId);
      _emit(MessageDeletedEvent(contactId: from, messageId: messageId));
    }));
  }

  void _emit(ConnectionEvent event) {
    if (!_eventsController.isClosed) _eventsController.add(event);
  }
}
