import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';

class AuthProvider with ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _error;

  // Getters
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get error => _error;

  // Limpiar error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Inicializar autenticación (verificar token existente)
  Future<void> initAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await AuthService.verifyToken();
      if (result.success && result.user != null) {
        _currentUser = result.user;
        _isAuthenticated = true;
        
        // Conectar socket si está autenticado
        await SocketService.instance.connect();
      } else {
        _isAuthenticated = false;
        _currentUser = null;
      }
    } catch (e) {
      _error = 'Error verificando autenticación: $e';
      _isAuthenticated = false;
      _currentUser = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Login simplificado (redirige a joinChat)
  Future<bool> login(String email, String password) async {
    // Para compatibilidad, pero ahora solo usamos nombres
    return await joinChat(email); // Usa email como nombre temporalmente
  }

  // Unirse al chat (solo con nombre)
  Future<bool> joinChat(String username) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await AuthService.joinChat(
        username: username,
      );

      if (result.success && result.user != null) {
        _currentUser = result.user;
        _isAuthenticated = true;
        
        // Conectar socket después de unirse
        await SocketService.instance.connect();
        
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = result.error ?? 'Error uniéndose al chat';
        _isAuthenticated = false;
        _currentUser = null;
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error de conexión: $e';
      _isAuthenticated = false;
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Desconectar socket
      SocketService.instance.disconnect();
      
      // Hacer logout en el servidor
      await AuthService.logout();
      
      // Limpiar estado local
      _currentUser = null;
      _isAuthenticated = false;
      _error = null;
    } catch (e) {
      _error = 'Error en logout: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Actualizar usuario
  void updateUser(UserModel user) {
    _currentUser = user;
    notifyListeners();
  }
}