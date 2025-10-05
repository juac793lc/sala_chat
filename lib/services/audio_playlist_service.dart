import 'package:audioplayers/audioplayers.dart';
import '../models/comentario.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;

class AudioPlaylistService {
  static final AudioPlaylistService _instance = AudioPlaylistService._internal();
  factory AudioPlaylistService() => _instance;
  AudioPlaylistService._internal();

  static AudioPlaylistService get instance => _instance;

  final AudioPlayer _audioPlayer = AudioPlayer();
  List<Comentario> _audioComments = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  html.AudioElement? _htmlAudio; // solo web

  // Listas de callbacks para notificar a múltiples widgets
  final List<Function(int index, bool isPlaying)> _playbackStateListeners = [];
  final List<Function(int index, Duration position, Duration duration)> _progressListeners = [];

  // Métodos para agregar/quitar listeners
  void addPlaybackStateListener(Function(int index, bool isPlaying) listener) {
    _playbackStateListeners.add(listener);
  }

  void removePlaybackStateListener(Function(int index, bool isPlaying) listener) {
    _playbackStateListeners.remove(listener);
  }

  void addProgressListener(Function(int index, Duration position, Duration duration) listener) {
    _progressListeners.add(listener);
  }

  void removeProgressListener(Function(int index, Duration position, Duration duration) listener) {
    _progressListeners.remove(listener);
  }

  // Notificar a todos los listeners
  void _notifyPlaybackStateChanged() {
    for (final listener in _playbackStateListeners) {
      listener(_currentIndex, _isPlaying);
    }
  }

  void _notifyProgressChanged() {
    for (final listener in _progressListeners) {
      listener(_currentIndex, _currentPosition, _totalDuration);
    }
  }

  bool get isPlaying => _isPlaying;
  int get currentIndex => _currentIndex;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;

