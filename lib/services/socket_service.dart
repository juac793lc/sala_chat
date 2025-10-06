import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/material.dart';
import 'auth_service.dart';

class SocketService {
  static SocketService? _instance;
  static SocketService get instance => _instance ??= SocketService._();
  
  SocketService._();

  io.Socket? _socket;
  bool _isConnected = false;
  final Set<String> _joinedRooms = {}; // evitar joins duplicados
  final Set<String> _pendingJoin = {}; // joins solicitados esperando confirmación
  bool _eventsRegistrados = false; // asegura que _setupChatEvents solo corre una vez
  Set<String> _joinedRoomsSnapshotBeforeDisconnect = {}; // snapshot para rejoin
  
  // Callbacks para eventos
  final Map<String, List<Function>> _eventCallbacks = {};
  
  // Contadores de usuarios en tiempo real
  int _usuariosConectados = 0;
  int _usuariosSuscritos = 0;
  final Map<String, int> _suscritosPorSala = {};

  // Getters
  bool get isConnected => _isConnected;
  io.Socket? get socket => _socket;
  int get usuariosConectados => _usuariosConectados;
  int get usuariosSuscritos => _usuariosSuscritos;
  int suscritosPorSala(String roomId) => _suscritosPorSala[roomId] ?? 0;

  // Conectar al servidor (idempotente)
  Future<bool> connect() async {
    if (_isConnected && _socket != null) {
      debugPrint('♻️ Reuso de conexión socket existente');
      return true;
    }
    if (_socket != null && _socket!.connected) {
      _isConnected = true;
      debugPrint('♻️ Socket ya conectado (flag reparado)');
      return true;
    }
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        debugPrint('❌ No hay token para conectar');
        return false;
      }

      debugPrint('🔑 Conectando con token: ${token.substring(0, 20)}...');

      // Configurar socket (solo crear si no existe)
      _socket = io.io(
        'https://sala-chat-backend-production.up.railway.app',
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .disableAutoConnect() // desactivar auto connect para controlar manualmente
            .setAuth({'token': token})
            .build(),
      );

      // Evitar registrar eventos múltiples
      if (!_eventsRegistrados) {
        _socket!.onConnect((_) {
          _isConnected = true;
            debugPrint('✅ Conectado al servidor de chat');
            _notifyCallbacks('connected', null);
        });

        // Debug global: log de cualquier evento recibido (excepto ping/pong internos)
        _socket!.onAny((event, data) {
          if (event == 'ping' || event == 'pong') return;
          debugPrint('🌐 [onAny] event=$event dataKeys=${data is Map ? data.keys.toList() : data.runtimeType}');
        });

        _socket!.onDisconnect((_) {
          _isConnected = false;
          debugPrint('❌ Desconectado del servidor');
          // Guardar snapshot de salas actuales para intentar rejoin al reconectar
          _joinedRoomsSnapshotBeforeDisconnect = Set.from(_joinedRooms);
          _notifyCallbacks('disconnected', null);
        });

        _socket!.onConnectError((error) {
          _isConnected = false;
          debugPrint('❌ Error de conexión: $error');
          _notifyCallbacks('connect_error', error);
        });

        _socket!.on('auth_error', (data) {
          debugPrint('❌ Error de autenticación: $data');
          _notifyCallbacks('auth_error', data);
          disconnect();
        });

        // Al conectar nuevamente, re-join a las salas que teníamos
        on('connected', (_) {
          debugPrint('✨ Socket reconectado, verificando salas...');
          final toRejoin = Set<String>.from(_joinedRooms);
          toRejoin.addAll(_joinedRoomsSnapshotBeforeDisconnect);
          
          if (toRejoin.isNotEmpty) {
            debugPrint('🔁 Reuniéndose automáticamente a salas: ${toRejoin.join(', ')}');
            for (final room in toRejoin) {
              // Reset flags para permitir rejoin
              _joinedRooms.remove(room);
              _pendingJoin.remove(room);
              // Delay para evitar spam al servidor
              Future.delayed(Duration(milliseconds: 100 * toRejoin.toList().indexOf(room)), () {
                joinRoomForce(room, force: true);
              });
            }
            _joinedRoomsSnapshotBeforeDisconnect.clear();
          }
        });

        // Eventos del chat
        _setupChatEvents();
        _eventsRegistrados = true;
      } else {
        debugPrint('🔁 Eventos ya registrados, no se duplican');
      }

