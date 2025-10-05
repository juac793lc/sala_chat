import 'package:flutter/material.dart';
import '../models/contenido_multimedia.dart';
import '../models/comentario.dart';
import '../widgets/comentario_widget.dart';
import '../widgets/input_comentario_widget.dart';
import '../services/history_service.dart';
import '../services/media_storage_service.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';

class SalaComentariosScreen extends StatefulWidget {
  final ContenidoMultimedia contenido;
  final bool esAudio;

  const SalaComentariosScreen({
    super.key,
    required this.contenido,
    required this.esAudio,
  });

  @override
  State<SalaComentariosScreen> createState() => _SalaComentariosScreenState();
}

class _SalaComentariosScreenState extends State<SalaComentariosScreen> {
  List<Comentario> comentarios = [];
  final ScrollController _scrollController = ScrollController();
  String? _currentUserId;
  String? _currentUserName;
  Function? _messageListener;
  bool _listenersConfigurados = false;
  int _maxOrdenSecuencia = 0; // seguimiento global para asignar secuencias nuevas
  bool _historialCargado = false; // indica que ya se cargó el historial inicial
  DateTime? _ultimaFecha; // última fecha usada (para monotonicidad)

  // (comparador antiguo eliminado - ahora usamos inserción incremental)

  // Inserta manteniendo orden cronológico creciente sin reordenar toda la lista.
  void _insertarOrdenado(Comentario c) {
    if (comentarios.isEmpty) {
      comentarios.add(c);
      _ultimaFecha = c.fechaCreacion;
      return;
    }
    if (_historialCargado) {
      // Fuerza monotonicidad: nunca insertar en medio tras historial inicial
      final base = _ultimaFecha ?? comentarios.last.fechaCreacion;
      DateTime nuevaFecha = c.fechaCreacion;
      if (nuevaFecha.isBefore(base)) {
        nuevaFecha = base.add(const Duration(milliseconds: 1));
        c = c.copyWith(fechaCreacion: nuevaFecha);
      }
      comentarios.add(c);
      _ultimaFecha = nuevaFecha;
      return;
    }
    // Antes de marcar historial cargado todavía podemos insertar ordenado por fecha
    for (int i = 0; i < comentarios.length; i++) {
      if (c.fechaCreacion.isBefore(comentarios[i].fechaCreacion)) {
        comentarios.insert(i, c);
        return;
      }
    }
    comentarios.add(c);
    _ultimaFecha = c.fechaCreacion;
  }

  @override
  void initState() {
    super.initState();
    _initFlow();
  }

