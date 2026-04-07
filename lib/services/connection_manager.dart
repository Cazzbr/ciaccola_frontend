import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ciaccola_frontend/models/chat_message.dart';
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/services/database_service.dart';
import 'package:ciaccola_frontend/services/socket_signaling_service.dart';
import 'package:ciaccola_frontend/services/webrtc_service.dart';

// ---------------------------------------------------------------------------
// Event types
// ---------------------------------------------------------------------------

abstract class ConnectionEvent {
  final String contactId;
  const ConnectionEvent(this.contactId);
}

/// A new text message arrived from [contactId] and was saved to the DB.
class IncomingMessageEvent extends ConnectionEvent {
  final ChatMessage message;
  IncomingMessageEvent(this.message) : super(message.contactId);
}

/// A delete event arrived for [messageId] from [contactId].
class MessageDeletedEvent extends ConnectionEvent {
  final String messageId;
  const MessageDeletedEvent({required String contactId, required this.messageId})
      : super(contactId);
}

/// Queued messages for [contactId] were just flushed through the data channel.
class MessagesDeliveredEvent extends ConnectionEvent {
  const MessagesDeliveredEvent(String contactId) : super(contactId);
}

/// The contact explicitly went offline (socket user-offline signal received).
class ContactOfflineEvent extends ConnectionEvent {
  const ContactOfflineEvent(String contactId) : super(contactId);
}

/// Someone sent us a contact invite (socket: contact-invite { from: username }).
/// Consumers should reload their contacts list to pick up the new 'invited' entry.
class ContactInviteReceivedEvent extends ConnectionEvent {
  final String fromUsername;
  ContactInviteReceivedEvent(this.fromUsername) : super(fromUsername);
}

/// Someone accepted our contact invite (socket: contact-accepted { by: username }).
/// Consumers should reload their contacts list to reflect the new 'accepted' status.
class ContactAcceptedEvent extends ConnectionEvent {
  final String byUsername;
  ContactAcceptedEvent(this.byUsername) : super(byUsername);
}

/// The WebRTC peer connection state changed for [contactId].
class PeerStateChangedEvent extends ConnectionEvent {
  final RTCPeerConnectionState state;
  const PeerStateChangedEvent({required String contactId, required this.state})
      : super(contactId);
}

/// The data channel state changed for [contactId].
class ChannelStateChangedEvent extends ConnectionEvent {
  final RTCDataChannelState state;
  const ChannelStateChangedEvent({required String contactId, required this.state})
      : super(contactId);
}

// ---------------------------------------------------------------------------
// ConnectionManager
// ---------------------------------------------------------------------------

/// Singleton that manages WebRTC peer connections for all contacts.
///
/// Lifetime: started once after login (via [start]), stopped on logout/exit
/// (via [stop]). Between those calls it owns all peer connections and handles
/// all WebRTC signaling so that the user is reachable even when no ChatScreen
/// is open.
class ConnectionManager {
  static final _instance = ConnectionManager._internal();
  factory ConnectionManager() => _instance;
  ConnectionManager._internal();

  final _signaling = SocketSignalingService();
  final _db = DatabaseService();

  String? _currentUserId;

  /// contactId → WebRtcService
  final Map<String, WebRtcService> _peers = {};

  /// contactId → socket room id
  final Map<String, String> _rooms = {};

  /// contactId → whether this side sends the first offer
  final Map<String, bool> _isInitiator = {};

  /// contactIds for which we have already sent an offer this session
  final Set<String> _offerSent = {};

  /// contactIds for which a _sendOffer call is currently in-flight
  final Set<String> _sendingOffer = {};

  /// Signaling-level stream subscriptions (created once in _bindSignaling).
  final List<StreamSubscription> _subs = [];

  /// Per-peer subscriptions, keyed by contactId.
  /// Cancelled and replaced whenever a peer is disposed/replaced.
  final Map<String, List<StreamSubscription>> _peerSubs = {};

  /// Broadcast stream of typed events. Never closed — survives stop/start cycles.
  final _eventsController = StreamController<ConnectionEvent>.broadcast();

  Stream<ConnectionEvent> get events => _eventsController.stream;

  bool get isRunning => _currentUserId != null;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Connect to signaling, join all contact rooms, and start managing peers.
  ///
  /// Safe to call multiple times: subsequent calls only register new contacts.
  Future<void> start({
    required String currentUserId,
    required String token,
    required List<Contact> contacts,
  }) async {
    if (_currentUserId != null) {
      // Already running — just add any new contacts.
      for (final c in contacts) {
        if (!_rooms.containsKey(c.id)) _addContact(c);
      }
      return;
    }

    _currentUserId = currentUserId;

    if (!_signaling.connected) {
      _signaling.connect(token: token);
    }

    _bindSignaling();

    // Personal room receives contact invites directed at this user.
    // ⚠️  Backend must forward 'contact-invite' events to room 'user_{userId}'.
    _signaling.joinRoom('user_$currentUserId');

    for (final contact in contacts) {
      _addContact(contact);
    }
  }

