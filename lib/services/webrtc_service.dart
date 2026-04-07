import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRtcService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  bool _closed = false;
  final List<Map<String, dynamic>> _pendingCandidates = [];

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<RTCPeerConnectionState>.broadcast();
  final _candidateController = StreamController<RTCIceCandidate>.broadcast();
  final _channelStateController = StreamController<RTCDataChannelState>.broadcast();

  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;
  Stream<RTCPeerConnectionState> get onState => _stateController.stream;
  Stream<RTCIceCandidate> get onCandidate => _candidateController.stream;
  Stream<RTCDataChannelState> get onChannelState => _channelStateController.stream;

  bool get isReady => _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;

  /// True between createOffer() and applyRemoteAnswer() — used to guard
  /// against applying stale/duplicate answers in the wrong signaling state.
  bool _hasLocalOffer = false;

  Future<void> init({bool createDataChannel = true}) async {
    _closed = false;
    _pendingCandidates.clear();
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    _peerConnection!.onIceCandidate = (candidate) {
      debugPrint('[WebRTC] local ICE candidate: ${candidate.toMap()}');
      try {
        _candidateController.add(candidate);
      } catch (_) {debugPrint('[_channelStateController] error');}

    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('[WebRTC] connection state: $state');
      try {
        _stateController.add(state);
      } catch (_) {debugPrint('[_channelStateController] error');}
    };

    _peerConnection!.onDataChannel = (channel) {
      debugPrint('[WebRTC] remote data channel received: ${channel.label}');
      _attachDataChannel(channel);
    };

    if (createDataChannel) {
      final channel = await _peerConnection!.createDataChannel(
        'messages',
        RTCDataChannelInit()..ordered = true,
      );
      debugPrint('[WebRTC] local data channel created: ${channel.label}');
      _attachDataChannel(channel);
    }
  }

  void _attachDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    final initialState = channel.state;
    if (initialState != null) {
      debugPrint('[WebRTC] data channel initial state: $initialState');
      try {
        _channelStateController.add(initialState);
      } catch (_) {debugPrint('[_channelStateController] error');}
    }

    channel.onDataChannelState = (state) {
      debugPrint('[WebRTC] data channel state changed: $state');
      try {
        _channelStateController.add(state);
      } catch (_) {debugPrint('[_channelStateController] error');}
    };
    channel.onMessage = (message) {
      final raw = message.text;
      debugPrint('[WebRTC] data channel message received: $raw');
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _messageController.add(decoded);
      } catch (_) {
        _messageController.add({'type': 'text', 'text': raw});
      }
    };
  }

  Future<Map<String, dynamic>> createOffer() async {
    _hasLocalOffer = true;
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });
    await _peerConnection!.setLocalDescription(offer);
    return {'sdp': offer.sdp, 'type': offer.type};
  }

  Future<void> applyRemoteOffer(Map<String, dynamic> data) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp']?.toString(), data['type']?.toString()),
    );
    for (final candidate in _pendingCandidates) {
      try {
        await addRemoteCandidate(candidate);
      } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  Future<Map<String, dynamic>> createAnswer() async {
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    return {'sdp': answer.sdp, 'type': answer.type};
  }

  Future<void> applyRemoteAnswer(Map<String, dynamic> data) async {
    if (!_hasLocalOffer) {
      debugPrint('[WebRTC] ignoring answer — no pending local offer');
      return;
    }
    _hasLocalOffer = false;
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp']?.toString(), data['type']?.toString()),
    );
    for (final candidate in _pendingCandidates) {
      try {
        await addRemoteCandidate(candidate);
      } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  Future<void> addRemoteCandidate(Map<String, dynamic> data) async {
    if (await _peerConnection!.getRemoteDescription() == null) {
      _pendingCandidates.add(data);
    } else {
      final candidate = data['candidate'] as Map<String, dynamic>;
      await _peerConnection!.addCandidate(
        RTCIceCandidate(
          candidate['candidate']?.toString(),
          candidate['sdpMid']?.toString(),
          candidate['sdpMLineIndex'] as int?,
        ),
      );
    }
  }

  Future<void> sendJson(Map<String, dynamic> payload) async {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      await _dataChannel!.send(RTCDataChannelMessage(jsonEncode(payload)));
    } else {
      throw Exception('Data channel not open');
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _dataChannel = null;
    _pendingCandidates.clear();
    final pc = _peerConnection;
    _peerConnection = null;
    if (pc != null) {
      try { await pc.close(); } catch (_) {}
    }
  }

  void dispose() {
    // Close synchronously best-effort, then release all stream controllers.
    if (!_closed) {
      _closed = true;
      _dataChannel = null;
      _pendingCandidates.clear();
      final pc = _peerConnection;
      _peerConnection = null;
      if (pc != null) {
        pc.close().catchError((_) {});
      }
    }
    _messageController.close();
    _stateController.close();
    _candidateController.close();
    _channelStateController.close();
  }
}
