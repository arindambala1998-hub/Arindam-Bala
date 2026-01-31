import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// ✅ Troonky Chat Socket Service
///
/// - Singleton connection
/// - Connect only when authenticated
/// - Join/leave per-conversation rooms
/// - Broadcast streams for UI/controllers
///
/// IMPORTANT: Your backend must support these (or rename here):
/// - "join"  : { room: "conversation:<id>" }
/// - "leave" : { room: "conversation:<id>" }
/// - "message:new"       : { conversation_id, message }
/// - "typing"            : { conversation_id, user_id, is_typing }
/// - "presence"          : { user_id, is_online }
/// - "message:delivered" : { conversation_id, message_id }
/// - "message:seen"      : { conversation_id, message_id }
class ChatSocketService {
  ChatSocketService._();
  static final ChatSocketService I = ChatSocketService._();

  /// Your socket base (same domain as API)
  static const String socketUrl = 'https://adminapi.troonky.in';
  static const String socketPath = '/socket.io';

  io.Socket? _socket;
  String _token = '';
  int _myUserId = 0;

  bool get isConnected => _socket?.connected == true;

  final _onNewMessageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNewMessage => _onNewMessageCtrl.stream;

  final _onTypingCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onTyping => _onTypingCtrl.stream;

  final _onPresenceCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onPresence => _onPresenceCtrl.stream;

  final _onDeliveredCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onDelivered => _onDeliveredCtrl.stream;

  final _onSeenCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onSeen => _onSeenCtrl.stream;

  void _debug(String s) {
    if (kDebugMode) debugPrint('[ChatSocket] $s');
  }

  /// Connect the socket if not already.
  /// Call this when user is logged in AND app is foreground.
  Future<void> connect({
    required String token,
    required int myUserId,
  }) async {
    final t = token.trim();
    if (t.isEmpty || myUserId <= 0) return;

    _token = t;
    _myUserId = myUserId;

    if (_socket != null) {
      if (_socket!.connected) return;
      try {
        _socket!.connect();
        return;
      } catch (_) {
        // fall-through to rebuild
      }
    }

    final s = io.io(
      socketUrl,
      <String, dynamic>{
        'transports': ['websocket'],
        'path': socketPath,
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': 999,
        'reconnectionDelay': 800,
        'reconnectionDelayMax': 3000,
        // Bearer token (backend can read headers)
        'extraHeaders': <String, String>{
          'Authorization': 'Bearer $_token',
        },
        // Also include auth payload (backend can read socket.handshake.auth)
        'auth': <String, dynamic>{
          'token': _token,
          'user_id': _myUserId,
        },
      },
    );

    _socket = s;

    s.onConnect((_) {
      _debug('connected');
      s.emit('presence:ping', <String, dynamic>{'user_id': _myUserId});
    });

    s.onDisconnect((_) {
      _debug('disconnected');
    });

    s.onConnectError((e) {
      _debug('connect_error: $e');
    });

    s.onError((e) {
      _debug('error: $e');
    });

    s.on('message:new', (data) {
      if (data is Map) {
        _onNewMessageCtrl.add(Map<String, dynamic>.from(data));
      }
    });

    s.on('typing', (data) {
      if (data is Map) {
        _onTypingCtrl.add(Map<String, dynamic>.from(data));
      }
    });

    s.on('presence', (data) {
      if (data is Map) {
        _onPresenceCtrl.add(Map<String, dynamic>.from(data));
      }
    });

    s.on('message:delivered', (data) {
      if (data is Map) {
        _onDeliveredCtrl.add(Map<String, dynamic>.from(data));
      }
    });

    s.on('message:seen', (data) {
      if (data is Map) {
        _onSeenCtrl.add(Map<String, dynamic>.from(data));
      }
    });

    s.connect();
  }

  /// Call this when app goes background or user logs out.
  void disconnect() {
    try {
      _socket?.disconnect();
    } catch (_) {}
  }

  void dispose() {
    try {
      _socket?.dispose();
    } catch (_) {}
  }

  void joinConversation(int conversationId) {
    final s = _socket;
    if (s == null || !s.connected) return;
    if (conversationId <= 0) return;
    s.emit('join', <String, dynamic>{
      'room': 'conversation:$conversationId',
      'conversation_id': conversationId,
    });
  }

  void leaveConversation(int conversationId) {
    final s = _socket;
    if (s == null || !s.connected) return;
    if (conversationId <= 0) return;
    s.emit('leave', <String, dynamic>{
      'room': 'conversation:$conversationId',
      'conversation_id': conversationId,
    });
  }

  /// Send typing state (optional)
  void setTyping({
    required int conversationId,
    required bool isTyping,
  }) {
    final s = _socket;
    if (s == null || !s.connected) return;
    if (conversationId <= 0) return;
    s.emit('typing', <String, dynamic>{
      'conversation_id': conversationId,
      'user_id': _myUserId,
      'is_typing': isTyping,
    });
  }
}
