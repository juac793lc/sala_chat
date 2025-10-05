import 'package:socket_io_client/socket_io_client.dart' as io;
import 'auth_service.dart';

class SocketService {
  static SocketService? _instance;
  static SocketService get instance => _instance ??= SocketService._();
  
  SocketService._();

  io.Socket? _socket;
  bool _isConnected = false;
  final Set<String> _joinedRooms = {}; // evitar joins duplicados
  final Set<String> _pendingJoin = {}; // joins solicitados esperando confirmación
  
  // Callbacks para eventos
  final Map<String, List<Function>> _eventCallbacks = {};

  // Getters
  bool get isConnected => _isConnected;
  io.Socket? get socket => _socket;

  // Conectar al servidor
  Future<bool> connect() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        print('❌ No hay token para conectar');
        return false;
      }

      print('🔑 Conectando con token: ${token.substring(0, 20)}...');

      // Configurar socket
      _socket = io.io(
        'http://localhost:3000',
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .setAuth({'token': token})
            .build(),
      );

      // Eventos de conexión
      _socket!.onConnect((_) {
        _isConnected = true;
        print('✅ Conectado al servidor de chat');
        _notifyCallbacks('connected', null);
      });

      // Debug global: log de cualquier evento recibido (excepto ping/pong internos)
      _socket!.onAny((event, data) {
        if (event == 'ping' || event == 'pong') return;
        print('🌐 [onAny] event=$event dataKeys=${data is Map ? data.keys.toList() : data.runtimeType}');
      });

      _socket!.onDisconnect((_) {
        _isConnected = false;
        print('❌ Desconectado del servidor');
        _notifyCallbacks('disconnected', null);
      });

      _socket!.onConnectError((error) {
        _isConnected = false;
        print('❌ Error de conexión: $error');
        _notifyCallbacks('connect_error', error);
      });

      _socket!.on('auth_error', (data) {
        print('❌ Error de autenticación: $data');
        _notifyCallbacks('auth_error', data);
        disconnect();
      });

      // Eventos del chat
      _setupChatEvents();

      // Conectar
      _socket!.connect();
      
      return true;
    } catch (e) {
      print('❌ Error conectando socket: $e');
      return false;
    }
  }

  // Configurar eventos del chat
  void _setupChatEvents() {
    if (_socket == null) return;

    // Nuevo mensaje
    _socket!.on('new_message', (data) {
      print('📬 Nuevo mensaje recibido: ${data['content']}');
      _notifyCallbacks('new_message', data);
    });

    // Usuario online/offline
    _socket!.on('user_online', (data) {
      final username = data['username'] ?? data['userId'] ?? 'Usuario';
      print('🟢 Usuario online: $username');
      _notifyCallbacks('user_online', data);
    });

    _socket!.on('user_offline', (data) {
      final username = data['username'] ?? data['userId'] ?? 'Usuario';
      print('🔴 Usuario offline: $username');
      _notifyCallbacks('user_offline', data);
    });

    // Eventos de sala
    _socket!.on('user_joined_room', (data) {
      print('🏠 Usuario se unió a sala: ${data['username']}');
      _notifyCallbacks('user_joined_room', data);
    });

    _socket!.on('user_left_room', (data) {
      print('🚪 Usuario salió de sala: ${data['username']}');
      _notifyCallbacks('user_left_room', data);
    });

    // Confirmación de unirse a sala
    _socket!.on('joined_room', (data) {
      print('✅ Te uniste a sala: ${data['roomName']}');
      _notifyCallbacks('joined_room', data);
      final room = data['roomName'] ?? data['roomId'];
      if (room is String) {
        _pendingJoin.remove(room);
        _joinedRooms.add(room);
      }
    });

    // Indicadores de escritura
    _socket!.on('user_typing', (data) {
      _notifyCallbacks('user_typing', data);
    });

    _socket!.on('user_stop_typing', (data) {
      _notifyCallbacks('user_stop_typing', data);
    });

    // Mensaje leído
    _socket!.on('message_read', (data) {
      _notifyCallbacks('message_read', data);
    });

    // Reacciones
    _socket!.on('message_reaction', (data) {
      _notifyCallbacks('message_reaction', data);
    });

    // Errores
    _socket!.on('error', (data) {
      print('❌ Error del servidor: $data');
      _notifyCallbacks('error', data);
    });
  }

  // Desconectar
  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
    _isConnected = false;
    _eventCallbacks.clear();
  }

  // === MÉTODOS DE EVENTOS ===

  // Agregar callback para evento
  void on(String event, Function callback) {
    if (!_eventCallbacks.containsKey(event)) {
      _eventCallbacks[event] = [];
    }
    _eventCallbacks[event]!.add(callback);
  }

  // Remover callback
  void off(String event, Function callback) {
    if (_eventCallbacks.containsKey(event)) {
      _eventCallbacks[event]!.remove(callback);
    }
  }

  // Notificar callbacks
  void _notifyCallbacks(String event, dynamic data) {
    if (_eventCallbacks.containsKey(event)) {
      for (final callback in _eventCallbacks[event]!) {
        try {
          callback(data);
        } catch (e) {
          print('❌ Error en callback $event: $e');
        }
      }
    }
  }

  // === MÉTODOS DE CHAT ===

  // Enviar mensaje
  void sendMessage({
    required String roomId,
    required String content,
    String type = 'text',
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? replyTo,
  }) {
    if (!_isConnected || _socket == null) {
      print('❌ No conectado al servidor');
      return;
    }

    _socket!.emit('send_message', {
      'roomId': roomId,
      'content': content,
      'type': type,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'replyTo': replyTo,
    });
  }

  // Unirse a sala
  void joinRoom(String roomId) {
    if (!_isConnected || _socket == null) {
      print('❌ No conectado al servidor');
      return;
    }
    if (_joinedRooms.contains(roomId)) {
      print('⏭️ Already in room $roomId, skip join');
      return;
    }
    if (_pendingJoin.contains(roomId)) {
      print('⏳ Join ya pendiente para $roomId');
      return;
    }
    _pendingJoin.add(roomId);
    _socket!.emit('join_room', {'roomId': roomId});
  }

  // Salir de sala
  void leaveRoom(String roomId) {
    if (!_isConnected || _socket == null) return;
    if (_joinedRooms.contains(roomId) || _pendingJoin.contains(roomId)) {
      _socket!.emit('leave_room', {'roomId': roomId});
      _joinedRooms.remove(roomId);
      _pendingJoin.remove(roomId);
    }
  }

  bool isInRoom(String roomId) => _joinedRooms.contains(roomId);
  bool isJoining(String roomId) => _pendingJoin.contains(roomId);

  // Indicador de escritura
  void startTyping(String roomId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('typing_start', {'roomId': roomId});
  }

  void stopTyping(String roomId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('typing_stop', {'roomId': roomId});
  }

  // Marcar mensaje como leído
  void markMessageAsRead(String messageId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('mark_message_read', {'messageId': messageId});
  }

  // Agregar reacción
  void addReaction(String messageId, String emoji) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('add_reaction', {
      'messageId': messageId,
      'emoji': emoji,
    });
  }
}

