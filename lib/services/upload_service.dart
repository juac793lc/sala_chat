import 'dart:convert';
import 'dart:html' as html; // ignore: avoid_web_libraries_in_flutter
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;

import 'web_storage_service.dart';

class UploadService {
  // Ajustar al puerto real del backend (server.js usa 3000 por defecto)
  static const String baseUrl = 'https://sala-chat-backend-production.up.railway.app';
  
  /// Sube un archivo multimedia al servidor y retorna la URL
  static Future<UploadResult> uploadFile(
    String filePathOrId,
    String mediaType, {
    String? roomId,
    String? userId,
    String? userNombre,
    int? durationSeconds,
  }) async {
    try {
      debugPrint('📤 Iniciando upload: $filePathOrId (${kIsWeb ? 'Web' : 'Mobile'})');
      
      if (kIsWeb) {
        return await _uploadFromWeb(
          filePathOrId,
          mediaType,
          roomId: roomId,
          userId: userId,
          userNombre: userNombre,
          durationSeconds: durationSeconds,
        );
      } else {
        return await _uploadFromMobile(
          filePathOrId,
          mediaType,
          roomId: roomId,
          userId: userId,
          userNombre: userNombre,
          durationSeconds: durationSeconds,
        );
      }
      
    } catch (e) {
      debugPrint('❌ Error en uploadFile: $e');
      rethrow;
    }
  }

  /// Upload desde Flutter Web usando blob
  static Future<UploadResult> _uploadFromWeb(
    String fileId,
    String mediaType, {
    String? roomId,
    String? userId,
    String? userNombre,
    int? durationSeconds,
  }) async {
    try {
      // Recuperar blob URL
      final blobUrl = await WebStorageService.getBlob(fileId);
      if (blobUrl == null) {
        throw Exception('Archivo no encontrado en web storage: $fileId');
      }

      // Convertir blob a bytes
      final bytes = await WebStorageService.blobToBytes(blobUrl);
      
      // Preparar multipart request
      final uri = Uri.parse('$baseUrl/api/media/upload');
      final request = http.MultipartRequest('POST', uri);
      
      // Generar nombre de archivo
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${mediaType}_$timestamp.${_getExtensionForMediaType(mediaType)}';
      final mimeType = _getMimeTypeForMediaType(mediaType);
      
      // Agregar archivo desde bytes
      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      );
      request.files.add(multipartFile);
      
      // Agregar metadata
      request.fields['mediaType'] = mediaType;
      request.fields['originalName'] = fileName;
      request.fields['mimeType'] = mimeType;
      request.fields['fileSize'] = bytes.length.toString();
      if (roomId != null) request.fields['roomId'] = roomId;
      if (userId != null) request.fields['userId'] = userId;
      if (userNombre != null) request.fields['userNombre'] = userNombre;
      if (durationSeconds != null) {
        request.fields['durationSeconds'] = durationSeconds.toString();
      }
      
      debugPrint('📊 Subiendo desde web:');
      debugPrint('   - Nombre: $fileName');
      debugPrint('   - Tipo: $mimeType');
      debugPrint('   - Tamaño: ${bytes.length} bytes');
      
      // Enviar request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResponse = json.decode(responseBody);
        final result = UploadResult.fromJson(jsonResponse);
        
        debugPrint('✅ Upload exitoso desde web: ${result.url}');
        return result;
      } else {
        debugPrint('❌ Error en upload web: ${response.statusCode}');
        debugPrint('❌ Respuesta: $responseBody');
        throw Exception('Error uploading file from web: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('❌ Error en _uploadFromWeb: $e');
      rethrow;
    }
  }

  /// Upload desde móvil usando archivo
  static Future<UploadResult> _uploadFromMobile(
    String filePath,
    String mediaType, {
    String? roomId,
    String? userId,
    String? userNombre,
    int? durationSeconds,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Archivo no encontrado: $filePath');
      }

      // Preparar multipart request
      final uri = Uri.parse('$baseUrl/api/media/upload');
      final request = http.MultipartRequest('POST', uri);
      
      // Obtener mime type
      final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
      final fileName = path.basename(filePath);
      
      // Agregar archivo
      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        filePath,
        filename: fileName,
      );
      request.files.add(multipartFile);
      
