import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class MediaStorageService {
  static const String _mediaFolderName = 'media';
  static const String _audioFolderName = 'audio';
  static const String _imageFolderName = 'images';
  static const String _videoFolderName = 'videos';

  /// Obtiene el directorio base para almacenamiento multimedia
  static Future<Directory> get _mediaDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(path.join(appDir.path, _mediaFolderName));
    
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
      print('📁 Creado directorio multimedia: ${mediaDir.path}');
    }
    
    return mediaDir;
  }

  /// Obtiene el directorio específico para un tipo de media
  static Future<Directory> _getMediaTypeDirectory(String mediaType) async {
    final mediaDir = await _mediaDirectory;
    final typeDir = Directory(path.join(mediaDir.path, mediaType));
    
    if (!await typeDir.exists()) {
      await typeDir.create(recursive: true);
      print('📁 Creado directorio $mediaType: ${typeDir.path}');
    }
    
    return typeDir;
  }

  /// Genera un nombre único para el archivo basado en timestamp
  static String _generateFileName(String extension) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${extension}_$timestamp';
  }

  /// Guarda un archivo de audio y retorna la ruta local
  static Future<String> saveAudio(String tempPath, {String? originalFileName}) async {
    try {
      final audioDir = await _getMediaTypeDirectory(_audioFolderName);
      
      // Generar nombre único
      final extension = path.extension(tempPath).isNotEmpty 
        ? path.extension(tempPath) 
        : '.m4a';
      final fileName = _generateFileName('audio') + extension;
      final finalPath = path.join(audioDir.path, fileName);
      
      // Copiar archivo temporal a ubicación permanente
      final tempFile = File(tempPath);
      final finalFile = await tempFile.copy(finalPath);
      
      print('🎵 Audio guardado: ${finalFile.path}');
      print('📊 Tamaño: ${await finalFile.length()} bytes');
      
      // Eliminar archivo temporal si existe y es diferente
      if (tempPath != finalPath && await tempFile.exists()) {
        await tempFile.delete();
        print('🗑️ Archivo temporal eliminado: $tempPath');
      }
      
      return finalFile.path;
    } catch (e) {
      print('❌ Error guardando audio: $e');
      rethrow;
    }
  }

  /// Guarda un archivo de imagen y retorna la ruta local
  static Future<String> saveImage(String tempPath) async {
    try {
      final imageDir = await _getMediaTypeDirectory(_imageFolderName);
      
      final extension = path.extension(tempPath).isNotEmpty 
        ? path.extension(tempPath) 
        : '.jpg';
      final fileName = _generateFileName('img') + extension;
      final finalPath = path.join(imageDir.path, fileName);
      
      final tempFile = File(tempPath);
      final finalFile = await tempFile.copy(finalPath);
      
      print('📷 Imagen guardada: ${finalFile.path}');
      
      if (tempPath != finalPath && await tempFile.exists()) {
        await tempFile.delete();
      }
      
      return finalFile.path;
    } catch (e) {
      print('❌ Error guardando imagen: $e');
      rethrow;
    }
  }

  /// Guarda un archivo de video y retorna la ruta local
  static Future<String> saveVideo(String tempPath) async {
    try {
      final videoDir = await _getMediaTypeDirectory(_videoFolderName);
      
      final extension = path.extension(tempPath).isNotEmpty 
        ? path.extension(tempPath) 
        : '.mp4';
      final fileName = _generateFileName('vid') + extension;
      final finalPath = path.join(videoDir.path, fileName);
      
      final tempFile = File(tempPath);
      final finalFile = await tempFile.copy(finalPath);
      
      print('🎬 Video guardado: ${finalFile.path}');
      
      if (tempPath != finalPath && await tempFile.exists()) {
        await tempFile.delete();
      }
      
      return finalFile.path;
    } catch (e) {
      print('❌ Error guardando video: $e');
      rethrow;
    }
  }

  /// Verifica si un archivo existe en el storage local
  static Future<bool> fileExists(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      print('❌ Error verificando archivo: $e');
      return false;
    }
  }

  /// Obtiene el tamaño de un archivo en bytes
  static Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      print('❌ Error obteniendo tamaño de archivo: $e');
      return 0;
    }
  }

  /// Elimina un archivo del storage local
  static Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        print('🗑️ Archivo eliminado: $filePath');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error eliminando archivo: $e');
      return false;
    }
  }

  /// Limpia archivos antiguos (opcional para gestión de espacio)
  static Future<void> cleanOldFiles({int maxDays = 30}) async {
    try {
      final mediaDir = await _mediaDirectory;
      final now = DateTime.now();
      
      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          final daysDiff = now.difference(stat.modified).inDays;
          
          if (daysDiff > maxDays) {
            await entity.delete();
            print('🗑️ Archivo antiguo eliminado: ${entity.path}');
          }
        }
      }
    } catch (e) {
      print('❌ Error limpiando archivos antiguos: $e');
    }
  }

  /// Obtiene estadísticas del almacenamiento multimedia
  static Future<Map<String, dynamic>> getStorageStats() async {
    try {
      final mediaDir = await _mediaDirectory;
      int totalFiles = 0;
      int totalSize = 0;
      Map<String, int> typeCount = {
        'audio': 0,
        'images': 0,
        'videos': 0,
      };

      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) {
          totalFiles++;
          totalSize += await entity.length();
          
          final parentDir = path.basename(entity.parent.path);
          if (typeCount.containsKey(parentDir)) {
            typeCount[parentDir] = typeCount[parentDir]! + 1;
          }
        }
      }

      return {
        'totalFiles': totalFiles,
        'totalSizeBytes': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'filesByType': typeCount,
        'storagePath': mediaDir.path,
      };
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return {};
    }
  }

  /// Inicializa el servicio con URLs del historial de audio del servidor
  static void inicializarConHistorial(List<String> audioUrls) {
    // Este método es para compatibilidad con el historial
    // Las URLs del servidor se manejan directamente desde los comentarios
    print('📚 MediaStorageService inicializado con ${audioUrls.length} URLs de historial');
    // Por ahora no necesitamos hacer nada especial, 
    // ya que las URLs del servidor se reproducen directamente
  }
}