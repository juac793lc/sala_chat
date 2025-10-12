import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';
import 'dart:html' as html; // ignore: avoid_web_libraries_in_flutter
import '../models/comentario.dart';
import '../services/auth_service.dart';
import '../services/platform_storage_service.dart';
import '../services/upload_service.dart';
import '../services/web_recorder_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/socket_service.dart';

class InputComentarioWidget extends StatefulWidget {
  final String contenidoId;
  final bool esAudio;
  final Function(Comentario) onComentarioAgregado;

  const InputComentarioWidget({
    super.key,
    required this.contenidoId,
    required this.esAudio,
    required this.onComentarioAgregado,
  });

  @override
  State<InputComentarioWidget> createState() => _InputComentarioWidgetState();
}

class _InputComentarioWidgetState extends State<InputComentarioWidget> {
  final TextEditingController _controller = TextEditingController();
  bool _grabandoAudio = false;
  final AudioRecorder _audioRecorder = AudioRecorder();

  late DateTime _inicioGrabacion;
  String _currentUserId = '1';
  String _currentUserName = 'Usuario';
  // Para manejo de comentario temporal de audio en web
  String? _tempAudioCommentId;
  io.Socket? _socket;
  bool _roomReady = false;
  late final String _roomId;

  @override
  void initState() {
    super.initState();
    _roomId = widget.contenidoId;
    _loadCurrentUser();
    _syncRoomState();
  }

  void _syncRoomState() {
    // Chequear si ya estamos dentro de la sala
    _roomReady = SocketService.instance.isInRoom(_roomId);
    // Escuchar evento joined_room para habilitar envío
    SocketService.instance.on('joined_room', (data) {
      final room = data['roomName'] ?? data['roomId'];
      if (room == _roomId && mounted) {
        setState(() { _roomReady = true; });
      }
    });
  }

  void _loadCurrentUser() async {
    try {
      final result = await AuthService.verifyToken();
      if (result.success && result.user != null) {
        setState(() {
          _currentUserId = result.user!.id;
          _currentUserName = result.user!.username;
        });
      }
    } catch (e) {
      debugPrint('Error cargando usuario en input: $e');
    }
  }

  io.Socket? get _activeSocket {
    try {
      // Recuperar socket desde algún servicio central (supuesto)
      _socket ??= SocketService.instance.socket; // si no existe, ignorar
    } catch (_) {}
    return _socket;
  }

  void _enviarComentario() {
    if (widget.esAudio) {
      _grabarAudio();
    } else {
      _enviarTexto();
    }
  }

