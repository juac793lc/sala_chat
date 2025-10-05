import 'dart:html' as html;
import '../models/comentario.dart';

/// Servicio de reproducción de audio optimizado para Flutter Web
class WebAudioService {
  static html.AudioElement? _currentAudio;
  static List<Comentario> _audioComments = [];
  static int _currentIndex = -1;
  static bool _isPlaying = false;

  // Listas de callbacks para notificar a múltiples widgets
  static final List<Function(int index, bool isPlaying)> _playbackStateListeners = [];
  static final List<Function(int index, Duration position, Duration duration)> _progressListeners = [];

  /// Métodos para agregar/quitar listeners (igual que AudioPlaylistService)
  static void addPlaybackStateListener(Function(int index, bool isPlaying) listener) {
    _playbackStateListeners.add(listener);
  }

  static void removePlaybackStateListener(Function(int index, bool isPlaying) listener) {
    _playbackStateListeners.remove(listener);
  }

  static void addProgressListener(Function(int index, Duration position, Duration duration) listener) {
    _progressListeners.add(listener);
  }

  static void removeProgressListener(Function(int index, Duration position, Duration duration) listener) {
    _progressListeners.remove(listener);
  }

  /// Notificar a todos los listeners
  static void _notifyPlaybackStateChanged() {
    for (final listener in _playbackStateListeners) {
      listener(_currentIndex, _isPlaying);
    }
  }

  static void _notifyProgressChanged(Duration position, Duration duration) {
    for (final listener in _progressListeners) {
      listener(_currentIndex, position, duration);
    }
  }

  /// Inicializa el servicio (equivalente a initialize())
  static void initialize() {
    print('🌐 WebAudioService inicializado para Flutter Web');
  }

  /// Actualiza la lista de audios
  static void updateAudioList(List<Comentario> audioComments) {
    _audioComments = audioComments.where((c) => c.tipo == TipoComentario.audio).toList();
    print('📋 Lista de audios actualizada: ${_audioComments.length} audios');
    for (int i = 0; i < _audioComments.length; i++) {
      print('   $i: ${_audioComments[i].contenido.substring(0, 30)}...');
    }
  }

  /// Reproduce un audio específico por índice
  static Future<void> playAudioAtIndex(int index) async {
    try {
      if (index < 0 || index >= _audioComments.length) {
        print('❌ Índice inválido: $index, lista tiene ${_audioComments.length} audios');
        return;
      }

      print('▶️ Reproduciendo audio $index de ${_audioComments.length}');
      print('🎯 Audio URL: ${_audioComments[index].contenido}');

      // Detener audio actual si existe
      if (_currentAudio != null) {
        _currentAudio!.pause();
        _currentAudio = null;
      }

      _currentIndex = index;
      final audio = _audioComments[index];

      // Crear nuevo elemento de audio HTML5
      _currentAudio = html.AudioElement();
      _currentAudio!.src = audio.contenido;
      _currentAudio!.crossOrigin = 'anonymous'; // Para CORS
      _currentAudio!.preload = 'metadata'; // Cargar metadatos primero
      
      print('🌐 Reproduciendo con HTML5 Audio: ${audio.contenido}');
      print('🔍 Verificando si el navegador puede reproducir WAV...');
      
      // Verificar soporte de formato
      final canPlayWav = _currentAudio!.canPlayType('audio/wav');
      final canPlayMp3 = _currentAudio!.canPlayType('audio/mpeg');
      print('📋 Soporte WAV: $canPlayWav, MP3: $canPlayMp3');

      // Configurar event listeners
      _currentAudio!.onLoadedMetadata.listen((_) {
        final durationValue = _currentAudio!.duration;
        if (!durationValue.isNaN && durationValue.isFinite && durationValue > 0) {
          final duration = Duration(seconds: durationValue.toInt());
          print('📊 Duración cargada: ${duration.inSeconds}s');
          _notifyProgressChanged(Duration.zero, duration);
        } else {
          print('⚠️ Duración no disponible o inválida: $durationValue');
        }
      });

      _currentAudio!.onTimeUpdate.listen((_) {
        final currentTimeValue = _currentAudio!.currentTime;
        final durationValue = _currentAudio!.duration;
        
        if (!currentTimeValue.isNaN && !durationValue.isNaN && 
            currentTimeValue.isFinite && durationValue.isFinite && durationValue > 0) {
          final position = Duration(seconds: currentTimeValue.toInt());
          final duration = Duration(seconds: durationValue.toInt());
          _notifyProgressChanged(position, duration);
        }
      });

      _currentAudio!.onPlay.listen((_) {
        print('🎵 Audio iniciado');
        _isPlaying = true;
        _notifyPlaybackStateChanged();
      });

      _currentAudio!.onPause.listen((_) {
        print('⏸️ Audio pausado');
        _isPlaying = false;
        _notifyPlaybackStateChanged();
      });

      _currentAudio!.onEnded.listen((_) {
        print('🎵 Audio completado! Índice actual: $_currentIndex de ${_audioComments.length}');
        print('🔄 Ejecutando _playNext()...');
        _isPlaying = false;
        _playNext();
      });

      _currentAudio!.onError.listen((event) {
        print('❌ Error de HTML5 Audio: ${event.toString()}');
        print('🔍 Error details: ${_currentAudio!.error?.code} - ${_currentAudio!.error?.message}');
        print('🔍 Network state: ${_currentAudio!.networkState}');
        print('🔍 Ready state: ${_currentAudio!.readyState}');
        _isPlaying = false;
        _notifyPlaybackStateChanged();
      });

      // Iniciar reproducción
      await _currentAudio!.play();
      
    } catch (e) {
      print('❌ Error reproduciendo audio: $e');
      _isPlaying = false;
      _notifyPlaybackStateChanged();
    }
  }

