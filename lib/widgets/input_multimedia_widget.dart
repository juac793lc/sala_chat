import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import '../models/contenido_multimedia.dart';

class InputMultimediaWidget extends StatefulWidget {
  final Function(ContenidoMultimedia) onContenidoAgregado;
  final VoidCallback? onMapaTap;

  const InputMultimediaWidget({
    super.key,
    required this.onContenidoAgregado,
    this.onMapaTap,
  });

  @override
  State<InputMultimediaWidget> createState() => _InputMultimediaWidgetState();
}

class _InputMultimediaWidgetState extends State<InputMultimediaWidget> 
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  // Variables para audio
  late AudioRecorder _audioRecorder;
  bool _isRecording = false;
  String? _audioPath;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // Inicializar grabador de audio
    _audioRecorder = AudioRecorder();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _mostrarOpcionesMultimedia() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Compartir contenido',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _OpcionContenido(
                  icono: Icons.camera_alt,
                  titulo: 'Cámara',
                  color: const Color(0xFF2196F3),
                  onTap: () {
                    Navigator.pop(context);
                    // Abrir directamente la galería del dispositivo
                    _abrirGaleriaNativa();
                  },
                ),
                _OpcionContenido(
                  icono: Icons.mic,
                  titulo: 'Audio',
                  color: const Color(0xFF4CAF50),
                  onTap: () {
                    Navigator.pop(context);
                    _toggleAudioRecording();
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }



  // Abrir galería nativa directamente (fotos y videos) - Compatible con PWA
  Future<void> _abrirGaleriaNativa() async {
    try {
      final ImagePicker picker = ImagePicker();
      
      // Abrir galería para cualquier tipo de medio (fotos y videos)
      final XFile? archivo = await picker.pickMedia();

      if (archivo != null) {
        // Determinar si es foto o video basándose en la extensión
        final String extension = archivo.name.toLowerCase();
        final bool esVideo = extension.endsWith('.mp4') || 
                           extension.endsWith('.mov') || 
                           extension.endsWith('.avi') ||
                           extension.endsWith('.mkv') ||
                           extension.endsWith('.webm');

        // Para PWA, usar el nombre del archivo y crear una URL temporal
        String urlArchivo;
        if (kIsWeb) {
          // En web/PWA, usar el path que ya es una URL blob
          urlArchivo = archivo.path;
        } else {
          // En dispositivos nativos, usar la ruta del archivo
          urlArchivo = archivo.path;
        }

        // Crear contenido multimedia real con el archivo seleccionado
        final nuevoContenido = ContenidoMultimedia(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          autorId: '1',
          autorNombre: 'Tú',
          tipo: esVideo ? TipoContenido.video : TipoContenido.imagen,
          url: urlArchivo,
          fechaCreacion: DateTime.now(),
          duracionSegundos: esVideo ? 30 : 0,
        );

        widget.onContenidoAgregado(nuevoContenido);

        // Mostrar mensaje de éxito
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                esVideo ? 'VIDEO seleccionado correctamente' : 'FOTO seleccionada correctamente'
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Manejo de errores
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al acceder a la galería: $e'),
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
  }



  // Iniciar/detener grabación de audio
  Future<void> _toggleAudioRecording() async {
    try {
      if (_isRecording) {
        // Detener grabación
        final path = await _audioRecorder.stop();
        if (path != null) {
          setState(() {
            _isRecording = false;
            _audioPath = path;
          });

          // Crear contenido de audio con archivo real
          final nuevoContenido = ContenidoMultimedia(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            autorId: '1',
            autorNombre: 'Tú',
            tipo: TipoContenido.audio,
            url: path,
            fechaCreacion: DateTime.now(),
            duracionSegundos: 5, // Placeholder - se puede calcular la duración real
          );

          widget.onContenidoAgregado(nuevoContenido);

          // Mostrar mensaje de éxito
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('AUDIO grabado correctamente'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else {
        // Verificar permisos y comenzar grabación
        if (await _audioRecorder.hasPermission()) {
          // Configurar grabación
          const config = RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          );

          // Generar nombre único para el archivo
          final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
          await _audioRecorder.start(config, path: fileName);
          setState(() {
            _isRecording = true;
          });

          // Mostrar mensaje de grabación
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎤 Grabando audio... Toca de nuevo para detener'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          // No hay permisos
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Se necesitan permisos de micrófono'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al grabar audio: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
          // Botón del Mapa (arriba)
          if (widget.onMapaTap != null)
            AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: GestureDetector(
                    onTapDown: (_) => _animationController.forward(),
                    onTapUp: (_) => _animationController.reverse(),
                    onTapCancel: () => _animationController.reverse(),
                    onTap: widget.onMapaTap,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFF9800),
                            Color(0xFFFFB74D),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.map_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                );
              },
            ),
          
          const SizedBox(height: 12),
          
          // Botón del Plus (abajo)
          AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: GestureDetector(
                  onTapDown: (_) => _animationController.forward(),
                  onTapUp: (_) => _animationController.reverse(),
                  onTapCancel: () => _animationController.reverse(),
                  onTap: _mostrarOpcionesMultimedia,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF2196F3),
                          Color(0xFF64B5F6),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

}

class _OpcionContenido extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final Color color;
  final VoidCallback onTap;

  const _OpcionContenido({
    required this.icono,
    required this.titulo,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120, // Ancho fijo para acomodar títulos largos
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: color.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                icono,
                color: color,
                size: 30,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}