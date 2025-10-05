import 'package:flutter/material.dart';
import '../models/comentario.dart';
// Eliminamos carga interna de usuario para evitar "reflejo" visual.
import '../services/platform_audio_service.dart';

class ComentarioWidget extends StatefulWidget {
  final Comentario comentario;
  final List<Comentario>? allAudioComments;
  final String? currentUserId; // Se recibe desde la pantalla para evitar recarga
  final String? currentUserName;

  const ComentarioWidget({
    super.key,
    required this.comentario,
    this.allAudioComments,
    this.currentUserId,
    this.currentUserName,
  });

  @override
  State<ComentarioWidget> createState() => _ComentarioWidgetState();
}

class _ComentarioWidgetState extends State<ComentarioWidget> {
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _setupPlaylistListeners();
  }

  @override
  void didUpdateWidget(covariant ComentarioWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si antes no teníamos user y ahora sí, forzar repaint (alignment correcto)
    if (oldWidget.currentUserId == null && widget.currentUserId != null) {
      setState(() {});
    }
  }

  void _setupPlaylistListeners() {
    // Agregar este widget a los listeners del servicio
    PlatformAudioService.addPlaybackStateListener(_onPlaybackStateChanged);
    PlatformAudioService.addProgressListener(_onProgressChanged);
  }

  void _onPlaybackStateChanged(int index, bool isPlaying) {
    if (mounted) {
      final isThisAudioPlaying = PlatformAudioService.isCurrentlyPlaying(widget.comentario);
      setState(() {
        _isPlaying = isThisAudioPlaying;
        // Si este audio se está reproduciendo, obtener progreso actual
        if (isThisAudioPlaying) {
          _currentPosition = PlatformAudioService.currentPosition;
          _totalDuration = PlatformAudioService.totalDuration;
        } else {
          // Si no se está reproduciendo, resetear progreso
          _currentPosition = Duration.zero;
        }
      });
    }
  }

  void _onProgressChanged(int index, Duration position, Duration duration) {
    if (mounted) {
      final isThisAudioPlaying = PlatformAudioService.isCurrentlyPlaying(widget.comentario);
      if (isThisAudioPlaying) {
        setState(() {
          _currentPosition = position;
          _totalDuration = duration;
        });
      }
    }
  }

  // Eliminada carga interna de usuario.

  Future<void> _playPause() async {
    try {
      if (_isPlaying) {
        // Pausar reproducción actual
        await PlatformAudioService.pause();
      } else {
        // Usar la lista de audios pasada como parámetro
        final audioComments = widget.allAudioComments ?? [];
        final index = audioComments.indexWhere((c) => c.id == widget.comentario.id);
        
        if (index >= 0) {
          PlatformAudioService.updateAudioList(audioComments);
          await PlatformAudioService.playAudioAtIndex(index);
        }
      }
    } catch (e) {
      print('Error al reproducir audio: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al reproducir audio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    // Remover listeners para evitar fugas al salir de la pantalla
    PlatformAudioService.removePlaybackStateListener(_onPlaybackStateChanged);
    PlatformAudioService.removeProgressListener(_onProgressChanged);
    super.dispose();
  }

  Widget _buildAudioPlayer(bool esMiMensaje) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: MediaQuery.of(context).size.width * 0.70,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _isPlaying ? Colors.green.shade50 : Colors.blue.shade50, // Color diferente cuando reproduce
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isPlaying ? Colors.green.shade300 : Colors.blue.shade200, // Borde verde cuando reproduce
          width: _isPlaying ? 2 : 1, // Borde más grueso cuando reproduce
        ),
        boxShadow: [
          BoxShadow(
            color: (_isPlaying ? Colors.green : Colors.black).withOpacity(0.1),
            blurRadius: _isPlaying ? 4 : 2, // Sombra más pronunciada cuando reproduce
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Botón play/pause con animación
          GestureDetector(
            onTap: _playPause,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isPlaying ? 32 : 28, // Más grande cuando reproduce
              height: _isPlaying ? 32 : 28,
              decoration: BoxDecoration(
                color: _isPlaying ? Colors.green.shade600 : Colors.blue.shade600,
                borderRadius: BorderRadius.circular(_isPlaying ? 16 : 14),
                boxShadow: _isPlaying ? [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ] : [],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Animación de pulso cuando reproduce
                  if (_isPlaying)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 1000),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: _isPlaying ? 18 : 16,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Información del audio
          Expanded(
            child: Column(
              children: [
                // Barra de progreso con animación
                Container(
                  height: _isPlaying ? 3 : 2, // Más alta cuando reproduce
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: LinearProgressIndicator(
                    value: _totalDuration.inMilliseconds > 0 
                        ? _currentPosition.inMilliseconds / _totalDuration.inMilliseconds 
                        : 0,
                    backgroundColor: _isPlaying ? Colors.green.shade200 : Colors.blue.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _isPlaying ? Colors.green.shade700 : Colors.blue.shade700
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                
                // Tiempo
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(
                      Icons.audiotrack,
                      size: 10,
                      color: Colors.blue.shade600,
                    ),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color: _isPlaying ? Colors.green.shade700 : Colors.blue.shade700,
                        fontSize: _isPlaying ? 10 : 9, // Texto más grande cuando reproduce
                        fontWeight: _isPlaying ? FontWeight.w600 : FontWeight.w500,
                      ),
                      child: Text(
                        '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration.inMilliseconds > 0 ? _totalDuration : Duration(seconds: widget.comentario.duracionSegundos ?? 0))}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _formatearTiempo(DateTime fecha) {
    final now = DateTime.now();
    final difference = now.difference(fecha);
    
    if (difference.inMinutes < 1) {
      return 'Ahora';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h';
    } else {
      return '${difference.inDays}d';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Verificar si es mi mensaje comparando ID o nombre
  final bool esMiMensaje = (widget.currentUserId != null && widget.comentario.autorId == widget.currentUserId) ||
               (widget.currentUserName != null && widget.comentario.autorNombre == widget.currentUserName) ||
               widget.comentario.autorNombre == 'Tú';
    
    return Padding(
      padding: const EdgeInsets.only(
        left: 0,
        right: 0,
        bottom: 1, // Sin espacios entre comentarios
      ),
      child: widget.comentario.tipo == TipoComentario.audio
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Audio centrado
                Expanded(
                  child: Center(
                    child: _buildAudioPlayer(esMiMensaje),
                  ),
                ),
              ],
            )
          : Row(
              // Mensajes de texto con formato WhatsApp
              mainAxisAlignment: esMiMensaje ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!esMiMensaje) ...[
                  // Avatar para otros usuarios
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey.shade400,
                    ),
                    child: Center(
                      child: Text(
                        widget.comentario.autorNombre.isNotEmpty ? widget.comentario.autorNombre[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Burbuja del mensaje
                Flexible(
                  child: Container( // Mensajes de texto normales
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: esMiMensaje ? Colors.blue : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.comentario.contenido,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.3,
                                color: esMiMensaje ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatearTiempo(widget.comentario.fechaCreacion),
                              style: TextStyle(
                                color: esMiMensaje 
                                    ? Colors.white.withOpacity(0.7) 
                                    : Colors.grey.shade500,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (esMiMensaje) const SizedBox(width: 40), // Espacio para mis mensajes
              ],
            ),
    );
  }

}
// _getAvatarColor removido por no usarse; si se requiere avatar coloreado reintroducir.