import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// audio UI removed: we only show image and video previews
import '../models/contenido_multimedia.dart';
import 'dart:html' as html; // ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui;
// no async helpers needed

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
  @override
  void initState() {
    super.initState();
    // No audio initialization in simplified UI
  }

  @override
  void dispose() {
    // No audio resources to dispose here
    super.dispose();
  }

  // Cache for computed BoxFit per image URL to avoid recalculating
  final Map<String, BoxFit> _imageFitCache = {};
  final Set<String> _resolvingFits = {};

  // Audio helpers removed for simplified UI

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
  final desired = (screenHeight * 0.50).clamp(200.0, 700.0);
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
              // Overlay de autor eliminado por request del usuario (se retiró el widget)
            ],
          ),
        );
        
      case TipoContenido.video:
        final screenHeight = MediaQuery.of(context).size.height;
  final desired = (screenHeight * 0.50).clamp(200.0, 700.0);
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
              // Overlay de autor eliminado por request del usuario (se retiró el widget)
            ],
          ),
        );
        
      case TipoContenido.audio:
        // Ocultar audio en esta vista simplificada
        return const SizedBox.shrink();
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
          
          // Botones de comentarios y notas de voz eliminados para interfaz limpia
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
