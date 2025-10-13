// 🟢 Build actualizado: endpoints.dart ejecutando versión 12-oct-2025
// Generated config: toggle between local and remote backend for easy testing.
// Set `useLocal = true` for local dev (http://localhost:3001)
// Set `useLocal = false` to point to the production/deployed backend.

class Endpoints {
  // During development set useLocal = true to point Flutter at your local
  // backend (http://localhost:3001). Set to false to use deployed backend.
  static const bool useLocal = false; // toggle for quick local testing (false -> production)
  static const String _prod = 'https://notimapa-production.up.railway.app';
  static const String _local = 'http://localhost:3001';

  static String get base => useLocal ? _local : _prod;

  // Rutas de API
  static String get apiAuth => '$base/api/auth';
  static String get apiChat => '$base/api/chat';
  static String get apiMedia => '$base/api/media';

  // URL para sockets (sin path)
  // Socket URL: for local dev use http but socket_service will adjust
  static String get socketUrl => base.replaceFirst(RegExp(r"^http"), 'wss');

  // Endpoint para obtener VAPID public key (si usas push)
  static String get vapidKey => '$base/api/push/vapidPublicKey';
}
