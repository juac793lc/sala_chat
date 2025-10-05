import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../models/message_model.dart'; // agregado

class ChatService {
  static const String baseUrl = 'http://localhost:3000/api/chat';

  // === SALAS ===

  // Obtener salas públicas
  static Future<RoomsResult> getPublicRooms({
    int page = 1,
    int limit = 20,
    String search = '',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/rooms').replace(queryParameters: {
        'page': page.toString(),
        'limit': limit.toString(),
        if (search.isNotEmpty) 'search': search,
      });

      final response = await http.get(uri, headers: await AuthService.getHeaders());
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return RoomsResult(
          success: true,
          rooms: (data['rooms'] as List)
              .map((room) => RoomModel.fromJson(room))
              .toList(),
          pagination: PaginationModel.fromJson(data['pagination']),
        );
      } else {
        return RoomsResult(
          success: false,
          error: data['error'] ?? 'Error obteniendo salas',
        );
      }
    } catch (e) {
      return RoomsResult(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  // Obtener mis salas
  static Future<RoomsResult> getMyRooms() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/rooms/my'),
        headers: await AuthService.getHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return RoomsResult(
          success: true,
          rooms: (data['rooms'] as List)
              .map((room) => RoomModel.fromJson(room))
              .toList(),
        );
      } else {
        return RoomsResult(
          success: false,
          error: data['error'] ?? 'Error obteniendo mis salas',
        );
      }
    } catch (e) {
      return RoomsResult(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  // Crear nueva sala
  static Future<RoomResult> createRoom({
    required String name,
    String description = '',
    String type = 'public',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/rooms'),
        headers: await AuthService.getHeaders(),
        body: jsonEncode({
          'name': name,
          'description': description,
          'type': type,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return RoomResult(
          success: true,
          room: RoomModel.fromJson(data['room']),
          message: data['message'],
        );
      } else {
        return RoomResult(
          success: false,
          error: data['error'] ?? 'Error creando sala',
        );
      }
    } catch (e) {
      return RoomResult(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  // Obtener detalles de sala
  static Future<RoomResult> getRoomDetails(String roomId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/rooms/$roomId'),
        headers: await AuthService.getHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return RoomResult(
          success: true,
          room: RoomModel.fromJson(data),
        );
      } else {
        return RoomResult(
          success: false,
          error: data['error'] ?? 'Sala no encontrada',
        );
      }
    } catch (e) {
      return RoomResult(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  // Unirse a sala
  static Future<ApiResult> joinRoom(String roomId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/rooms/$roomId/join'),
        headers: await AuthService.getHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResult(
          success: true,
          message: data['message'],
        );
      } else {
        return ApiResult(
          success: false,
          error: data['error'] ?? 'Error uniéndose a la sala',
        );
      }
    } catch (e) {
      return ApiResult(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  // Salir de sala
  static Future<ApiResult> leaveRoom(String roomId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/rooms/$roomId/leave'),
        headers: await AuthService.getHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResult(
          success: true,
          message: data['message'],
        );
      } else {
        return ApiResult(
          success: false,
          error: data['error'] ?? 'Error saliendo de la sala',
        );
      }
    } catch (e) {
      return ApiResult(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  // === MENSAJES ===

  // Obtener mensajes de una sala
  static Future<MessagesResult> getRoomMessages({
    required String roomId,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/rooms/$roomId/messages').replace(
        queryParameters: {
          'page': page.toString(),
          'limit': limit.toString(),
        },
      );

      final response = await http.get(uri, headers: await AuthService.getHeaders());
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return MessagesResult(
          success: true,
          messages: (data['messages'] as List)
              .map((msg) => MessageModel.fromJson(msg))
              .toList(),
          pagination: PaginationModel.fromJson(data['pagination']),
        );
      } else {
        return MessagesResult(
          success: false,
          error: data['error'] ?? 'Error obteniendo mensajes',
        );
      }
    } catch (e) {
      return MessagesResult(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  // === ARCHIVOS ===

  // Subir archivo
  static Future<FileUploadResult> uploadFile(File file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/upload'),
      );

      // Agregar headers de autenticación
      final headers = await AuthService.getHeaders();
      request.headers.addAll(headers);

      // Agregar archivo
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return FileUploadResult(
          success: true,
          file: UploadedFile.fromJson(data['file']),
          message: data['message'],
        );
      } else {
        return FileUploadResult(
          success: false,
          error: data['error'] ?? 'Error subiendo archivo',
        );
      }
    } catch (e) {
      return FileUploadResult(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }
}

// === MODELOS ===

// Modelo de sala
class RoomModel {
  final String id;
  final String name;
  final String description;
  final String type;
  final String? avatar;
  final int memberCount;
  final Map<String, dynamic> settings;
  final DateTime lastActivity;
  final DateTime createdAt;
  final UserModel? creator;
  final String? myRole;
  final bool? isMember;

  RoomModel({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.avatar,
    required this.memberCount,
    required this.settings,
    required this.lastActivity,
    required this.createdAt,
    this.creator,
    this.myRole,
    this.isMember,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      type: json['type'],
      avatar: json['avatar'],
      memberCount: json['memberCount'],
      settings: json['settings'] ?? {},
      lastActivity: DateTime.parse(json['lastActivity']),
      createdAt: DateTime.parse(json['createdAt']),
      creator: json['creator'] != null ? UserModel.fromJson(json['creator']) : null,
      myRole: json['myRole'],
      isMember: json['isMember'],
    );
  }
}

// Modelo de paginación
class PaginationModel {
  final int page;
  final int limit;
  final int total;
  final int pages;

  PaginationModel({
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });

  factory PaginationModel.fromJson(Map<String, dynamic> json) {
    return PaginationModel(
      page: json['page'],
      limit: json['limit'],
      total: json['total'],
      pages: json['pages'],
    );
  }
}

// Modelo de archivo subido
class UploadedFile {
  final String url;
  final String originalName;
  final String filename;
  final int size;
  final String mimeType;

  UploadedFile({
    required this.url,
    required this.originalName,
    required this.filename,
    required this.size,
    required this.mimeType,
  });

  factory UploadedFile.fromJson(Map<String, dynamic> json) {
    return UploadedFile(
      url: json['url'],
      originalName: json['originalName'],
      filename: json['filename'],
      size: json['size'],
      mimeType: json['mimeType'],
    );
  }
}

// === RESULTADOS ===

class ApiResult {
  final bool success;
  final String? message;
  final String? error;

  ApiResult({
    required this.success,
    this.message,
    this.error,
  });
}

class RoomsResult extends ApiResult {
  final List<RoomModel>? rooms;
  final PaginationModel? pagination;

  RoomsResult({
    required bool success,
    this.rooms,
    this.pagination,
    String? message,
    String? error,
  }) : super(success: success, message: message, error: error);
}

class RoomResult extends ApiResult {
  final RoomModel? room;

  RoomResult({
    required bool success,
    this.room,
    String? message,
    String? error,
  }) : super(success: success, message: message, error: error);
}

class MessagesResult extends ApiResult {
  final List<MessageModel>? messages;
  final PaginationModel? pagination;

  MessagesResult({
    required bool success,
    this.messages,
    this.pagination,
    String? message,
    String? error,
  }) : super(success: success, message: message, error: error);
}

class FileUploadResult extends ApiResult {
  final UploadedFile? file;

  FileUploadResult({
    required bool success,
    this.file,
    String? message,
    String? error,
  }) : super(success: success, message: message, error: error);
}