      // Agregar metadata
      request.fields['mediaType'] = mediaType;
      request.fields['originalName'] = fileName;
      request.fields['mimeType'] = mimeType;
      request.fields['fileSize'] = (await file.length()).toString();
      if (roomId != null) request.fields['roomId'] = roomId;
      if (userId != null) request.fields['userId'] = userId;
      if (userNombre != null) request.fields['userNombre'] = userNombre;
      if (durationSeconds != null) {
        request.fields['durationSeconds'] = durationSeconds.toString();
      }
      
      debugPrint('📊 Subiendo desde móvil:');
      debugPrint('   - Nombre: $fileName');
      debugPrint('   - Tipo: $mimeType');
      debugPrint('   - Tamaño: ${await file.length()} bytes');
      
      // Enviar request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResponse = json.decode(responseBody);
        final result = UploadResult.fromJson(jsonResponse);
        
        debugPrint('✅ Upload exitoso desde móvil: ${result.url}');
        return result;
      } else {
        debugPrint('❌ Error en upload móvil: ${response.statusCode}');
        debugPrint('❌ Respuesta: $responseBody');
        throw Exception('Error uploading file from mobile: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('❌ Error en _uploadFromMobile: $e');
      rethrow;
    }
  }

  /// Obtiene la extensión de archivo para un tipo de media
  static String _getExtensionForMediaType(String mediaType) {
    switch (mediaType) {
      case 'audio':
        return 'webm'; // Usar formato webm (opus) capturado en navegador
      case 'image':
        return 'jpg';
      case 'video':
        return 'mp4';
      default:
        return 'bin';
    }
  }

  /// Obtiene el mime type para un tipo de media
  static String _getMimeTypeForMediaType(String mediaType) {
    switch (mediaType) {
      case 'audio':
        return 'audio/webm';
      case 'image':
        return 'image/jpeg';
      case 'video':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  /// Sube un archivo de audio específicamente
  static Future<UploadResult> uploadAudio(String audioPath, {
    String? roomId,
    String? userId,
    int? durationSeconds,
  }) async {
    return await uploadFile(
      audioPath,
      'audio',
      roomId: roomId,
      userId: userId,
      durationSeconds: durationSeconds,
    );
  }

  /// Sube un Blob de audio directamente (para web)
  static Future<UploadResult> uploadAudioBlob(
    dynamic blob, {
    String? roomId,
    String? userId,
    int? durationSeconds,
  }) async {
    try {
      debugPrint('📤 Subiendo audio blob directamente...');
      
      if (!kIsWeb) {
        throw Exception('uploadAudioBlob solo funciona en web');
      }

      // Convertir blob a bytes usando JavaScript
      final bytes = await _blobToBytes(blob);

      // Detectar tipo real del blob
      String realMime = 'audio/webm';
      String extension = 'webm';
      try {
        final htmlBlob = blob as html.Blob; // if cast fails, permanecen defaults
        if (htmlBlob.type.isNotEmpty) {
          realMime = htmlBlob.type; // ej: audio/webm;codecs=opus
          if (realMime.contains('wav')) { extension = 'wav'; }
          else if (realMime.contains('mp4')) { extension = 'm4a'; }
          else if (realMime.contains('mpeg')) { extension = 'mp3'; }
          else { extension = 'webm'; }
        }
      } catch (e) {
        debugPrint('⚠️ No se pudo obtener mime del blob, usando defaults webm: $e');
      }
      
      // Preparar multipart request
      final uri = Uri.parse('$baseUrl/api/media/upload');
      final request = http.MultipartRequest('POST', uri);
      
      // Generar nombre de archivo
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'web_audio_$timestamp.$extension';
      final mimeType = realMime.split(';').first; // quitar ;codecs=opus para header limpio
      
      // Agregar archivo desde bytes
      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      );
      request.files.add(multipartFile);
      
      // Agregar metadata
      request.fields['mediaType'] = 'audio';
      request.fields['originalName'] = fileName;
      request.fields['mimeType'] = mimeType;
      request.fields['fileSize'] = bytes.length.toString();
      if (roomId != null) request.fields['roomId'] = roomId;
      if (userId != null) request.fields['userId'] = userId;
      if (durationSeconds != null) {
        request.fields['durationSeconds'] = durationSeconds.toString();
      }
      
  debugPrint('📊 Subiendo audio blob (mime real detectado):');
      debugPrint('   - Nombre: $fileName');
      debugPrint('   - Tipo: $mimeType');
      debugPrint('   - Tamaño: ${bytes.length} bytes');
      
      // Enviar request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResponse = json.decode(responseBody);
        final result = UploadResult.fromJson(jsonResponse);
        
        debugPrint('✅ Upload de blob exitoso: ${result.url}');
        return result;
      } else {
        debugPrint('❌ Error en upload de blob: ${response.statusCode}');
        debugPrint('❌ Respuesta: $responseBody');
        throw Exception('Error uploading audio blob: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('❌ Error en uploadAudioBlob: $e');
      rethrow;
    }
  }

  /// Sube un archivo de imagen específicamente
  static Future<UploadResult> uploadImage(String imagePath) async {
    return await uploadFile(imagePath, 'image');
  }

  /// Sube un archivo de video específicamente
  static Future<UploadResult> uploadVideo(String videoPath) async {
    return await uploadFile(videoPath, 'video');
  }

  /// Descarga un archivo del servidor y lo guarda localmente
  static Future<String> downloadFile(String url, String localPath) async {
    try {
      debugPrint('📥 Descargando: $url');
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);
        
        debugPrint('✅ Descarga exitosa: $localPath');
        return localPath;
      } else {
        throw Exception('Error downloading file: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error en downloadFile: $e');
      rethrow;
    }
  }

  /// Verifica si una URL de servidor es válida y accesible
  static Future<bool> isUrlAccessible(String url) async {
    try {
      final response = await http.head(Uri.parse(url));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ URL no accesible: $url');
      return false;
    }
  }

  /// Elimina un archivo del servidor (si el servidor lo soporta)
  static Future<bool> deleteFileFromServer(String url) async {
    try {
      final response = await http.delete(Uri.parse(url));
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint('❌ Error eliminando archivo del servidor: $e');
      return false;
    }
  }

  /// Convierte un Blob a bytes usando FileReader (solo web)
  static Future<Uint8List> _blobToBytes(dynamic blob) async {
    if (!kIsWeb) {
      throw Exception('_blobToBytes solo funciona en web');
    }

    // Usar FileReader para convertir el Blob a bytes
    final reader = html.FileReader();
    reader.readAsArrayBuffer(blob as html.Blob);
    
    // Esperar a que termine la lectura
    await reader.onLoadEnd.first;
    
    if (reader.result != null) {
      return Uint8List.fromList((reader.result as List<int>));
    } else {
      throw Exception('Error leyendo blob');
    }
  }
}

/// Clase para el resultado del upload
class UploadResult {
  final String url;
  final String fileName;
  final String fileId; // Legacy (server original)
  final String? mediaId; // Nuevo ID persistente
  final int fileSize;
  final String mimeType;
  final DateTime uploadedAt;

  UploadResult({
    required this.url,
    required this.fileName,
    required this.fileId,
    required this.fileSize,
    required this.mimeType,
    required this.uploadedAt,
    this.mediaId,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      url: json['url'] ?? '',
      fileName: json['fileName'] ?? json['fileName'] ?? '',
      fileId: json['fileId'] ?? json['mediaId'] ?? '',
      mediaId: json['mediaId'],
      fileSize: json['fileSize'] ?? 0,
      mimeType: json['mimeType'] ?? '',
      uploadedAt: json['uploadedAt'] != null
          ? DateTime.parse(json['uploadedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'fileName': fileName,
      'fileId': fileId,
      'mediaId': mediaId,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'uploadedAt': uploadedAt.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'UploadResult(url: $url, fileName: $fileName, mediaId: $mediaId, size: $fileSize)';
  }
}
