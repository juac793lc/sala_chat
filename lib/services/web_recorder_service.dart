import 'dart:html' as html;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Servicio de grabación nativo para Flutter Web usando MediaRecorder API
class WebRecorderService {
  static html.MediaRecorder? _mediaRecorder;
  static html.MediaStream? _stream;
  static List<html.Blob> _audioChunks = [];
  static bool _isRecording = false;
  
  /// Inicia la grabación usando MediaRecorder nativo
  static Future<bool> startRecording() async {
    if (!kIsWeb) {
      throw UnsupportedError('WebRecorderService solo funciona en web');
    }
    
    try {
      print('🎤 Iniciando grabación nativa web...');
      
      // Obtener stream de audio
      _stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'sampleRate': 44100,
        }
      });
      
      // FORZAR WebM porque es lo ÚNICO que funciona en MediaRecorder
      // El navegador miente sobre soporte de WAV/MP4
      final options = {
        'mimeType': 'audio/webm;codecs=opus',
        'audioBitsPerSecond': 128000,
      };
      
      print('🔊 FORCED WebM format (MediaRecorder limitation)');
      
      print('🔊 Formato seleccionado: ${options['mimeType']}');
      
      _mediaRecorder = html.MediaRecorder(_stream!, options);
      _audioChunks.clear();
      
      // Configurar eventos
      _mediaRecorder!.addEventListener('dataavailable', (event) {
        final blobEvent = event as html.BlobEvent;
        if (blobEvent.data != null && blobEvent.data!.size > 0) {
          _audioChunks.add(blobEvent.data!);
          print('📊 Chunk recibido: ${blobEvent.data!.size} bytes');
        }
      });
      
      _mediaRecorder!.addEventListener('start', (_) {
        print('🟢 Grabación nativa iniciada');
        _isRecording = true;
      });
      
      _mediaRecorder!.addEventListener('stop', (_) {
        print('⏹️ Grabación nativa detenida');
        _isRecording = false;
      });
      
      _mediaRecorder!.addEventListener('error', (error) {
        print('❌ Error en MediaRecorder: $error');
        _isRecording = false;
      });
      
      // Iniciar grabación
      _mediaRecorder!.start();
      
      return true;
      
    } catch (e) {
      print('❌ Error iniciando grabación nativa: $e');
      _isRecording = false;
      return false;
    }
  }
  
  /// Detiene la grabación y retorna el blob de audio
  static Future<html.Blob?> stopRecording() async {
    if (!kIsWeb || _mediaRecorder == null) {
      return null;
    }
    
    try {
      print('🔴 Deteniendo grabación nativa...');
      
      // Crear un completer para esperar el evento stop
      final completer = Completer<html.Blob?>();
      
      _mediaRecorder!.addEventListener('stop', (_) {
        try {
          if (_audioChunks.isNotEmpty) {
            // Crear blob final con todos los chunks
            final finalBlob = html.Blob(_audioChunks, _mediaRecorder!.mimeType);
            print('✅ Blob final creado: ${finalBlob.size} bytes, tipo: ${finalBlob.type}');
            completer.complete(finalBlob);
          } else {
            print('❌ No hay chunks de audio');
            completer.complete(null);
          }
        } catch (e) {
          print('❌ Error creando blob final: $e');
          completer.complete(null);
        }
      });
      
      // Detener grabación
      _mediaRecorder!.stop();
      
      // Limpiar stream
      if (_stream != null) {
        for (final track in _stream!.getTracks()) {
          track.stop();
        }
        _stream = null;
      }
      
      _isRecording = false;
      
      // Esperar resultado
      return await completer.future;
      
    } catch (e) {
      print('❌ Error deteniendo grabación nativa: $e');
      return null;
    }
  }
  
  /// Verifica si está grabando
  static bool get isRecording => _isRecording;
  
  /// Limpia recursos
  static void dispose() {
    if (_stream != null) {
      for (final track in _stream!.getTracks()) {
        track.stop();
      }
      _stream = null;
    }
    _mediaRecorder = null;
    _audioChunks.clear();
    _isRecording = false;
  }
}