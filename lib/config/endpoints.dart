// Generated config: toggle between local and remote backend for easy testing.
// Set `useLocal = true` for local dev (http://localhost:3001)
// Set `useLocal = false` to point to the production/deployed backend.

class Endpoints {
  // cambiar a true para desarrollo local
  static const bool useLocal = true;

  // URL local del backend
  static const String localBase = 'http://localhost:3001';

  // URL remota (producción)
  static const String remoteBase = 'https://sala-chat-backend-production.up.railway.app';

  static String get base => useLocal ? localBase : remoteBase;
  static String get apiAuth => '${base}/api/auth';
  static String get apiChat => '${base}/api/chat';
  static String get apiMedia => '${base}/api/media';
}
