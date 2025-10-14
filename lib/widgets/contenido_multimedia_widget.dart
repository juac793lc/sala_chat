// dart:io removed to keep web compatibility
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/endpoints.dart';
import '../models/contenido_multimedia.dart';
import '../services/auth_service.dart';
import '../services/upload_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:html' as html; // ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui; // ignore: avoid_web_libraries_in_flutter

class ContenidoMultimediaWidget extends StatefulWidget {
  final ContenidoMultimedia contenido;
  final VoidCallback onTextoTap;
  final VoidCallback onAudioTap;
  final void Function(String id)? onDelete;

  const ContenidoMultimediaWidget({
    super.key,
    required this.contenido,
    required this.onTextoTap,
    required this.onAudioTap,
    this.onDelete,
  });

  @override
  State<ContenidoMultimediaWidget> createState() => _ContenidoMultimediaWidgetState();
}

class _ContenidoMultimediaWidgetState extends State<ContenidoMultimediaWidget> {
  @override
  void initState() {
    super.initState();
  }

  Future<bool> _canCurrentUserDelete() async {
    try {
      final user = AuthService.getCachedUser();
      if (user != null && user.isAdmin) return true;
      if (user != null && widget.contenido.autorId.isNotEmpty && user.id == widget.contenido.autorId) return true;
      final sp = await SharedPreferences.getInstance();
      final pin = sp.getString('admin_pin');
      if (pin != null && pin.isNotEmpty) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar archivo'),
        content: const Text('¿Seguro que deseas eliminar este archivo?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final uri = Uri.parse(widget.contenido.url);
      final segments = uri.pathSegments;
      final uploadsIndex = segments.indexOf('uploads');
      if (uploadsIndex < 0 || uploadsIndex + 2 > segments.length - 1) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL inválida')));
        return;
      }
      final type = segments[uploadsIndex + 1];
      final filename = segments[uploadsIndex + 2];

      final okDelete = await UploadService.deleteMediaByTypeFilename(type, filename);
      if (okDelete) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Archivo eliminado'), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se eliminó en servidor'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red));
    } finally {
      if (widget.onDelete != null) widget.onDelete!(widget.contenido.id);
    }
  }

  void _openFullScreenImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: LayoutBuilder(builder: (context, constraints) {
          final maxW = MediaQuery.of(context).size.width * 0.95;
          final maxH = MediaQuery.of(context).size.height * 0.9;
          final boxW = constraints.maxWidth.clamp(200.0, maxW);
          final boxH = constraints.maxHeight.clamp(200.0, maxH);
          return SizedBox(
            width: boxW,
            height: boxH,
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Container(
                color: Colors.black,
                child: Center(child: Image.network(url, fit: BoxFit.contain)),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildContenidoPreview() {
    final screenHeight = MediaQuery.of(context).size.height;
    final desired = (screenHeight * 0.50).clamp(200.0, 700.0);

    if (widget.contenido.tipo == TipoContenido.imagen) {
      return SizedBox(
        height: desired,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => _openFullScreenImage(widget.contenido.url),
                  child: Image.network(
                    widget.contenido.url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      final expected = loadingProgress.expectedTotalBytes;
                      final loaded = loadingProgress.cumulativeBytesLoaded;
                      final progress = (expected != null && expected > 0) ? loaded / expected : null;
                      return Container(
                        color: Colors.grey.shade200,
                        child: Center(child: SizedBox(width: 48, height: 48, child: CircularProgressIndicator(value: progress))),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade300,
                        child: const Center(child: Icon(Icons.broken_image, size: 48, color: Colors.white70)),
                      );
                    },
                  ),
                ),
              ),
              // delete overlay
              Positioned(
                top: 8,
                right: 8,
                child: Endpoints.superUserBuild
                    ? _deleteButton()
                    : FutureBuilder<bool>(future: _canCurrentUserDelete(), builder: (c, s) {
                        if (s.data == true) return _deleteButton();
                        return const SizedBox.shrink();
                      }),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.contenido.tipo == TipoContenido.video) {
      return SizedBox(
        height: desired,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned.fill(child: _buildVideoPlayer()),
              Positioned(
                top: 8,
                right: 8,
                child: Endpoints.superUserBuild
                    ? _deleteButton()
                    : FutureBuilder<bool>(future: _canCurrentUserDelete(), builder: (c, s) {
                        if (s.data == true) return _deleteButton();
                        return const SizedBox.shrink();
                      }),
              ),
            ],
          ),
        ),
      );
    }

    // audio or unknown
    return const SizedBox.shrink();
  }

  Widget _deleteButton() {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(
        icon: const Icon(Icons.delete, color: Colors.white),
        onPressed: () => _confirmAndDelete(context),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (kIsWeb) {
      final String videoId = 'video_${widget.contenido.id}_${DateTime.now().millisecondsSinceEpoch}';
      try {
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
        return Container(color: Colors.black, child: const Center(child: Text('Error al cargar video', style: TextStyle(color: Colors.white))));
      }
    }

    return Container(color: Colors.black, child: const Center(child: Icon(Icons.videocam, color: Colors.white70, size: 48)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade700,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildContenidoPreview(),
          // espacio inferior para separar items
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
