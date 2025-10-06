import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/comentario.dart';

class HistoryService {
  static const String baseUrl = 'http://localhost:3000/api';
  // Cache en memoria por room para evitar spam y manejar 429
  static final Map<String, _RoomCacheEntry> _roomCache = {};
  static const Duration _cacheTtl = Duration(seconds: 30); // TTL principal
  static const Duration _minInterval = Duration(seconds: 3); // Evitar golpear muy rápido
  
  static Future<List<Comentario>> cargarHistorialRoom(String roomId) async {
    try {
      debugPrint('📚 Cargando historial para room: $roomId');
      final now = DateTime.now();
      final cache = _roomCache[roomId];
      if (cache != null) {
        final age = now.difference(cache.timestamp);
        if (age < _minInterval) {
          debugPrint('🛑 Usando cache (intervalo mínimo) para room $roomId (age=${age.inSeconds}s)');
          return cache.comentarios;
        }
        if (age < _cacheTtl) {
          // Haremos petición, pero si falla (429) devolveremos cache
          debugPrint('ℹ️ Cache existente (age=${age.inSeconds}s), intentando refrescar...');
        }
      }
      
      // Cargar mensajes de la room
      final messagesResponse = await http.get(
        Uri.parse('$baseUrl/messages?roomId=$roomId&limit=100&offset=0'),
      );
      
      // Cargar media de la room  
      final mediaResponse = await http.get(
        Uri.parse('$baseUrl/media/by-room/$roomId?limit=100&offset=0'),
      );
      
      if (messagesResponse.statusCode == 429 || mediaResponse.statusCode == 429) {
        debugPrint('⚠️ 429 Too Many Requests (messages=${messagesResponse.statusCode}, media=${mediaResponse.statusCode})');
        if (cache != null) {
          debugPrint('♻️ Devolviendo cache previo (${cache.comentarios.length} comentarios)');
          return cache.comentarios;
        }
        return [];
      }

      if (messagesResponse.statusCode != 200 || mediaResponse.statusCode != 200) {
        debugPrint('❌ Error cargando historial: messages=${messagesResponse.statusCode}, media=${mediaResponse.statusCode}');
        if (cache != null) {
          debugPrint('♻️ Devolviendo cache previo por fallo de red');
          return cache.comentarios;
        }
        return [];
      }
      
      final messagesData = jsonDecode(messagesResponse.body);
      final mediaData = jsonDecode(mediaResponse.body);
      
      debugPrint('📊 Historial cargado: ${messagesData['count']} mensajes, ${mediaData['count']} medias');
      
      List<Comentario> comentarios = [];
      Map<String, dynamic> mediaMap = {};
      
      // Mapear media por media_id
      for (var media in mediaData['items']) {
        mediaMap[media['media_id']] = media;
      }
      
      // Convertir mensajes a comentarios
      for (var message in messagesData['items']) {
        try {
          final comentario = Comentario(
            id: message['message_id'],
            contenidoId: roomId,
            autorId: message['user_id'] ?? 'user_unknown',
            autorNombre: (message['user_nombre'] ?? message['username'] ?? message['user_id'] ?? 'Usuario').toString(),
            contenido: message['text'] ?? '',
            fechaCreacion: DateTime.parse(message['created_at']),
            tipo: message['media_id'] != null ? TipoComentario.audio : TipoComentario.texto,
            mediaId: message['media_id'],
            mediaUrl: message['media_id'] != null && mediaMap.containsKey(message['media_id']) 
              ? mediaMap[message['media_id']]['url'] 
              : null,
          );
          
          comentarios.add(comentario);
          
        } catch (e) {
          debugPrint('⚠️ Error procesando mensaje ${message['message_id']}: $e');
        }
      }
      
  // Ordenar por fecha ascendente (más antiguos primero) para mostrar en orden cronológico natural
  comentarios.sort((a, b) => a.fechaCreacion.compareTo(b.fechaCreacion));
  // Asignar ordenSecuencia estable incremental
  for (int i = 0; i < comentarios.length; i++) {
    comentarios[i] = comentarios[i].copyWith(ordenSecuencia: i);
  }
      
  debugPrint('✅ Historial procesado: ${comentarios.length} comentarios listos');
  _roomCache[roomId] = _RoomCacheEntry(comentarios, now);
  return comentarios;
      
    } catch (e) {
      debugPrint('❌ Error cargando historial: $e');
      final cache = _roomCache[roomId];
      if (cache != null) {
        debugPrint('♻️ Devolviendo cache previo tras excepción (${cache.comentarios.length})');
        return cache.comentarios;
      }
      return [];
    }
  }
  
  static Future<List<String>> cargarHistorialAudio(String roomId) async {
    try {
      debugPrint('🎵 Cargando historial de audio para room: $roomId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/media/by-room/$roomId?limit=100&offset=0'),
      );
      
      if (response.statusCode != 200) {
        debugPrint('❌ Error cargando media: ${response.statusCode}');
        return [];
      }
      
      final data = jsonDecode(response.body);
      List<String> audioUrls = [];
      
      for (var media in data['items']) {
        if (media['tipo'] == 'audio' && media['url'] != null) {
          audioUrls.add(media['url']);
        }
      }
      
      debugPrint('✅ Audio historial cargado: ${audioUrls.length} archivos');
      return audioUrls;
      
    } catch (e) {
      debugPrint('❌ Error cargando historial audio: $e');
      return [];
    }
  }
}

class _RoomCacheEntry {
  final List<Comentario> comentarios;
  final DateTime timestamp;
  _RoomCacheEntry(this.comentarios, this.timestamp);
}
