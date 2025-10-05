import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'dart:html' as html;
import 'dart:convert';

/// Servicio de almacenamiento específico para Flutter Web
/// Usa IndexedDB para persistir archivos como blobs
class WebStorageService {
  static const String _dbName = 'SalaChatMedia';
  static const String _storeName = 'mediaFiles';
  static const int _dbVersion = 1;
  static bool enableLogs = true; // permitir desactivar logs en runtime

  static void _log(String msg) {
    if (kDebugMode && enableLogs) {
      // ignore: avoid_print
      print(msg);
    }
  }

  /// Guarda un blob URL en IndexedDB y retorna un ID único
  static Future<String> saveBlob(String blobUrl, String mediaType) async {
    try {
      if (!kIsWeb) {
        throw UnsupportedError('WebStorageService solo funciona en web');
      }

  _log('💾 Guardando blob: $blobUrl');
      
      // Generar ID único
      final fileId = 'file_${DateTime.now().millisecondsSinceEpoch}';
      
      // Convertir blob URL a Uint8List
      final response = await html.window.fetch(blobUrl);
      final arrayBuffer = await response.arrayBuffer();
      final bytes = arrayBuffer.asUint8List();
      
  _log('📊 Blob bytes: ${bytes.length}');
      
      // Crear objeto para almacenar
      final fileData = {
        'id': fileId,
        'data': base64Encode(bytes),
        'mediaType': mediaType,
        'createdAt': DateTime.now().toIso8601String(),
        'size': bytes.length,
        'originalBlobUrl': blobUrl,
      };
      
      // Guardar en localStorage (más simple que IndexedDB para esta demo)
      html.window.localStorage['media_$fileId'] = jsonEncode(fileData);
      
  _log('✅ Blob guardado ID: $fileId');
      return fileId;
      
    } catch (e) {
      _log('❌ Error guardando blob: $e');
      rethrow;
    }
  }

  /// Recupera un archivo guardado por su ID
  static Future<String?> getBlob(String fileId) async {
    try {
      if (!kIsWeb) return null;
      
      final jsonData = html.window.localStorage['media_$fileId'];
      if (jsonData == null) return null;
      
      final fileData = jsonDecode(jsonData);
      final bytes = base64Decode(fileData['data']);
      
      // Crear nuevo blob URL
      final blob = html.Blob([bytes]);
      final blobUrl = html.Url.createObjectUrl(blob);
      
  _log('📤 Blob recuperado: $fileId');
      return blobUrl;
      
    } catch (e) {
      _log('❌ Error recuperando blob: $e');
      return null;
    }
  }

  /// Lista todos los archivos guardados
  static Future<List<Map<String, dynamic>>> listFiles() async {
    try {
      if (!kIsWeb) return [];
      
      final files = <Map<String, dynamic>>[];
      
      for (var key in html.window.localStorage.keys) {
        if (key.startsWith('media_')) {
          final jsonData = html.window.localStorage[key];
          if (jsonData != null) {
            final fileData = jsonDecode(jsonData);
            // No incluir los datos binarios en la lista
            files.add({
              'id': fileData['id'],
              'mediaType': fileData['mediaType'],
              'createdAt': fileData['createdAt'],
              'size': fileData['size'],
            });
          }
        }
      }
      
      return files;
    } catch (e) {
      _log('❌ Error listando archivos: $e');
      return [];
    }
  }

  /// Elimina un archivo por su ID
  static Future<bool> deleteFile(String fileId) async {
    try {
      if (!kIsWeb) return false;
      
      html.window.localStorage.remove('media_$fileId');
  _log('🗑️ Archivo eliminado: $fileId');
      return true;
    } catch (e) {
      _log('❌ Error eliminando archivo: $e');
      return false;
    }
  }

  /// Limpia archivos antiguos
  static Future<void> cleanOldFiles({int maxDays = 30}) async {
    try {
      if (!kIsWeb) return;
      
      final now = DateTime.now();
      final keysToDelete = <String>[];
      
      for (var key in html.window.localStorage.keys) {
        if (key.startsWith('media_')) {
          final jsonData = html.window.localStorage[key];
          if (jsonData != null) {
            final fileData = jsonDecode(jsonData);
            final createdAt = DateTime.parse(fileData['createdAt']);
            final daysDiff = now.difference(createdAt).inDays;
            
            if (daysDiff > maxDays) {
              keysToDelete.add(key);
            }
          }
        }
      }
      
      for (var key in keysToDelete) {
        html.window.localStorage.remove(key);
  _log('🗑️ Archivo antiguo eliminado: $key');
      }
    } catch (e) {
      _log('❌ Error limpiando archivos antiguos: $e');
    }
  }

  /// Obtiene estadísticas de almacenamiento
  static Future<Map<String, dynamic>> getStorageStats() async {
    try {
      if (!kIsWeb) return {};
      
      int totalFiles = 0;
      int totalSize = 0;
      Map<String, int> typeCount = {
        'audio': 0,
        'image': 0,
        'video': 0,
      };

      for (var key in html.window.localStorage.keys) {
        if (key.startsWith('media_')) {
          final jsonData = html.window.localStorage[key];
          if (jsonData != null) {
            final fileData = jsonDecode(jsonData);
            totalFiles++;
            totalSize += fileData['size'] as int;
            
            final mediaType = fileData['mediaType'] as String;
            if (typeCount.containsKey(mediaType)) {
              typeCount[mediaType] = typeCount[mediaType]! + 1;
            }
          }
        }
      }

      return {
        'totalFiles': totalFiles,
        'totalSizeBytes': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'filesByType': typeCount,
        'storagePath': 'localStorage (Web)',
      };
    } catch (e) {
      _log('❌ Error obteniendo estadísticas: $e');
      return {};
    }
  }

  /// Convierte blob URL a Uint8List para upload
  static Future<Uint8List> blobToBytes(String blobUrl) async {
    try {
      if (!kIsWeb) {
        throw UnsupportedError('blobToBytes solo funciona en web');
      }
      
      final response = await html.window.fetch(blobUrl);
      final arrayBuffer = await response.arrayBuffer();
      return arrayBuffer.asUint8List();
    } catch (e) {
      _log('❌ Error convirtiendo blob a bytes: $e');
      rethrow;
    }
  }

  /// Estimación simple del uso (bytes) recorriendo claves
  static Future<int> estimateUsage() async {
    if (!kIsWeb) return 0;
    int total = 0;
    for (var key in html.window.localStorage.keys) {
      if (key.startsWith('media_')) {
        final jsonData = html.window.localStorage[key];
        if (jsonData != null) {
          try {
            final fileData = jsonDecode(jsonData);
            total += (fileData['size'] as int? ?? 0);
          } catch (_) {}
        }
      }
    }
    return total;
  }
}