  Future<void> _initFlow() async {
    // Intentar cache inmediato
    final cached = AuthService.getCachedUser();
    if (cached != null) {
      _currentUserId = cached.id;
      _currentUserName = cached.username;
      print('👤 Usuario desde cache: ${cached.username} (${cached.id})');
    } else {
      _obtenerUsuarioActual();
    }
    
    // Asegurar conexión socket antes de listeners/join
    if (!SocketService.instance.isConnected) {
      await SocketService.instance.connect();
      // Esperar un momento para que la conexión se estabilice
      await Future.delayed(const Duration(milliseconds: 300));
    }
    
    if (mounted) {
      _cargarComentarios();
      _configurarSocketListeners();
      _unirseASala();
      
      // Verificación adicional tras setup inicial
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          SocketService.instance.ensureInRoom(widget.contenido.id);
        }
      });
    }
  }

  void _obtenerUsuarioActual() async {
    try {
      final authResult = await AuthService.verifyToken();
      if (authResult.success && authResult.user != null) {
        setState(() {
          _currentUserId = authResult.user!.id;
          _currentUserName = authResult.user!.username;
        });
        print('👤 Usuario actual cargado: ${authResult.user!.username} (${authResult.user!.id})');
      }
    } catch (e) {
      print('Error obteniendo usuario actual: $e');
    }
  }



  void _configurarSocketListeners() {
    // Siempre reconfigurar listeners para esta sala específica
    if (_listenersConfigurados) {
      print('🔄 Reconfigurado listeners para nueva sala');
      // Remover listener previo si existe
      if (_messageListener != null) {
        SocketService.instance.off('new_message', _messageListener!);
      }
    }
    
    // Crear nueva función listener
    _messageListener = (data) {
      final incomingRoom = data['roomId'] ?? data['room'];
      if (incomingRoom != widget.contenido.id) {
        // Debug detallado si se descarta
        print('🚫 Mensaje descartado por room mismatch. esperado=${widget.contenido.id} recibido=$incomingRoom keys=${data.keys.toList()}');
        return; // Solo mensajes de esta sala
      }
      
      try {
        final autorId = data['sender']?['id'] ?? data['userId'] ?? 'usuario';
        final autorNombre = data['sender']?['username'] ?? data['username'] ?? 'Usuario';
        
        // Debug: Comparar IDs
  print('📬 Nuevo mensaje recibido: ${data['content']} (room=$incomingRoom)');
        print('🆔 Autor ID del mensaje: $autorId');
        print('🆔 Mi ID actual: $_currentUserId');
        print('🎯 Es mi mensaje: ${_currentUserId != null && autorId == _currentUserId}');
        
        // Convertir datos del servidor directamente a Comentario
        // Determinar si es audio: type=='audio' o mediaId presente o fileUrl presente
        final bool esAudio = (data['type'] == 'audio') || (data['mediaId'] != null) || (data['fileUrl'] != null && (data['fileUrl'] as String).isNotEmpty);
        final comentario = Comentario(
          id: data['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          contenidoId: widget.contenido.id,
          autorId: autorId,
          autorNombre: autorNombre,
          tipo: esAudio ? TipoComentario.audio : TipoComentario.texto,
          contenido: esAudio ? (data['fileUrl'] ?? '') : (data['content'] ?? ''),
          mediaId: data['mediaId'] ?? (esAudio ? (data['mediaId'] ?? '') : null),
          mediaUrl: esAudio ? data['fileUrl'] : null,
          fechaCreacion: data['createdAt'] != null ? DateTime.parse(data['createdAt']) : DateTime.now(),
          duracionSegundos: esAudio ? (data['durationSeconds'] is int ? data['durationSeconds'] : (data['durationSeconds'] is double ? (data['durationSeconds'] as double).round() : null)) : null,
        );
        
        // Solo agregar si coincide con el tipo de sala
        bool debeAgregar = false;
        if (widget.esAudio && comentario.tipo == TipoComentario.audio) {
          debeAgregar = true;
        } else if (!widget.esAudio && comentario.tipo == TipoComentario.texto) {
          debeAgregar = true;
        }
        
        if (debeAgregar) {
          // Intentar reconciliar con mensaje optimista (temp_*) mismo contenido reciente
            final now = DateTime.now();
            final idxTemp = comentarios.indexWhere((c) => c.id.startsWith('temp_') && c.contenido == comentario.contenido && now.difference(c.fechaCreacion).inSeconds < 5);
            if (idxTemp >= 0) {
              setState(() {
                final prevSeq = comentarios[idxTemp].ordenSecuencia;
                comentarios[idxTemp] = comentario.copyWith(ordenSecuencia: prevSeq);
              });
              print('🟢 Reemplazado mensaje optimista por definitivo (${comentario.id})');
            } else {
              _agregarComentarioDelServidor(comentario);
            }
        }
        
      } catch (e) {
        print('❌ Error procesando mensaje del servidor: $e');
      }
    };
    
    // Registrar el listener
    SocketService.instance.on('new_message', _messageListener!);
    _listenersConfigurados = true;
    print('✅ Listeners configurados correctamente');
  }
  
  void _unirseASala() {
    // Forzar join siempre que se abre la pantalla (cambia audio/texto o reentra)
    SocketService.instance.joinRoomForce(widget.contenido.id, force: true);
    print('🏠 (force) Uniéndose a sala: ${widget.contenido.id}');
    
    // Verificar estado de conexión y rejoin si es necesario
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !SocketService.instance.isInRoom(widget.contenido.id)) {
        print('⚠️ Sala no confirmada, reintentando join...');
        SocketService.instance.joinRoomForce(widget.contenido.id, force: true);
      }
    });
  }
  
  void _agregarComentarioDelServidor(Comentario comentario) {
    // Evitar duplicados - no agregar si ya existe
    final yaExiste = comentarios.any((c) => c.id == comentario.id);
    if (yaExiste) {
      print('🔄 Comentario ${comentario.id} ya existe, ignorando');
      return;
    }
    
    setState(() {
      // Asignar ordenSecuencia si no viene definido
      final nextSeq = (++_maxOrdenSecuencia);
      final toInsert = comentario.ordenSecuencia == null
          ? comentario.copyWith(ordenSecuencia: nextSeq)
          : comentario;
      if (toInsert.ordenSecuencia != null && toInsert.ordenSecuencia! > _maxOrdenSecuencia) {
        _maxOrdenSecuencia = toInsert.ordenSecuencia!;
      }
      _insertarOrdenado(toInsert);
    });
    
    // Auto scroll al último comentario
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    
    print('✅ Nuevo comentario del servidor agregado: ${comentario.contenido}');
  }

  @override
  @override
  void dispose() {
    // Remover listener específico al salir
    if (_messageListener != null) {
      SocketService.instance.off('new_message', _messageListener!);
      print('🧹 Listener removido para sala: ${widget.contenido.id}');
    }
    // NO hacer leaveRoom para mantener suscripción activa en socket
    // SocketService.instance.leaveRoom(widget.contenido.id);
    
    // Si es sala de audio, opcionalmente limpiar estado de reproducción
    if (widget.esAudio) {
      try {
        // Detener reproducción para liberar índice y estado
        // ignore: use_build_context_synchronously
      } catch (_) {}
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _cargarComentarios() async {
    try {
      print('📚 Cargando historial para contenido: ${widget.contenido.id}');
      
      // Cargar comentarios del historial usando el ID del contenido como roomId
      final historial = await HistoryService.cargarHistorialRoom(widget.contenido.id);
      
      // Filtrar comentarios según el tipo de sala
      final comentariosFiltrados = historial.where((comentario) {
        if (widget.esAudio) {
          // Sala de audio: solo mostrar comentarios de audio
          return comentario.tipo == TipoComentario.audio;
        } else {
          // Sala de texto: solo mostrar comentarios de texto
          return comentario.tipo == TipoComentario.texto;
        }
      }).toList();
      
      if (mounted) {
        setState(() {
          comentarios = comentariosFiltrados;
          _historialCargado = true;
          if (comentarios.isNotEmpty) {
            _ultimaFecha = comentarios.last.fechaCreacion;
          }
          // Inicializar _maxOrdenSecuencia al máximo existente para continuidad
          if (comentarios.isNotEmpty) {
            _maxOrdenSecuencia = comentarios
                .map((c) => c.ordenSecuencia ?? 0)
                .fold<int>(0, (prev, el) => el > prev ? el : prev);
          }
        });
        print('✅ Historial cargado: ${comentarios.length} comentarios (${widget.esAudio ? 'audio' : 'texto'})');
        // Auto scroll al final tras el primer frame para mostrar el último mensaje
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
      
      // Si es audio, también cargar los URLs de audio en el MediaStorageService
      if (widget.esAudio) {
        final audioUrls = await HistoryService.cargarHistorialAudio(widget.contenido.id);
        if (audioUrls.isNotEmpty) {
          // Actualizar el servicio de audio con las URLs del servidor
          MediaStorageService.inicializarConHistorial(audioUrls);
          print('🎵 Audio historial inicializado: ${audioUrls.length} archivos');
        }
      }
      
    } catch (e) {
      print('❌ Error cargando historial: $e');
      if (mounted) {
        setState(() {
          comentarios = [];
        });
      }
    }
  }

  void _agregarComentario(Comentario comentario) {
    // Solo agregar el comentario si coincide con el tipo de sala
    bool debeAgregar = false;
    if (widget.esAudio && comentario.tipo == TipoComentario.audio) {
      debeAgregar = true;
    } else if (!widget.esAudio && comentario.tipo == TipoComentario.texto) {
      debeAgregar = true;
    }
    
    if (!debeAgregar) {
      print('🚫 Comentario ${comentario.tipo.name} ignorado en sala ${widget.esAudio ? 'audio' : 'texto'}');
      return;
    }
    
    setState(() {
      final existingIndex = comentarios.indexWhere((c) => c.id == comentario.id);
      if (existingIndex >= 0) {
        // Conservar la secuencia previa para estabilidad
        final prevSeq = comentarios[existingIndex].ordenSecuencia;
        comentarios[existingIndex] = comentario.copyWith(ordenSecuencia: prevSeq);
      } else {
        final nextSeq = (++_maxOrdenSecuencia);
        final insert = comentario.copyWith(ordenSecuencia: comentario.ordenSecuencia ?? nextSeq);
        if (insert.ordenSecuencia != null && insert.ordenSecuencia! > _maxOrdenSecuencia) {
          _maxOrdenSecuencia = insert.ordenSecuencia!;
        }
        _insertarOrdenado(insert);
      }
    });

    // Auto scroll al último comentario
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Volver al chat',
        ),
        title: Text(
          widget.esAudio ? 'Sala Audio' : 'Sala Texto',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          // Botón para cambiar a sala de audio/texto
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(
                widget.esAudio ? Icons.textsms : Icons.mic,
                color: Colors.white,
              ),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SalaComentariosScreen(
                      contenido: widget.contenido,
                      esAudio: !widget.esAudio,
                    ),
                  ),
                );
              },
              tooltip: widget.esAudio ? 'Cambiar a texto' : 'Cambiar a audio',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Mostrar la foto/contenido en la parte superior
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildContenidoPreview(),
            ),
          ),
          // Lista de comentarios
          Expanded(
            child: comentarios.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Aún no hay comentarios',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '¡Sé el primero en comentar!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: comentarios.length,
                    itemBuilder: (context, index) {
                      return ComentarioWidget(
                        comentario: comentarios[index],
                        allAudioComments: widget.esAudio ? comentarios : null,
                        currentUserId: _currentUserId,
                        currentUserName: _currentUserName,
                      );
                    },
                  ),
          ),
          // Input para nuevo comentario
          Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              top: 16,
              left: 16,
              right: 16,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: InputComentarioWidget(
              esAudio: widget.esAudio,
              onComentarioAgregado: _agregarComentario,
              contenidoId: widget.contenido.id,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContenidoPreview() {
    // Para la sala de comentarios, mostrar solo fotos. Videos NO se muestran para dejar la sala libre
    switch (widget.contenido.tipo) {
      case TipoContenido.imagen:
        return Container(
          width: double.infinity,
          height: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              widget.contenido.url,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey.shade300,
                child: const Center(
                  child: Icon(
                    Icons.image,
                    size: 60,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ),
        );
      case TipoContenido.video:
        // Para videos, solo mostrar referencia mínima
        return Container(
          width: double.infinity,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videocam,
                color: Colors.blue.shade600,
                size: 24,
              ),
            ],
          ),
        );
      default:
        return Container(
          width: double.infinity,
          height: 200,
          color: Colors.grey.shade300,
          child: const Center(
            child: Icon(
              Icons.help_outline,
              size: 60,
              color: Colors.grey,
            ),
          ),
        );
    }
  }


}