import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/contenido_multimedia.dart';
import '../services/upload_service.dart';
import '../services/auth_service.dart';

class InputMultimediaWidget extends StatefulWidget {
  final Function(ContenidoMultimedia) onContenidoAgregado;
  final VoidCallback? onMapaTap;
  final String roomId;

  const InputMultimediaWidget({
    super.key,
    required this.onContenidoAgregado,
    required this.roomId,
    this.onMapaTap,
  });

  @override
  State<InputMultimediaWidget> createState() => _InputMultimediaWidgetState();
}

class _InputMultimediaWidgetState extends State<InputMultimediaWidget>
    with TickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 140),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1, end: 0.92).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _abrirGaleriaDirecta() async {
    try {
      // Mostrar indicador de carga
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccionando archivo...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final picker = ImagePicker();
      final XFile? archivo = await picker.pickMedia();
      if (archivo == null) return;

      // Mostrar indicador de subida
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subiendo archivo...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final nombre = archivo.name.toLowerCase();
      final esVideo = nombre.endsWith('.mp4') ||
          nombre.endsWith('.mov') ||
          nombre.endsWith('.avi') ||
          nombre.endsWith('.mkv') ||
          nombre.endsWith('.webm');

      // Obtener datos del usuario
      final user = AuthService.getCachedUser();
      final userId = user?.id ?? '1';
      final userNombre = user?.username ?? 'Usuario';

      // Subir archivo al backend (manejar diferencias entre web y móvil)
      late UploadResult uploadResult;
      
      if (kIsWeb) {
        // En web, necesitamos usar los bytes directamente
        final bytes = await archivo.readAsBytes();
        final fileName = archivo.name;
        
        // Para web, usamos una estrategia diferente - enviamos los bytes directamente
        uploadResult = await _uploadBytesWeb(
          bytes,
          fileName,
          esVideo ? 'video' : 'image',
          widget.roomId,
          userId,
          userNombre,
        );
      } else {
        // En móvil, usamos el path normalmente
        uploadResult = await UploadService.uploadFile(
          archivo.path,
          esVideo ? 'video' : 'image',
          roomId: widget.roomId,
          userId: userId,
          userNombre: userNombre,
        );
      }

      // Crear contenido multimedia con datos del servidor
      final contenido = ContenidoMultimedia(
        id: uploadResult.mediaId ?? uploadResult.fileId,
        autorId: userId,
        autorNombre: userNombre,
        tipo: esVideo ? TipoContenido.video : TipoContenido.imagen,
        url: uploadResult.url,
        fechaCreacion: uploadResult.uploadedAt,
        duracionSegundos: 0,
      );

      // Notificar a la pantalla principal (que se encargará de la emisión por socket)
      widget.onContenidoAgregado(contenido);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(esVideo
              ? 'Video subido correctamente'
              : 'Imagen subida correctamente'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al subir archivo: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Widget _buildBoton({
    required VoidCallback onTap,
    required List<Color> colores,
    required IconData icono,
  }) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (_, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: GestureDetector(
          onTapDown: (_) => _animationController.forward(),
          onTapUp: (_) => _animationController.reverse(),
            onTapCancel: () => _animationController.reverse(),
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colores,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: colores.last.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icono, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }

  Future<UploadResult> _uploadBytesWeb(
    List<int> bytes,
    String fileName,
    String mediaType,
    String roomId,
    String userId,
    String userNombre,
  ) async {
    try {
      // Usar http directamente para enviar multipart
      final uri = Uri.parse('http://localhost:3000/api/media/upload');
      final request = http.MultipartRequest('POST', uri);
      
      // Headers básicos (sin Authorization por ahora)
      request.headers.addAll({
        'Accept': 'application/json',
      });

      // Campos del formulario
      request.fields.addAll({
        'roomId': roomId,
        'userId': userId,
        'userNombre': userNombre,
        'mediaType': mediaType,
        'originalName': fileName,
      });

      // Archivo como bytes
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );

      // Enviar request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(responseBody);
        return UploadResult.fromJson(data);
      } else {
        throw Exception('Error HTTP ${response.statusCode}: $responseBody');
      }
    } catch (e) {
      throw Exception('Error subiendo archivo en web: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      right: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onMapaTap != null) ...[
            _buildBoton(
              onTap: widget.onMapaTap!,
              colores: const [Color(0xFF2196F3), Color(0xFF64B5F6)],
              icono: Icons.map_rounded,
            ),
            const SizedBox(height: 12),
          ],
          _buildBoton(
            onTap: _abrirGaleriaDirecta,
            colores: const [Color(0xFF4CAF50), Color(0xFF81C784)],
            icono: Icons.add,
          ),
        ],
      ),
    );
  }
}