  /// Register a contact that was added after [start] was called.
  void addContact(Contact contact) {
    if (_currentUserId == null) return;
    if (!_rooms.containsKey(contact.id)) _addContact(contact);
  }

  /// Stop all connections and reset state. Call on logout or app exit.
  void stop() {
    // Notify every room before the socket closes so the other side knows
    // immediately, without waiting for WebRTC ICE timeout.
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

    _signaling.disconnect();
  }

  // -------------------------------------------------------------------------
  // Public API used by ChatScreen
  // -------------------------------------------------------------------------

  /// Returns the active [WebRtcService] for [contactId], or null if not yet
  /// created (connection not established yet).
  WebRtcService? getPeer(String contactId) => _peers[contactId];

  bool isChannelReady(String contactId) =>
      _peers[contactId]?.isReady ?? false;

  /// If the data channel for [contactId] is already open, flush any queued
  /// messages immediately. Safe to call any time — no-op if channel not ready.
  Future<void> flushIfReady(String contactId) async {
    final peer = _peers[contactId];
    if (peer != null && peer.isReady) {
      await _flushQueuedMessages(contactId, peer);
    }
  }

  /// Send a JSON payload through the data channel for [contactId].
  ///
  /// Throws if the channel is not open.
  Future<void> sendJson(String contactId, Map<String, dynamic> payload) async {
    final peer = _peers[contactId];
    if (peer == null || !peer.isReady) throw Exception('Data channel not open');
    await peer.sendJson(payload);
  }

  // -------------------------------------------------------------------------
  // Internal — contact setup
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Internal — peer management
  // -------------------------------------------------------------------------

  Future<WebRtcService> _getOrCreatePeer(String contactId) async {
    if (_peers.containsKey(contactId)) return _peers[contactId]!;
    final peer = WebRtcService();
    // Only the initiator creates the data channel; the answerer receives it
    // via onDataChannel. Both sides creating a channel produces extra SDP
    // m-lines and causes setRemoteDescription to fail.
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
    // Cancel any subscriptions from a previous peer for this contact so stale
    // callbacks (e.g. RTCDataChannelClosed from a disposed peer) never fire.
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
      if (type == 'text') {
        final message = ChatMessage(
          messageId: payload['messageId'].toString(),
          contactId: contactId,
          text: payload['text'].toString(),
          timestamp: payload['timestamp'] is int
              ? payload['timestamp'] as int
              : DateTime.now().millisecondsSinceEpoch,
          isSentByMe: false,
          isQueued: false,
          deleted: false,
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
      await peer.sendJson({
        'type': 'text',
        'messageId': message.messageId,
        'text': message.text,
        'timestamp': message.timestamp,
      });
      await _db.markMessageDelivered(message.messageId);
    }
    if (queued.isNotEmpty) {
      _emit(MessagesDeliveredEvent(contactId));
    }
  }

  // -------------------------------------------------------------------------
  // Internal — signaling
  // -------------------------------------------------------------------------

  Future<void> _sendOffer(String contactId) async {
    // Guard against concurrent calls for the same contact (e.g. onRoomJoined
    // and onUserJoined firing at the same time).
    if (_sendingOffer.contains(contactId)) return;
    _sendingOffer.add(contactId);
    _offerSent.add(contactId);
    try {
      final peer = await _getOrCreatePeer(contactId);
      // Bail out if the peer was replaced while we were awaiting init.
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
    // We just joined a room — send offer if we're the initiator.
    _subs.add(_signaling.onRoomJoined.listen((room) async {
      final contactId = _contactIdForRoom(room);
      if (contactId == null) return;
      if (_isInitiator[contactId] == true && !_offerSent.contains(contactId)) {
        await _sendOffer(contactId);
      }
    }));

    // Peer (re)joined — tear down any stale peer and send a fresh offer.
    _subs.add(_signaling.onUserJoined.listen((data) async {
      final joinedId = data['userId']?.toString();
      if (joinedId == null || !_rooms.containsKey(joinedId)) return;
      if (_isInitiator[joinedId] == true) {
        // If an offer is already being built (e.g. onRoomJoined fired first),
        // let it finish — no need to race against it.
        if (_sendingOffer.contains(joinedId)) return;
        // Cancel stale callbacks and dispose the old peer before re-offering.
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

    // Incoming contact invite from another user.
    _subs.add(_signaling.onContactInvite.listen((data) {
      final fromUsername = data['from']?.toString() ?? '';
      if (fromUsername.isEmpty) return;
      _emit(ContactInviteReceivedEvent(fromUsername));
    }));

    // Another user accepted our contact invite.
    _subs.add(_signaling.onContactAccepted.listen((data) {
      final byUsername = data['by']?.toString() ?? '';
      if (byUsername.isEmpty) return;
      _emit(ContactAcceptedEvent(byUsername));
    }));

    // Peer explicitly going offline — instant notification before socket closes.
    _subs.add(_signaling.onUserOffline.listen((data) {
      final from = data['from']?.toString();
      if (from == null || !_rooms.containsKey(from)) return;
      _emit(ContactOfflineEvent(from));
    }));

    // Socket fallback for delete events (when data channel is not open).
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
