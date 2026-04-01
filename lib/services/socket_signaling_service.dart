import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:ciaccola_frontend/configs/api_config.dart';

class SocketSignalingService {
  io.Socket? _socket;

  final _connectController = StreamController<void>.broadcast();
  final _disconnectController = StreamController<void>.broadcast();
  final _offerController = StreamController<Map<String, dynamic>>.broadcast();
  final _answerController = StreamController<Map<String, dynamic>>.broadcast();
  final _candidateController = StreamController<Map<String, dynamic>>.broadcast();
  final _peerOnlineController = StreamController<Map<String, dynamic>>.broadcast();
  final _deleteController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<void> get onConnect => _connectController.stream;
  Stream<void> get onDisconnect => _disconnectController.stream;
  Stream<Map<String, dynamic>> get onOffer => _offerController.stream;
  Stream<Map<String, dynamic>> get onAnswer => _answerController.stream;
  Stream<Map<String, dynamic>> get onCandidate => _candidateController.stream;
  Stream<Map<String, dynamic>> get onPeerOnline => _peerOnlineController.stream;
  Stream<Map<String, dynamic>> get onDelete => _deleteController.stream;

  bool get connected => _socket?.connected == true;

  void connect({required String token, required String userId}) {
    _socket?.dispose();
    _socket = io.io(
      ApiConfig.baseSocketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );

    _socket!.onConnect((_) {
      _socket!.emit('join-user', {'userId': userId});
      _connectController.add(null);
    });
    _socket!.onDisconnect((_) => _disconnectController.add(null));
    _socket!.on('webrtc-offer', (data) => _offerController.add(Map<String, dynamic>.from(data)));
    _socket!.on('webrtc-answer', (data) => _answerController.add(Map<String, dynamic>.from(data)));
    _socket!.on('ice-candidate', (data) => _candidateController.add(Map<String, dynamic>.from(data)));
    _socket!.on('peer-online', (data) => _peerOnlineController.add(Map<String, dynamic>.from(data)));
    _socket!.on('delete-message', (data) => _deleteController.add(Map<String, dynamic>.from(data)));
    _socket!.connect();
  }

  void openChat(String peerId) {
    _socket?.emit('open-chat', {'peerId': peerId});
  }

  void sendOffer({required String to, required String from, required Map<String, dynamic> offer}) {
    _socket?.emit('webrtc-offer', {'to': to, 'from': from, ...offer});
  }

  void sendAnswer({required String to, required String from, required Map<String, dynamic> answer}) {
    _socket?.emit('webrtc-answer', {'to': to, 'from': from, ...answer});
  }

  void sendIceCandidate({required String to, required String from, required Map<String, dynamic> candidate}) {
    _socket?.emit('ice-candidate', {'to': to, 'from': from, 'candidate': candidate});
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
    _peerOnlineController.close();
    _deleteController.close();
  }
}
