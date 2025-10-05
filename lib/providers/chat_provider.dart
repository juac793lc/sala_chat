import 'package:flutter/foundation.dart';
import '../services/chat_service.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';
import '../models/message_model.dart';

class ChatProvider with ChangeNotifier {
  // Estado general
  bool _isLoading = false;
  String? _error;
  bool _isConnected = false;

  // Salas
  List<RoomModel> _rooms = [];
  List<RoomModel> _myRooms = [];
  RoomModel? _currentRoom;

  // Mensajes
  final Map<String, List<MessageModel>> _roomMessages = {};
  final List<String> _typingUsers = [];

  // Usuarios online
  final Map<String, UserModel> _onlineUsers = {};

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _isConnected;
  List<RoomModel> get rooms => List.unmodifiable(_rooms);
  List<RoomModel> get myRooms => List.unmodifiable(_myRooms);
  RoomModel? get currentRoom => _currentRoom;
  List<String> get typingUsers => List.unmodifiable(_typingUsers);
  Map<String, UserModel> get onlineUsers => Map.unmodifiable(_onlineUsers);

  // Obtener mensajes de una sala específica
  List<MessageModel> getRoomMessages(String roomId) {
    return List.unmodifiable(_roomMessages[roomId] ?? []);
  }

  // Inicializar provider
  void init() {
    _setupSocketListeners();
    _checkConnection();
  }

  // Configurar listeners de socket
  void _setupSocketListeners() {
    final socket = SocketService.instance;

    // Conexión
    socket.on('connected', (_) {
      _isConnected = true;
      notifyListeners();
    });

    socket.on('disconnected', (_) {
      _isConnected = false;
      notifyListeners();
    });

    socket.on('connect_error', (error) {
      _error = 'Error de conexión: $error';
      _isConnected = false;
      notifyListeners();
    });

    // Mensajes
    socket.on('new_message', (data) {
      try {
        final msg = MessageModel.fromJson(Map<String,dynamic>.from(data));
        _addMessage(msg);
      } catch (e) {
        print('❌ Error parseando mensaje: $e');
      }
    });

    // Usuarios online/offline
    socket.on('user_online', (data) {
      try {
        final userData = {
          'id': data['userId'] ?? data['id'] ?? 'unknown',
          'username': data['username'] ?? 'Usuario',
          'avatar': 'UN:#4ECDC4',
          'isOnline': true,
          'lastSeen': DateTime.now().toIso8601String(),
        };
        final user = UserModel.fromJson(userData);
        _onlineUsers[user.id] = user;
        notifyListeners();
      } catch (e) {
        print('❌ Error procesando user_online: $e');
      }
    });

    socket.on('user_offline', (data) {
      final id = data['userId'] ?? data['id'];
      if (id != null) {
        _onlineUsers.remove(id);
        notifyListeners();
      }
    });

    socket.on('joined_room', (data) {
      if (_currentRoom != null) {
        loadRoomMessages(_currentRoom!.id);
      }
    });

    // Escritura
    socket.on('user_typing', (data) {
      final u = data['username'];
      if (u != null && !_typingUsers.contains(u)) {
        _typingUsers.add(u);
        notifyListeners();
      }
    });

    socket.on('user_stop_typing', (data) {
      final u = data['username'];
      if (u != null) {
        _typingUsers.remove(u);
        notifyListeners();
      }
    });

    // Errores
    socket.on('error', (data) {
      _error = data['message'] ?? 'Error del servidor';
      notifyListeners();
    });
  }

  // Verificar estado de conexión
  void _checkConnection() {
    _isConnected = SocketService.instance.isConnected;
    notifyListeners();
  }

  // Limpiar error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // === SALAS ===

  // Cargar salas públicas
  Future<void> loadPublicRooms({String search = ''}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ChatService.getPublicRooms(search: search);
      if (res.success && res.rooms != null) {
        _rooms = res.rooms!;
      } else {
        _error = res.error ?? 'Error cargando salas';
      }
    } catch (e) {
      _error = 'Error de conexión: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Cargar mis salas
  Future<void> loadMyRooms() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ChatService.getMyRooms();
      if (res.success && res.rooms != null) {
        _myRooms = res.rooms!;
      } else {
        _error = res.error ?? 'Error cargando mis salas';
      }
    } catch (e) {
      _error = 'Error de conexión: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Crear sala
  Future<bool> createRoom({
    required String name,
    String description = '',
    String type = 'public',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final r = await ChatService.createRoom(
        name: name,
        description: description,
        type: type,
      );

      if (r.success && r.room != null) {
        _myRooms.insert(0, r.room!);
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = r.error ?? 'Error creando sala';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error de conexión: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Unirse a sala
  Future<bool> joinRoom(String roomId) async {
    try {
      final r = await ChatService.joinRoom(roomId);
      if (r.success) {
        // Unirse al socket room
        SocketService.instance.joinRoom(roomId);
        
        // Recargar mis salas
        await loadMyRooms();
        return true;
      } else {
        _error = r.error ?? 'Error uniéndose a la sala';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error de conexión: $e';
      notifyListeners();
      return false;
    }
  }

  // Establecer sala actual
  void setCurrentRoom(RoomModel room) {
    _currentRoom = room;
    
    // Unirse al socket room si no está conectado
    SocketService.instance.joinRoom(room.id);
    
    // Cargar mensajes si no están cargados
    if (!_roomMessages.containsKey(room.id)) {
      loadRoomMessages(room.id);
    }
    
    notifyListeners();
  }

  // Salir de la sala actual
  void leaveCurrentRoom() {
    if (_currentRoom != null) {
      SocketService.instance.leaveRoom(_currentRoom!.id);
      _currentRoom = null;
      notifyListeners();
    }
  }

  // === MENSAJES ===

  // Cargar mensajes de una sala
  Future<void> loadRoomMessages(String roomId) async {
    try {
      final res = await ChatService.getRoomMessages(roomId: roomId);
      if (res.success && res.messages != null) {
        _roomMessages[roomId] = res.messages!;
        notifyListeners();
      }
    } catch (e) {
      print('Error cargando mensajes: $e');
    }
  }

  // Enviar mensaje
  void sendMessage({
    required String roomId,
    required String content,
    String type = 'text',
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
  }) {
    SocketService.instance.sendMessage(
      roomId: roomId,
      content: content,
      type: type,
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
    );
  }

  // Agregar mensaje a la lista local
  void _addMessage(MessageModel message) {
    final list = _roomMessages.putIfAbsent(message.roomId, () => []);
    if (!list.any((m) => m.id == message.id)) {
      list.add(message);
      notifyListeners();
    }
  }

  // Indicadores de escritura
  void startTyping(String roomId) { SocketService.instance.startTyping(roomId); }
  void stopTyping(String roomId) { SocketService.instance.stopTyping(roomId); }

  // Marcar mensaje como leído
  void markMessageAsRead(String messageId) { SocketService.instance.markMessageAsRead(messageId); }

  // Agregar reacción
  void addReaction(String messageId, String emoji) { SocketService.instance.addReaction(messageId, emoji); }

  // === LIMPIEZA ===

  @override
  void dispose() {
    // No removemos callbacks individuales aquí porque se podrían seguir usando desde otras vistas; se limpia en disconnect.
    super.dispose();
  }
}