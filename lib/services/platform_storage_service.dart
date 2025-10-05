import 'package:flutter/foundation.dart' show kIsWeb;
import 'media_storage_service.dart';
import 'web_storage_service.dart';

/// Adaptador que usa el servicio de almacenamiento correcto según la plataforma
class PlatformStorageService {
  
  /// Guarda un archivo de audio y retorna el identificador
  static Future<String> saveAudio(String pathOrUrl, {String? originalFileName}) async {
    if (kIsWeb) {
      // En web, el path es una blob URL
      print('🌐 Guardando audio en web storage: $pathOrUrl');
      return await WebStorageService.saveBlob(pathOrUrl, 'audio');
    } else {
      // En móvil, usar el servicio de archivos
      print('📱 Guardando audio en móvil: $pathOrUrl');
      return await MediaStorageService.saveAudio(pathOrUrl, originalFileName: originalFileName);
    }
  }

  /// Guarda un archivo de imagen y retorna el identificador
  static Future<String> saveImage(String pathOrUrl) async {
    if (kIsWeb) {
      return await WebStorageService.saveBlob(pathOrUrl, 'image');
    } else {
      return await MediaStorageService.saveImage(pathOrUrl);
    }
  }

  /// Guarda un archivo de video y retorna el identificador
  static Future<String> saveVideo(String pathOrUrl) async {
    if (kIsWeb) {
      return await WebStorageService.saveBlob(pathOrUrl, 'video');
    } else {
      return await MediaStorageService.saveVideo(pathOrUrl);
    }
  }

  /// Recupera un archivo por su identificador y retorna su URL/path
  static Future<String?> getFile(String fileId) async {
    if (kIsWeb) {
      // En web, recuperar blob URL
      return await WebStorageService.getBlob(fileId);
    } else {
      // En móvil, fileId ya es el path completo
      return fileId;
    }
  }

  /// Verifica si un archivo existe
  static Future<bool> fileExists(String fileId) async {
    if (kIsWeb) {
      final blobUrl = await WebStorageService.getBlob(fileId);
      return blobUrl != null;
    } else {
      return await MediaStorageService.fileExists(fileId);
    }
  }

  /// Elimina un archivo
  static Future<bool> deleteFile(String fileId) async {
    if (kIsWeb) {
      return await WebStorageService.deleteFile(fileId);
    } else {
      return await MediaStorageService.deleteFile(fileId);
    }
  }

  /// Obtiene estadísticas de almacenamiento
  static Future<Map<String, dynamic>> getStorageStats() async {
    if (kIsWeb) {
      return await WebStorageService.getStorageStats();
    } else {
      return await MediaStorageService.getStorageStats();
    }
  }

  /// Limpia archivos antiguos
  static Future<void> cleanOldFiles({int maxDays = 30}) async {
    if (kIsWeb) {
      return await WebStorageService.cleanOldFiles(maxDays: maxDays);
    } else {
      return await MediaStorageService.cleanOldFiles(maxDays: maxDays);
    }
  }

  /// Método específico para web: obtiene bytes de blob URL para upload
  static Future<List<int>?> getBytesForUpload(String fileIdOrPath) async {
    if (kIsWeb) {
      // En web, recuperar blob URL y convertir a bytes
      final blobUrl = await WebStorageService.getBlob(fileIdOrPath);
      if (blobUrl != null) {
        return await WebStorageService.blobToBytes(blobUrl);
      }
      return null;
    } else {
      // En móvil, leer archivo desde path
      return await MediaStorageService.getFileSize(fileIdOrPath) > 0 
        ? await _readFileBytes(fileIdOrPath)
        : null;
    }
  }

  /// Helper para leer bytes de archivo en móvil
  static Future<List<int>> _readFileBytes(String filePath) async {
    // Implementar lectura de archivo para móvil si es necesario
    // Por ahora retornar lista vacía
    return [];
  }
}