// Modelo de mensaje
class MessageModel {
  final String id;
  final String content;
  final String type;
  final UserModel sender;
  final String roomId;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? replyTo;
  final List<MessageReaction> reactions;
  final List<MessageRead> readBy;
  final DateTime? editedAt;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  MessageModel({
    required this.id,
    required this.content,
    required this.type,
    required this.sender,
    required this.roomId,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.replyTo,
    required this.reactions,
    required this.readBy,
    this.editedAt,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      content: json['content'] ?? '',
      type: json['type'] ?? 'text',
      sender: UserModel.fromJson(json['sender'] ?? {}),
      roomId: json['roomId'] ?? json['room'] ?? 'sala-general',
      fileUrl: json['fileUrl'],
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      mimeType: json['mimeType'],
      replyTo: json['replyTo'],
      reactions: (json['reactions'] as List? ?? [])
          .map((r) => MessageReaction.fromJson(r))
          .toList(),
      readBy: (json['readBy'] as List? ?? [])
          .map((r) => MessageRead.fromJson(r))
          .toList(),
      editedAt: json['editedAt'] != null ? DateTime.parse(json['editedAt']) : null,
      isDeleted: json['isDeleted'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

// Modelo de reacción
class MessageReaction {
  final String userId;
  final String emoji;
  final DateTime createdAt;

  MessageReaction({
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      userId: json['user'],
      emoji: json['emoji'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

// Modelo de lectura
class MessageRead {
  final String userId;
  final DateTime readAt;

  MessageRead({
    required this.userId,
    required this.readAt,
  });

  factory MessageRead.fromJson(Map<String, dynamic> json) {
    return MessageRead(
      userId: json['user'],
      readAt: DateTime.parse(json['readAt']),
    );
  }
}