import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/contenido_multimedia.dart';
import 'auth_service.dart';

/// Servicio para obtener y cachear el feed multimedia (imagenes / videos) de una sala.
class MediaFeedService {
  MediaFeedService._internal();
  static final MediaFeedService instance = MediaFeedService._internal();

  // Cache en memoria
  final Map<String, List<ContenidoMultimedia>> _cachePorRoom = {};
  final Map<String, DateTime> _cacheTimestamp = {};
  final Duration cacheTtl = const Duration(seconds: 40); // corto para pruebas

  bool _isFetching = false;

  /// Obtiene el feed (HTTP). Si hay cache reciente y no forceRefresh, devuelve cache.
  Future<List<ContenidoMultimedia>> obtenerFeedRoom(String roomId, {bool forceRefresh = false}) async {
    final ahora = DateTime.now();
    if (!forceRefresh && _cachePorRoom.containsKey(roomId)) {
      final ts = _cacheTimestamp[roomId];
      if (ts != null && ahora.difference(ts) < cacheTtl) {
        return _cachePorRoom[roomId]!;
      }
    }
    if (_isFetching) {
      // Evita llamadas paralelas (simple). Devuelve lo que haya.
      return _cachePorRoom[roomId] ?? [];
    }
    _isFetching = true;
    try {
      final base = AuthService.baseUrl.replaceFirst('/api/auth', '');
      final url = Uri.parse('$base/api/media/by-room/$roomId?limit=100&offset=0');
      final headers = await AuthService.getHeaders();
      final resp = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final data = jsonDecode(resp.body);
      final items = (data['items'] as List? ?? []);
      final List<ContenidoMultimedia> parsed = [];
      for (final raw in items) {
        try {
          final tipoStr = (raw['tipo'] ?? '').toString();
          TipoContenido tipo = TipoContenido.imagen;
          if (tipoStr.contains('video')) { tipo = TipoContenido.video; }
          else if (tipoStr.contains('audio')) { tipo = TipoContenido.audio; } // Por si en futuro
          parsed.add(
            ContenidoMultimedia(
              id: raw['media_id']?.toString() ?? raw['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
              autorId: raw['user_id']?.toString() ?? '0',
              autorNombre: raw['user_nombre']?.toString() ?? raw['autorNombre']?.toString() ?? 'Usuario',
              tipo: tipo,
              url: raw['url']?.toString() ?? '',
              fechaCreacion: _parseDate(raw['created_at']) ?? DateTime.now(),
              comentariosTexto: _parseCount(raw['comentariosTexto'] ?? raw['comentarios_texto']),
              comentariosAudio: _parseCount(raw['comentariosAudio'] ?? raw['comentarios_audio']),
              duracionSegundos: (raw['duration_seconds'] is num) ? (raw['duration_seconds'] as num).round() : 0,
            ),
          );
        } catch (_) {/*ignorar item corrupto*/}
      }
      // Orden ya viene DESC (created_at DESC). Guardamos tal cual.
      _cachePorRoom[roomId] = parsed;
      _cacheTimestamp[roomId] = DateTime.now();
      return parsed;
    } catch (e) {
      // Retornar cache vieja si existe para no dejar vacío
      return _cachePorRoom[roomId] ?? [];
    } finally {
      _isFetching = false;
    }
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try { return DateTime.parse(v.toString()); } catch (_) { return null; }
  }

  int _parseCount(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
      final asNum = num.tryParse(v);
      if (asNum != null) return asNum.toInt();
    }
    return 0;
  }
}