  void _enviarTexto() {
    if (_controller.text.trim().isEmpty) return;
    if (!_roomReady) {
      debugPrint('\u23f3 Sala aún no confirmada, reintentando...');
      // Reintento simple: esperar un corto delay y reintentar una sola vez
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_roomReady) {
          _enviarTexto();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sala no lista todavía, intenta de nuevo'), duration: Duration(seconds: 2)),
            );
          }
        }
      });
      return;
    }

    final contenidoTexto = _controller.text.trim();
    _controller.clear();

    // UI optimista: crear comentario local temporal (se reemplazará por el del servidor)
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = Comentario(
      id: tempId,
      contenidoId: widget.contenidoId,
      autorId: _currentUserId,
      autorNombre: _currentUserName,
      tipo: TipoComentario.texto,
      contenido: contenidoTexto,
      fechaCreacion: DateTime.now(),
      ordenSecuencia: DateTime.now().microsecondsSinceEpoch, // base única para estabilidad antes de reconciliar
    );
    widget.onComentarioAgregado(optimistic);

    // ENVIAR AL SERVIDOR - el mensaje aparecerá cuando el servidor lo confirme
    SocketService.instance.sendMessage(
      roomId: widget.contenidoId,
      content: contenidoTexto,
      type: 'text',
    );
    
    debugPrint('\ud83d\udce4 Mensaje enviado al servidor: $contenidoTexto');
  }

  Future<void> _grabarAudio() async {
    if (_grabandoAudio) {
      // Detener grabación
      await _detenerGrabacion();
    } else {
      // Iniciar grabación
      await _iniciarGrabacion();
    }
  }

  Future<void> _iniciarGrabacion() async {
    try {
      debugPrint('\ud83c\udfa4 Iniciando grabación...');

      if (kIsWeb) {
        // Usar grabador nativo web
        final success = await WebRecorderService.startRecording();
        if (!success) {
          throw Exception('No se pudo iniciar la grabación web');
        }
      } else {
        // Usar record package para móvil
        if (!await _audioRecorder.hasPermission()) {
          debugPrint('\u274c Sin permisos de micrófono');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('\u274c Permiso de micrófono denegado'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        const config = RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          bitRate: 128000,
        );

        final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _audioRecorder.start(config, path: fileName);
      }

      setState(() {
        _grabandoAudio = true;
        _inicioGrabacion = DateTime.now();
      });

      debugPrint('\ud83d\udfe2 Grabación iniciada correctamente');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('\ud83c\udfa4 Grabando... Toca STOP para enviar'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

    } catch (e) {
      debugPrint('\u274c Error al iniciar grabación: $e');
      setState(() {
        _grabandoAudio = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('\u274c Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _detenerGrabacion() async {
    try {
      debugPrint('\ud83d\udd34 Deteniendo grabación...');
      
      final duracion = DateTime.now().difference(_inicioGrabacion);
      
      setState(() {
        _grabandoAudio = false;
      });

      dynamic audioData;
      String? fileId;
      
      if (kIsWeb) {
        // Usar grabador nativo web - devuelve Blob
        audioData = await WebRecorderService.stopRecording();
        if (audioData != null) {
          // Guardar el Blob directamente
          fileId = 'web_audio_${DateTime.now().millisecondsSinceEpoch}';
          // Para web, necesitamos manejar el Blob de manera diferente
          // Por ahora, usamos un placeholder para el fileId
        }
      } else {
        // Usar record package para móvil - devuelve String path
        final tempPath = await _audioRecorder.stop();
        if (tempPath != null) {
          fileId = await PlatformStorageService.saveAudio(tempPath);
        }
      }

      debugPrint('\u23f9\ufe0f Grabación detenida. Duración: ${duracion.inSeconds}s');

      if (audioData != null || fileId != null) {
        // Mostrar indicador de procesamiento
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 16),
                  Text('Procesando audio...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ));
        }        try {
          String? finalUrl;

          if (kIsWeb && audioData != null) {
            // Reproducir inmediatamente el blob local (efecto instantáneo)
            final localObjectUrl = html.Url.createObjectUrl(audioData);
            // tempPlaybackUrl ya no se usa, reproducimos directo via blob
            debugPrint('\ud83c\udfa7 Reproduciendo local antes de upload: $localObjectUrl');
            // Insertar comentario temporal (estado pendiente) usando URL blob local
            _tempAudioCommentId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
            final comentarioTemp = Comentario(
              id: _tempAudioCommentId!,
              contenidoId: widget.contenidoId,
              autorId: _currentUserId,
              autorNombre: _currentUserName,
              tipo: TipoComentario.audio,
              contenido: localObjectUrl, // legado para reproducción inmediata
              mediaUrl: localObjectUrl,
              fechaCreacion: DateTime.now(),
              duracionSegundos: duracion.inSeconds > 0 ? duracion.inSeconds : 1,
            );
            widget.onComentarioAgregado(comentarioTemp);

            // Subir en segundo plano
            try {
              final uploadResult = await UploadService.uploadAudioBlob(
                audioData,
                roomId: widget.contenidoId,
                userId: _currentUserId,
                durationSeconds: duracion.inSeconds > 0 ? duracion.inSeconds : 1,
              );
              finalUrl = uploadResult.url;
              final mediaId = uploadResult.mediaId;
              debugPrint('\u2601\ufe0f (async) Reemplazando blob local por URL servidor (mediaId=$mediaId)');
              if (_tempAudioCommentId != null && mediaId != null) {
                final comentarioFinal = Comentario(
                  id: _tempAudioCommentId!,
                  contenidoId: widget.contenidoId,
                  autorId: _currentUserId,
                  autorNombre: _currentUserName,
                  tipo: TipoComentario.audio,
                  contenido: finalUrl, // mantener por compatibilidad
                  mediaId: mediaId,
                  mediaUrl: finalUrl,
                  fechaCreacion: DateTime.now(),
                  duracionSegundos: duracion.inSeconds > 0 ? duracion.inSeconds : 1,
                );
                widget.onComentarioAgregado(comentarioFinal);
                // Emitir mensaje persistente vía socket (si disponible)
                _activeSocket?.emit('send_message', {
                  'content': '',
                  'roomId': widget.contenidoId,
                  'mediaId': mediaId,
                  'type': 'audio',
                });
              }
            } catch (e) {
              debugPrint('\u274c Upload async falló: $e');
            }
          } else if (fileId != null) {
            final uploadResult = await UploadService.uploadAudio(
              fileId,
              roomId: widget.contenidoId,
              userId: _currentUserId,
              durationSeconds: duracion.inSeconds > 0 ? duracion.inSeconds : 1,
            );
            finalUrl = uploadResult.url;
            final mediaId = uploadResult.mediaId;
            // Crear comentario final (no hubo temporal en móvil)
            final comentarioFinal = Comentario(
              id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
              contenidoId: widget.contenidoId,
              autorId: _currentUserId,
              autorNombre: _currentUserName,
              tipo: TipoComentario.audio,
              contenido: finalUrl,
              mediaId: mediaId,
              mediaUrl: finalUrl,
              fechaCreacion: DateTime.now(),
              duracionSegundos: duracion.inSeconds > 0 ? duracion.inSeconds : 1,
            );
            widget.onComentarioAgregado(comentarioFinal);
            _activeSocket?.emit('send_message', {
              'content': '',
              'roomId': widget.contenidoId,
              'mediaId': mediaId,
              'type': 'audio',
            });
          }

          // Ya no agregamos un segundo comentario en web para evitar duplicados

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('\u2705 Audio enviado (${duracion.inSeconds}s)'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (uploadError) {
          debugPrint('\u274c Error procesando audio: $uploadError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('\u274c Error enviando audio: $uploadError'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        debugPrint('\u274c No se obtuvo audio');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('\u274c Error: No se pudo obtener el audio'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('\u274c Error al detener grabación: $e');
      setState(() {
        _grabandoAudio = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('\u274c Error al finalizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

      @override
      Widget build(BuildContext context) {
        // Mostrar la UI correspondiente según si la sala es de audio o texto.
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: widget.esAudio ? _buildInputAudio() : _buildInputTexto(),
          ),
        );
      }

  Widget _buildInputAudio() {
    return SizedBox(
      height: 60,
      child: Stack(
        children: [
          // Contenedor con forma de ola (fondo)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 35,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.shade50,
                      Colors.blue.shade100,
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.elliptical(60, 20),
                    topRight: Radius.elliptical(60, 20),
                    bottomLeft: Radius.circular(15),
                    bottomRight: Radius.circular(15),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Botón de audio que sobresale como una ola
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _enviarComentario,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _grabandoAudio ? Colors.red : Colors.green,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_grabandoAudio ? Colors.red : Colors.green).withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _grabandoAudio 
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          // Animación de pulso para indicar grabación
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 800),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          const Icon(
                            Icons.stop,
                            color: Colors.white,
                            size: 28,
                          ),
                        ],
                      )
                    : const Icon(
                        Icons.mic,
                        color: Colors.white,
                        size: 28,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Método mínimo para mantener compatibilidad con llamadas existentes.
  // Como la UI ahora elimina la entrada de texto, devolvemos un widget vacío.
  Widget _buildInputTexto() {
    return const SizedBox.shrink();
  }
}
