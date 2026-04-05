import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:ciaccola_frontend/configs/api_config.dart';

class SocketSignalingService {
  static final SocketSignalingService _instance = SocketSignalingService._internal();

  factory SocketSignalingService() => _instance;

  SocketSignalingService._internal();

  io.Socket? _socket;
  final List<String> _pendingRooms = [];

  final _connectController = StreamController<void>.broadcast();
  final _disconnectController = StreamController<void>.broadcast();
  final _offerController = StreamController<Map<String, dynamic>>.broadcast();
  final _answerController = StreamController<Map<String, dynamic>>.broadcast();
  final _candidateController = StreamController<Map<String, dynamic>>.broadcast();
  final _userJoinedController = StreamController<Map<String, dynamic>>.broadcast();
  final _audioOfferController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<String>.broadcast();
  final _stopTypingController = StreamController<void>.broadcast();
  final _deleteController = StreamController<Map<String, dynamic>>.broadcast();
  final _roomJoinedController = StreamController<String>.broadcast();

  Stream<void> get onConnect => _connectController.stream;
  Stream<void> get onDisconnect => _disconnectController.stream;
  Stream<Map<String, dynamic>> get onOffer => _offerController.stream;
  Stream<Map<String, dynamic>> get onAnswer => _answerController.stream;
  Stream<Map<String, dynamic>> get onCandidate => _candidateController.stream;
  Stream<Map<String, dynamic>> get onUserJoined => _userJoinedController.stream;
  Stream<Map<String, dynamic>> get onAudioOffer => _audioOfferController.stream;
  Stream<String> get onTyping => _typingController.stream;
  Stream<void> get onStopTyping => _stopTypingController.stream;
  Stream<Map<String, dynamic>> get onDelete => _deleteController.stream;
  Stream<String> get onRoomJoined => _roomJoinedController.stream;

  bool get connected => _socket?.connected == true;

  void connect({required String token}) {
    if (_socket?.connected == true) return;
    _socket?.dispose();
    _socket = io.io(
      ApiConfig.baseSocketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[Socket] connected');
      _connectController.add(null);
      for (final room in _pendingRooms) {
        debugPrint('[Socket] joining pending room $room');
        _socket!.emit('join-room', {'room': room});
        _roomJoinedController.add(room);
      }
      _pendingRooms.clear();
    });
    _socket!.onDisconnect((_) {
      debugPrint('[Socket] disconnected');
      _disconnectController.add(null);
    });
    _socket!.on('offer', (data) {
      debugPrint('[Socket] offer received: $data');
      _offerController.add(Map<String, dynamic>.from(data));
    });
    _socket!.on('answer', (data) => _answerController.add(Map<String, dynamic>.from(data)));
    _socket!.on('ice-candidate', (data) => _candidateController.add(Map<String, dynamic>.from(data)));
    _socket!.on('user-joined', (data) => _userJoinedController.add(Map<String, dynamic>.from(data)));
    _socket!.on('audio-offer', (data) => _audioOfferController.add(Map<String, dynamic>.from(data)));
    _socket!.on('typing', (data) => _typingController.add(data?.toString() ?? ''));
    _socket!.on('stop-typing', (_) => _stopTypingController.add(null));
    _socket!.on('delete-message', (data) => _deleteController.add(Map<String, dynamic>.from(data)));
    _socket!.connect();
  }

  void joinRoom(String room) {
    if (_socket?.connected == true) {
      debugPrint('[Socket] joining room $room');
      _socket!.emit('join-room', {'room': room});
      _roomJoinedController.add(room);
    } else {
      _pendingRooms.add(room);
    }
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  void sendOffer({required String room, required String from, required Map<String, dynamic> offer}) {
    _socket?.emit('offer', {'room': room, 'from': from, ...offer});
  }

  void sendAnswer({required String room, required String from, required Map<String, dynamic> answer}) {
    _socket?.emit('answer', {'room': room, 'from': from, ...answer});
  }

  void sendIceCandidate({required String room, required String from, required Map<String, dynamic> candidate}) {
    _socket?.emit('ice-candidate', {'room': room, 'from': from, 'candidate': candidate});
  }

  void sendAudioOffer({required String room, required Map<String, dynamic> offer}) {
    _socket?.emit('audio-offer', {'room': room, ...offer});
  }

  void sendTyping({required String room}) {
    _socket?.emit('typing', {'room': room});
  }

  void sendStopTyping({required String room}) {
    _socket?.emit('stop-typing', {'room': room});
  }

  void sendDelete({required String to, required String from, required String messageId}) {
    _socket?.emit('delete-message', {'to': to, 'from': from, 'messageId': messageId});
  }

  void dispose() {
    _socket?.dispose();
    _connectController.close();
    _disconnectController.close();
    _offerController.close();
    _answerController.close();
    _candidateController.close();
    _userJoinedController.close();
    _audioOfferController.close();
    _typingController.close();
    _stopTypingController.close();
    _deleteController.close();
    _roomJoinedController.close();
  }
}