  void initialize() {
    _audioPlayer.onDurationChanged.listen((duration) {
      _totalDuration = duration;
      if (_currentIndex >= 0) {
        _notifyProgressChanged();
      }
    });

    _audioPlayer.onPositionChanged.listen((position) {
      _currentPosition = position;
      if (_currentIndex >= 0) {
        _notifyProgressChanged();
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      print('🎵 Audio completado! Índice actual: $_currentIndex de ${_audioComments.length}');
      print('🔄 Ejecutando _playNext()...');
      _playNext();
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      if (_currentIndex >= 0) {
        _notifyPlaybackStateChanged();
      }
    });
  }

  void updateAudioList(List<Comentario> audioComments) {
    _audioComments = audioComments.where((c) => c.tipo == TipoComentario.audio).toList();
    // Reiniciar índice si ya no es válido para evitar estados inconsistentes tras navegar
    if (_currentIndex >= _audioComments.length) {
      _currentIndex = -1;
      _isPlaying = false;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
    }
    print('📋 Lista de audios actualizada: ${_audioComments.length} audios');
    for (int i = 0; i < _audioComments.length; i++) {
      final preview = _audioComments[i].contenido;
      final safeLen = preview.length < 30 ? preview.length : 30;
      final slice = safeLen > 0 ? preview.substring(0, safeLen) : '';
      print('   $i: $slice${preview.length > 30 ? '...' : ''}');
    }
  }

  Future<void> playAudioAtIndex(int index) async {
    try {
      print('🎵 ========== INICIANDO REPRODUCCIÓN ==========');
      print('📊 Estado actual: _isPlaying=$_isPlaying, _currentIndex=$_currentIndex');
      print('📊 Lista tiene ${_audioComments.length} audios');
      print('📊 Índice solicitado: $index');
      
      if (index < 0 || index >= _audioComments.length) {
        print('❌ Índice inválido: $index, lista tiene ${_audioComments.length} audios');
        return;
      }

      print('▶️ Reproduciendo audio $index de ${_audioComments.length}');
      print('🎯 Audio URL: ${_audioComments[index].contenido}');
      print('🔊 Player state antes: ${_audioPlayer.state}');
      
      _currentIndex = index;
      final audio = _audioComments[index];
      // Determinar URL real: usar mediaUrl si existe y contenido está vacío o muy corto
      String effectiveUrl = audio.mediaUrl != null && audio.mediaUrl!.isNotEmpty
          ? audio.mediaUrl!
          : audio.contenido;
      if (effectiveUrl.isEmpty) {
        print('⚠️ URL vacía para audio id=${audio.id}, abortando reproducción');
        return;
      }
      
      print('⏹️ Deteniendo audio actual...');
      await _audioPlayer.stop();
      _htmlAudio?.pause();
      print('✅ Audio detenido');

  final src = effectiveUrl;
      if (kIsWeb) {
        print('🌐 (web) Usando SIEMPRE HTMLAudioElement (forzado)');
        await _playHtmlElement(src, force:true);
      } else {
        await _playNative(src);
      }

      _isPlaying = true;
      _notifyPlaybackStateChanged();
      print('🎵 ========== REPRODUCCIÓN INICIADA ==========');

    } catch (e) {
      print('❌ Error reproduciendo audio index=$index: $e');
      _isPlaying = false;
      _notifyPlaybackStateChanged();
    }
  }

  Future<void> _playNative(String path) async {
    if (path.startsWith('http')) {
      print('🌐 (native) URL: $path');
      await _audioPlayer.play(UrlSource(path));
    } else {
      final file = File(path);
      if (await file.exists()) {
        print('� (native) Archivo local: $path');
        await _audioPlayer.play(DeviceFileSource(path));
      } else {
        print('🔄 (native) Intentando como URL fallback');
        await _audioPlayer.play(UrlSource(path));
      }
    }
  }

  // _playWeb removido: ahora forzamos HTMLAudioElement directamente

  Future<void> _playHtmlElement(String url, {bool force=false}) async {
    _htmlAudio?.pause();
    _htmlAudio = html.AudioElement();
    final audio = _htmlAudio!;
    audio
      ..src = url
      ..preload = 'auto'
      ..controls = false
      ..autoplay = false;
    print('🎧 (html5) Preparando elemento para: $url');

    // Actualizar progreso
    audio.onTimeUpdate.listen((_) {
      _currentPosition = Duration(milliseconds: (audio.currentTime * 1000).round());
      if (audio.duration.isFinite) {
        final dMs = (audio.duration * 1000).round();
        if (dMs >= 0) _totalDuration = Duration(milliseconds: dMs);
      }
      if (_currentIndex >= 0) _notifyProgressChanged();
    });

    Future<void> _waitReady(html.AudioElement el) async {
      final completer = Completer<void>();
      void ready([dynamic _]) { if (!completer.isCompleted) completer.complete(); }
      el.onLoadedMetadata.listen(ready);
      el.onCanPlay.listen(ready);
      el.onCanPlayThrough.listen(ready);
      // Fallback por si los eventos no disparan en blobs muy pequeños
      Future.delayed(const Duration(milliseconds: 800), ready);
      await completer.future;
    }

    try {
      audio.load();
      await _waitReady(audio);
      final playFuture = audio.play();
      await playFuture.catchError((err) => print('⚠️ (html5) play() rechazado: $err'));
      if (audio.paused) {
        await Future.delayed(const Duration(milliseconds: 120));
        try { await audio.play(); } catch (e) { print('⚠️ Segundo intento play() falló: $e'); }
      }
      if (!audio.paused) {
        print('✅ (html5) Reproduciendo');
        _isPlaying = true;
        _notifyPlaybackStateChanged();
        audio.onEnded.first.then((_) => _playNext());
        audio.onError.first.then((_) => print('❌ (html5) error evento'));
        return; // éxito
      }
      throw Exception('No se pudo iniciar reproducción (autoplay / permiso / codec)');
    } catch (e) {
      print('❌ (html5) intento directo falló: $e');
      // Fallback: fetch -> blob -> object URL
      if (url.startsWith('http')) {
        try {
          print('🔄 (fallback) Descargando $url para reproducir como blob');
          final request = await html.HttpRequest.request(url,
              method: 'GET', responseType: 'blob');
          final blob = request.response as html.Blob;
          print('📦 (fallback) Blob recibido: ${blob.size} bytes, type=${blob.type}');
          final type = blob.type.isNotEmpty ? blob.type : 'audio/webm;codecs=opus';
          final fixedBlob = blob.type.isNotEmpty ? blob : html.Blob([blob], type);
            final objUrl = html.Url.createObjectUrl(fixedBlob);
          print('🔗 (fallback) Object URL creado');
          // reintentar con object URL
          _htmlAudio?.pause();
          _htmlAudio = html.AudioElement();
          final a2 = _htmlAudio!;
          a2
            ..src = objUrl
            ..preload = 'auto'
            ..autoplay = false
            ..controls = false;
          await _waitReady(a2);
          try { await a2.play(); } catch (e2) { print('⚠️ (fallback) play() rechazado: $e2'); }
          if (a2.paused) {
            await Future.delayed(const Duration(milliseconds: 120));
            try { await a2.play(); } catch (_) {}
          }
          if (!a2.paused) {
            print('✅ (fallback) Reproduciendo desde blob');
            _isPlaying = true;
            _notifyPlaybackStateChanged();
            a2.onEnded.first.then((_) => _playNext());
            a2.onError.first.then((_) => print('❌ (fallback) error evento'));
            return;
          } else {
            print('❌ (fallback) tampoco se pudo reproducir blob');
            throw e;
          }
        } catch (f) {
          print('❌ Fallback fetch->blob falló: $f');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  Future<void> _playNext() async {
    print('🔄 _playNext(): Índice actual $_currentIndex, Total audios: ${_audioComments.length}');
    
    if (_currentIndex < _audioComments.length - 1) {
      // Hay más audios, reproducir el siguiente
      final nextIndex = _currentIndex + 1;
      print('➡️ Reproduciendo siguiente audio en índice: $nextIndex');
      await playAudioAtIndex(nextIndex);
    } else {
      // No hay más audios, detener reproducción
      print('🏁 Lista de reproducción completada');
      _currentIndex = -1;
      _isPlaying = false;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
      
      _notifyPlaybackStateChanged();
    }
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    _isPlaying = false;
    if (_currentIndex >= 0) {
      _notifyPlaybackStateChanged();
    }
  }

  Future<void> resume() async {
    await _audioPlayer.resume();
    _isPlaying = true;
    if (_currentIndex >= 0) {
      _notifyPlaybackStateChanged();
    }
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    _currentIndex = -1;
    _isPlaying = false;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    
    _notifyPlaybackStateChanged();
  }

  bool isCurrentlyPlaying(Comentario comentario) {
    if (_currentIndex < 0 || _currentIndex >= _audioComments.length) return false;
    return _audioComments[_currentIndex].id == comentario.id && _isPlaying;
  }

  void dispose() {
    _audioPlayer.dispose();
    if (kIsWeb) {
      _htmlAudio?.pause();
      _htmlAudio = null;
    }
  }
}