  /// Reproduce el siguiente audio en la lista automáticamente
  static void _playNext() {
    print('🔄 _playNext llamado. Índice actual: $_currentIndex');
    print('📋 Total de audios: ${_audioComments.length}');
    
    if (_currentIndex >= 0 && _currentIndex < _audioComments.length - 1) {
      final nextIndex = _currentIndex + 1;
      print('⏭️ Reproduciendo siguiente audio: $nextIndex');
      playAudioAtIndex(nextIndex);
    } else {
      print('⏹️ No hay más audios para reproducir');
      _currentIndex = -1;
      _isPlaying = false;
      _notifyPlaybackStateChanged();
    }
  }

  /// Control de reproducción
  static Future<void> pause() async {
    if (_currentAudio != null && !_currentAudio!.paused) {
      _currentAudio!.pause();
    }
  }

  static Future<void> resume() async {
    if (_currentAudio != null && _currentAudio!.paused) {
      await _currentAudio!.play();
    }
  }

  static Future<void> stop() async {
    if (_currentAudio != null) {
      _currentAudio!.pause();
      _currentAudio!.currentTime = 0;
      _currentAudio = null;
    }
    _isPlaying = false;
    _currentIndex = -1;
    _notifyPlaybackStateChanged();
  }

  /// Getters para compatibilidad con AudioPlaylistService
  static bool get isPlaying => _isPlaying;

  static int get currentIndex => _currentIndex;

  static Duration get currentPosition {
    if (_currentAudio != null) {
      final currentTimeValue = _currentAudio!.currentTime;
      if (!currentTimeValue.isNaN && currentTimeValue.isFinite && currentTimeValue >= 0) {
        return Duration(seconds: currentTimeValue.toInt());
      }
    }
    return Duration.zero;
  }

  static Duration get totalDuration {
    if (_currentAudio != null) {
      final durationValue = _currentAudio!.duration;
      if (!durationValue.isNaN && durationValue.isFinite && durationValue > 0) {
        return Duration(seconds: durationValue.toInt());
      }
    }
    return Duration.zero;
  }

  /// Verifica si un comentario específico está siendo reproducido
  static bool isCurrentlyPlaying(Comentario comentario) {
    if (!_isPlaying || _currentIndex < 0 || _currentIndex >= _audioComments.length) {
      return false;
    }
    return _audioComments[_currentIndex].id == comentario.id;
  }

  /// Limpieza de recursos
  static void dispose() {
    if (_currentAudio != null) {
      _currentAudio!.pause();
      _currentAudio = null;
    }
    _playbackStateListeners.clear();
    _progressListeners.clear();
    _audioComments.clear();
    _currentIndex = -1;
    _isPlaying = false;
  }
}