import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/contenido_multimedia.dart';
import 'dart:html' as html; // ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui;
import 'dart:async';

class ContenidoMultimediaWidget extends StatefulWidget {
  final ContenidoMultimedia contenido;
  final VoidCallback onTextoTap;
  final VoidCallback onAudioTap;

  const ContenidoMultimediaWidget({
    super.key,
    required this.contenido,
    required this.onTextoTap,
    required this.onAudioTap,
  });

  @override
  State<ContenidoMultimediaWidget> createState() => _ContenidoMultimediaWidgetState();
}

class _ContenidoMultimediaWidgetState extends State<ContenidoMultimediaWidget> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    
    // Escuchar cambios en el reproductor
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    // Cancel any image stream listeners? (listeners are removed after receive)
    super.dispose();
  }

  // Cache for computed BoxFit per image URL to avoid recalculating
  final Map<String, BoxFit> _imageFitCache = {};
  final Set<String> _resolvingFits = {};

  // Función para reproducir/pausar audio
  Future<void> _toggleAudioPlayback() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        // Reproducir archivo de audio real
        if (kIsWeb && widget.contenido.url.startsWith('blob:')) {
          await _audioPlayer.play(UrlSource(widget.contenido.url));
        } else if (!kIsWeb) {
          await _audioPlayer.play(DeviceFileSource(widget.contenido.url));
        } else {
          // Fallback para assets
          await _audioPlayer.play(AssetSource('audio/ejemplo.mp3'));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reproducir audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Widget del reproductor de audio
  Widget _buildAudioWidget() {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade100, Colors.blue.shade100],
        ),
      ),
      child: Stack(
        children: [
          // Contenido del reproductor
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Botón play/pause
                    GestureDetector(
                      onTap: _toggleAudioPlayback,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isPlaying ? Colors.red : Colors.green,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Información del audio
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🎧 Audio grabado',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Barra de progreso responsiva
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final filled = _duration.inMilliseconds > 0
                          ? width * (_position.inMilliseconds / _duration.inMilliseconds)
                          : 0.0;
                      return Stack(
                        children: [
                          Container(
                            width: filled,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          
          // Overlay con perfil
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade300, Colors.purple.shade300],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.contenido.autorNombre[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.contenido.autorNombre} · ${_formatearTiempo(widget.contenido.fechaCreacion)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Formatear duración para mostrar
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

  // Construir widget de imagen compatible con PWA y dispositivos nativos
  Widget _buildImageWidget() {
    // Si es una URL del servidor, blob (PWA) o URL HTTP, usar Image.network
    if (widget.contenido.url.startsWith('blob:') || 
        widget.contenido.url.startsWith('http://') ||
        widget.contenido.url.startsWith('https://') ||
        widget.contenido.url.startsWith('/uploads/')) {
      
      // Usar Image.network para URLs remotas, blobs, y rutas del servidor
      // Determine fit: if we already computed fit for this URL use it; otherwise default to contain
      final cachedFit = _imageFitCache[widget.contenido.url] ?? BoxFit.contain;
      // Start async resolve if not cached
      if (!_imageFitCache.containsKey(widget.contenido.url) && !_resolvingFits.contains(widget.contenido.url)) {
        _resolveImageFit(widget.contenido.url, false);
      }

      return InteractiveViewer(
        clipBehavior: Clip.hardEdge,
        panEnabled: true,
        scaleEnabled: true,
        minScale: 1.0,
        maxScale: 4.0,
        child: Image.network(
          widget.contenido.url,
          fit: cachedFit,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            final expected = loadingProgress.expectedTotalBytes;
            final loaded = loadingProgress.cumulativeBytesLoaded;
            final progress = (expected != null && expected > 0) ? loaded / expected : null;
            return Container(
              color: Colors.grey.shade200,
              child: Center(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(value: progress),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue.shade100, Colors.purple.shade100],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.image,
                  size: 60,
                  color: Colors.white70,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Error cargando imagen',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
        ),
      );
    } else if (!kIsWeb) {
      // Dispositivos nativos: usar Image.file solo para paths locales
      final cachedFileFit = _imageFitCache[widget.contenido.url] ?? BoxFit.contain;
      if (!_imageFitCache.containsKey(widget.contenido.url) && !_resolvingFits.contains(widget.contenido.url)) {
        _resolveImageFit(widget.contenido.url, true);
      }

      return InteractiveViewer(
        clipBehavior: Clip.hardEdge,
        panEnabled: true,
        scaleEnabled: true,
        minScale: 1.0,
        maxScale: 4.0,
        child: Image.file(
          File(widget.contenido.url),
          fit: cachedFileFit,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.red.shade100, Colors.orange.shade100],
              ),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 60,
                    color: Colors.white70,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Error al cargar imagen',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        ),
      );
    } else {
      // Placeholder para cuando no hay imagen
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.grey.shade200, Colors.grey.shade300],
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.image,
            size: 80,
            color: Colors.grey,
          ),
        ),
      );
    }
  }

  Widget _buildContenidoPreview() {
    switch (widget.contenido.tipo) {
      case TipoContenido.imagen:
        final screenHeight = MediaQuery.of(context).size.height;
        final desired = (screenHeight * 0.65).clamp(260.0, 700.0);
        return SizedBox(
          height: desired,
          width: double.infinity,
          child: Stack(
            children: [
              // Imagen real - Mostrar archivo del dispositivo si existe
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildImageWidget(),
                ),
              ),
              // Overlay con perfil en la parte superior
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.blue.shade300, Colors.purple.shade300],
                          ),
                        ),
                        child: Center(
                          child: Text(
                            widget.contenido.autorNombre[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.contenido.autorNombre} · ${_formatearTiempo(widget.contenido.fechaCreacion)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            ],
          ),
        );
        
      case TipoContenido.video:
        final screenHeight = MediaQuery.of(context).size.height;
        final desired = (screenHeight * 0.65).clamp(260.0, 700.0);
        return SizedBox(
          height: desired,
          width: double.infinity,
          child: Stack(
            children: [
              // Reproductor de video real
              Container(
                width: double.infinity,
                height: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildVideoPlayer(),
                ),
              ),
              // Overlay con perfil
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.blue.shade300, Colors.purple.shade300],
                          ),
                        ),
                        child: Center(
                          child: Text(
                            widget.contenido.autorNombre[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.contenido.autorNombre} · ${_formatearTiempo(widget.contenido.fechaCreacion)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        
      case TipoContenido.audio:
        return _buildAudioWidget();
    }
  }

  // Resolve natural size of image to pick a better BoxFit (fitWidth when image is wide)
  void _resolveImageFit(String url, bool isFile) {
    try {
      _resolvingFits.add(url);
      ImageProvider provider;
      if (isFile) {
        provider = FileImage(File(url));
      } else {
        provider = NetworkImage(url);
      }
  final stream = provider.resolve(const ImageConfiguration());
      ImageStreamListener? listener;
      listener = ImageStreamListener((info, _) {
        try {
          final img = info.image;
          final w = img.width.toDouble();
          final h = img.height.toDouble();
          final aspect = w / h;
          // If image is wide (aspect ratio > 1.6) prefer filling width
          final fit = (aspect > 1.6) ? BoxFit.fitWidth : BoxFit.contain;
          _imageFitCache[url] = fit;
          if (mounted) setState(() {});
        } catch (e) {
          // ignore
        } finally {
          if (listener != null) stream.removeListener(listener);
          _resolvingFits.remove(url);
        }
      }, onError: (err, stack) {
        if (listener != null) stream.removeListener(listener);
        _resolvingFits.remove(url);
      });
      stream.addListener(listener);
    } catch (e) {
      _resolvingFits.remove(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFB2DFDB), // Verde-azulado suave
            Color(0xFFBBDEFB), // Azul suave
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Contenido multimedia con overlay integrado
          _buildContenidoPreview(),
          
          // Botones de comentarios sin bordes y compactos
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onTextoTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue.withValues(alpha: 0.1),
                            ),
                            child: Icon(
                              Icons.chat_bubble_outline,
                              size: 12,
                              color: Colors.blue.shade600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Comentarios',
                                  style: TextStyle(
                                    color: Colors.grey.shade800,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${widget.contenido.comentariosTexto} respuestas',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: Colors.grey.shade200,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onAudioTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green.withValues(alpha: 0.1),
                            ),
                            child: Icon(
                              Icons.mic_none,
                              size: 12,
                              color: Colors.green.shade600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Notas de voz',
                                  style: TextStyle(
                                    color: Colors.grey.shade800,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${widget.contenido.comentariosAudio} audios',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (kIsWeb) {
      // Para web, crear elemento video HTML5 embebido
      final String videoId = 'video_${widget.contenido.id}_${DateTime.now().millisecondsSinceEpoch}';
      
      try {
        // Registrar el elemento video HTML
        ui.platformViewRegistry.registerViewFactory(videoId, (int viewId) {
          final video = html.VideoElement()
            ..src = widget.contenido.url
            ..controls = true
            ..autoplay = false
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'contain'
            ..style.backgroundColor = '#000';
          
          return video;
        });
        
        return HtmlElementView(viewType: videoId);
      } catch (e) {
        debugPrint('Error creando reproductor de video: $e');
        return Container(
          color: Colors.black,
          child: const Center(
            child: Text(
              'Error al cargar video',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } else {
      // Para dispositivos nativos, mostrar placeholder
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_library,
                size: 60,
                color: Colors.white70,
              ),
              SizedBox(height: 12),
              Text(
                'Video no soportado en esta plataforma',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
  }


}
