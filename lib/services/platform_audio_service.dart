import '../models/comentario.dart';
import 'audio_playlist_service.dart';

/// Adaptador que usa solo AudioPlaylistService (funciona en web y móvil)
class PlatformAudioService {
  
  /// Inicializa el servicio
  static void initialize() {
    AudioPlaylistService.instance.initialize();
  }

  /// Métodos para agregar/quitar listeners
  static void addPlaybackStateListener(Function(int index, bool isPlaying) listener) {
    AudioPlaylistService.instance.addPlaybackStateListener(listener);
  }

  static void removePlaybackStateListener(Function(int index, bool isPlaying) listener) {
    AudioPlaylistService.instance.removePlaybackStateListener(listener);
  }

  static void addProgressListener(Function(int index, Duration position, Duration duration) listener) {
    AudioPlaylistService.instance.addProgressListener(listener);
  }

  static void removeProgressListener(Function(int index, Duration position, Duration duration) listener) {
    AudioPlaylistService.instance.removeProgressListener(listener);
  }

  /// Actualiza la lista de audios
  static void updateAudioList(List<Comentario> audioComments) {
    AudioPlaylistService.instance.updateAudioList(audioComments);
  }

  /// Reproduce un audio específico por índice
  static Future<void> playAudioAtIndex(int index) async {
    await AudioPlaylistService.instance.playAudioAtIndex(index);
  }

  /// Control de reproducción
  static Future<void> pause() async {
    await AudioPlaylistService.instance.pause();
  }

  static Future<void> resume() async {
    await AudioPlaylistService.instance.resume();
  }

  static Future<void> stop() async {
    await AudioPlaylistService.instance.stop();
  }

  /// Getters
  static bool get isPlaying {
    return AudioPlaylistService.instance.isPlaying;
  }

  static int get currentIndex {
    return AudioPlaylistService.instance.currentIndex;
  }

  static Duration get currentPosition {
    return AudioPlaylistService.instance.currentPosition;
  }

  static Duration get totalDuration {
    return AudioPlaylistService.instance.totalDuration;
  }

  /// Verifica si un comentario está siendo reproducido
  static bool isCurrentlyPlaying(Comentario comentario) {
    return AudioPlaylistService.instance.isCurrentlyPlaying(comentario);
  }

  /// Limpieza de recursos
  static void dispose() {
    AudioPlaylistService.instance.dispose();
  }
}