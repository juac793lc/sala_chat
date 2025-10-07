import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../config/endpoints.dart';

class AuthService {
  static String get baseUrl => Endpoints.apiAuth;
  // Cache simple en memoria del usuario actual para evitar verify repetido lento
  static UserModel? _cachedUser;
  static DateTime? _cachedAt;
  static const Duration _userCacheTtl = Duration(minutes: 5);
  
  // Obtener token almacenado
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // Guardar token
  static Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  // Eliminar token
  static Future<void> removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  // Headers con autenticación
  static Future<Map<String, String>> getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Unirse al chat con nombre
  static Future<AuthResult> joinChat({
    required String username,
  }) async {
    try {
      debugPrint('🔍 Intentando conectar a: $baseUrl/join');
      debugPrint('📤 Enviando usuario: $username');
      
      final response = await http.post(
        Uri.parse('$baseUrl/join'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
        }),
      ).timeout(Duration(seconds: 10));

      debugPrint('📥 Respuesta status: ${response.statusCode}');
      debugPrint('📥 Respuesta headers: ${response.headers}');
      debugPrint('📥 Respuesta body: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await _saveToken(data['token']);
        debugPrint('✅ Token guardado correctamente');
        return AuthResult(
          success: true,
          user: UserModel.fromJson(data['user']),
          message: data['message'],
          isNewUser: data['isNewUser'] ?? false,
        );
      } else {
        debugPrint('❌ Error del servidor: ${data['error']}');
        return AuthResult(
          success: false,
          error: data['error'] ?? 'Error uniéndose al chat',
        );
      }
    } catch (e) {
      debugPrint('❌ Excepción capturada: $e');
      debugPrint('❌ Tipo de excepción: ${e.runtimeType}');
      return AuthResult(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  // Obtener usuarios conectados
  static Future<UsersResult> getConnectedUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users'),
        headers: await getHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return UsersResult(
          success: true,
          users: (data['users'] as List)
              .map((user) => UserModel.fromJson(user))
              .toList(),
          count: data['count'],
        );
      } else {
        return UsersResult(
          success: false,
          error: data['error'] ?? 'Error obteniendo usuarios',
        );
      }
    } catch (e) {
      return UsersResult(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  // Verificar token
  static Future<AuthResult> verifyToken() async {
    try {
      // Retornar cache si existe y no venció
      if (_cachedUser != null && _cachedAt != null && DateTime.now().difference(_cachedAt!) < _userCacheTtl) {
        return AuthResult(success: true, user: _cachedUser);
      }
      final token = await getToken();
      if (token == null) {
        return AuthResult(success: false, error: 'No hay token');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/verify'),
        headers: await getHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['valid'] == true) {
        final result = AuthResult(
          success: true,
          user: UserModel.fromJson(data['user']),
        );
        _cachedUser = result.user;
        _cachedAt = DateTime.now();
        return result;
      } else {
        await removeToken();
        return AuthResult(
          success: false,
          error: data['error'] ?? 'Token inválido',
        );
      }
    } catch (e) {
      return AuthResult(
        success: false,
        error: 'Error verificando token: $e',
      );
    }
  }

  static UserModel? getCachedUser() {
    if (_cachedUser != null && _cachedAt != null && DateTime.now().difference(_cachedAt!) < _userCacheTtl) {
      return _cachedUser;
    }
    return null;
  }

  // Logout
  static Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: await getHeaders(),
      );
    } catch (e) {
      debugPrint('Error en logout: $e');
    } finally {
      await removeToken();
    }
  }
}

// Modelo de usuario
class UserModel {
  final String id;
  final String username;
  final String avatar;
  final bool isOnline;
  final DateTime lastSeen;

  UserModel({
    required this.id,
    required this.username,
    required this.avatar,
    required this.isOnline,
    required this.lastSeen,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? json['_id'] ?? 'unknown',
      username: json['username'] ?? 'Usuario',
      avatar: json['avatar'] ?? 'UN:#4ECDC4',
      isOnline: json['isOnline'] ?? false,
      lastSeen: json['lastSeen'] != null 
          ? DateTime.parse(json['lastSeen'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'avatar': avatar,
      'isOnline': isOnline,
      'lastSeen': lastSeen.toIso8601String(),
    };
  }

  // Obtener iniciales y color del avatar
  String get initials {
    if (avatar.contains(':')) {
      return avatar.split(':')[0];
    }
    return username.substring(0, 2).toUpperCase();
  }

  String get avatarColor {
    if (avatar.contains(':')) {
      return avatar.split(':')[1];
    }
    return '#4ECDC4';
  }
}

// Resultado de autenticación
class AuthResult {
  final bool success;
  final UserModel? user;
  final String? message;
  final String? error;
  final bool isNewUser;

  AuthResult({
    required this.success,
    this.user,
    this.message,
    this.error,
    this.isNewUser = false,
  });
}

// Resultado de lista de usuarios
class UsersResult {
  final bool success;
  final List<UserModel>? users;
  final int? count;
  final String? error;

  UsersResult({
    required this.success,
    this.users,
    this.count,
    this.error,
  });
}
