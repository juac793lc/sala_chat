// Generated config: toggle between local and remote backend for easy testing.
// Set `useLocal = true` for local dev (http://localhost:3001)
// Set `useLocal = false` to point to the production/deployed backend.

class Endpoints {
  // Puedes sobreescribir si quieres usar local o remoto en build-time:
  // --dart-define=USE_LOCAL=true  (o false)
  static final bool useLocal = const String.fromEnvironment('USE_LOCAL', defaultValue: 'true') == 'true';

  // URL local del backend (desarrollo)
  static const String localBase = 'http://localhost:3001';

  // URL remota por defecto (ajusta a la URL que Railway te dio)
  static const String remoteBase = 'https://sala-chat-backend-production.up.railway.app';

  // Prioridad máxima: API_BASE pasada por --dart-define
  static String? get _envBase {
    const apiBase = String.fromEnvironment('API_BASE', defaultValue: '');
    return apiBase.isNotEmpty ? apiBase : null;
  }

  static String get base {
    final env = _envBase;
    if (env != null && env.isNotEmpty) return env;
    return useLocal ? localBase : remoteBase;
  }

  // Rutas de API
  static String get apiAuth => '$base/api/auth';
  static String get apiChat => '$base/api/chat';
  static String get apiMedia => '$base/api/media';

  // URL para sockets (sin path)
  static String get socketUrl => base.replaceFirst(RegExp(r"^http"), 'ws');

  // Endpoint para obtener VAPID public key (si usas push)
  static String get vapidKey => '$base/api/push/vapidPublicKey';
}