      // Conectar si aún no
      if (!(_socket!.connected)) {
        _socket!.connect();
      }
      return true;
    } catch (e) {
      debugPrint('❌ Error conectando socket: $e');
      return false;
    }
  }

  // Configurar eventos del chat (solo se llama internamente si no registrados)
  void _setupChatEvents() {
    if (_socket == null) return;

    // limpiar previos
    for (final ev in [
      'new_message','user_online','user_offline','user_joined_room','user_left_room','joined_room','user_typing','user_stop_typing','message_read','message_reaction','error'
    ]) { _socket!.off(ev); }

    // Nuevo mensaje
    _socket!.on('new_message', (data) {
      debugPrint('📬 Nuevo mensaje recibido: ${data['content']}');
      _notifyCallbacks('new_message', data);
    });

    // Usuario online/offline
    _socket!.on('user_online', (data) {
      debugPrint('🟢 Usuario online: ${data['username'] ?? data['userId']}');
      _usuariosConectados = data['totalConnected'] ?? (_usuariosConectados + 1);
      _usuariosSuscritos = data['totalRegistered'] ?? _usuariosSuscritos;
      _notifyCallbacks('user_online', data);
      _notifyCallbacks('users_count_updated', {
        'connected': _usuariosConectados,
        'subscribed': _usuariosSuscritos,
        'totalRegistered': data['totalRegistered'] ?? _usuariosSuscritos,
      });
    });

    _socket!.on('user_offline', (data) {
      debugPrint('🔴 Usuario offline: ${data['username'] ?? data['userId']}');
      _usuariosConectados = data['totalConnected'] ?? (_usuariosConectados - 1).clamp(0, 999);
      _usuariosSuscritos = data['totalRegistered'] ?? _usuariosSuscritos;
      _notifyCallbacks('user_offline', data);
      _notifyCallbacks('users_count_updated', {
        'connected': _usuariosConectados,
        'subscribed': _usuariosSuscritos,
        'totalRegistered': data['totalRegistered'] ?? _usuariosSuscritos,
      });
    });

    // Eventos de sala
    _socket!.on('user_joined_room', (data) => _notifyCallbacks('user_joined_room', data));

    _socket!.on('user_left_room', (data) => _notifyCallbacks('user_left_room', data));

    // Confirmación de unirse a sala
    _socket!.on('joined_room', (data) {
      final room = data['roomId'] ?? data['roomName'];
      debugPrint('✅ Te uniste a sala (tracking): $room');
      if (room is String) {
        _pendingJoin.remove(room);
        _joinedRooms.add(room);
        // Actualizar contadores con datos del servidor
        final roomSubscribers = data['roomSubscribers'] ?? data['subscribers'] ?? 0;
        _suscritosPorSala[room] = roomSubscribers;
        _usuariosConectados = data['totalConnected'] ?? _usuariosConectados;
        _usuariosSuscritos = data['totalRegistered'] ?? _usuariosSuscritos;
      }
      _notifyCallbacks('joined_room', data);
      _notifyCallbacks('users_count_updated', {
        'connected': _usuariosConectados,
        'subscribed': _usuariosSuscritos,
        'roomSubscribers': _suscritosPorSala[room] ?? 0,
      });
    });

    // Indicadores de escritura
    _socket!.on('user_typing', (data) => _notifyCallbacks('user_typing', data));

    _socket!.on('user_stop_typing', (data) => _notifyCallbacks('user_stop_typing', data));

    // Mensaje leído
    _socket!.on('message_read', (data) => _notifyCallbacks('message_read', data));

    // Reacciones
    _socket!.on('message_reaction', (data) => _notifyCallbacks('message_reaction', data));

    // Multimedia compartido (feed)
    _socket!.on('multimedia_compartido', (data) {
      debugPrint('🎯 Socket nativo recibió multimedia_compartido: $data');
      _notifyCallbacks('multimedia_compartido', data);
    });

    // Eventos de contenido (legacy)
    _socket!.on('nuevo_contenido', (data) => _notifyCallbacks('nuevo_contenido', data));
    _socket!.on('historial_contenido', (data) => _notifyCallbacks('historial_contenido', data));

    // Errores
    _socket!.on('error', (data) {
      debugPrint('❌ Error del servidor: $data');
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
    _eventsRegistrados = false;
    _joinedRooms.clear();
    _pendingJoin.clear();
  }

  // === MÉTODOS DE EVENTOS ===

  // Agregar callback para evento
  void on(String event, Function callback) {
    _eventCallbacks.putIfAbsent(event, () => []);
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
    final list = _eventCallbacks[event];
    if (list == null) return;
    for (final cb in List<Function>.from(list)) {
      try { cb(data); } catch (e) { debugPrint('❌ Error en callback $event: $e'); }
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
      debugPrint('❌ No conectado al servidor');
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
    joinRoomForce(roomId, force: false);
  }

  // Permite forzar join aunque pensemos que ya estamos unidos (para pantallas que se reconstruyen)
  void joinRoomForce(String roomId, {bool force = true}) {
    if (!_isConnected || _socket == null) {
      debugPrint('❌ No conectado al servidor');
      return;
    }
    if (!force) {
      if (_joinedRooms.contains(roomId)) {
        debugPrint('⏭️ Already in room $roomId, skip join');
        return;
      }
      if (_pendingJoin.contains(roomId)) {
        debugPrint('⏳ Join ya pendiente para $roomId');
        return;
      }
    } else {
      // reset flags para permitir rejoin
      _joinedRooms.remove(roomId);
      _pendingJoin.remove(roomId);
    }
    _pendingJoin.add(roomId);
    debugPrint(force ? '🔁 Forzando join a $roomId' : '➡️ Join a $roomId');
    _socket!.emit('join_room', {'roomId': roomId});
  }

  // Salir de sala
  void leaveRoom(String roomId) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit('leave_room', {'roomId': roomId});
    _joinedRooms.remove(roomId);
    _pendingJoin.remove(roomId);
    debugPrint('🚪 Saliendo de sala: $roomId');
  }

  bool isInRoom(String roomId) => _joinedRooms.contains(roomId);
  bool isJoining(String roomId) => _pendingJoin.contains(roomId);
  
  // Método para asegurar que estamos en la sala (rejoin si es necesario)
  void ensureInRoom(String roomId) {
    if (!isInRoom(roomId) && !isJoining(roomId)) {
      debugPrint('🔄 Asegurando suscripción a sala: $roomId');
      joinRoomForce(roomId, force: true);
    }
  }

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
    _socket!.emit('add_reaction', {'messageId': messageId, 'emoji': emoji});
  }

  // Método público para emitir eventos personalizados
  void emit(String event, dynamic data) {
    if (!_isConnected || _socket == null) return;
    _socket!.emit(event, data);
  }
}
