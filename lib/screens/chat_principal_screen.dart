import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../models/contenido_multimedia.dart';
import '../widgets/header_widget.dart';
import '../widgets/contenido_multimedia_widget.dart';
import '../widgets/input_multimedia_widget.dart';
import '../widgets/mapa_widget.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';
import '../services/media_feed_service.dart'; // nuevo
import 'sala_comentarios_screen.dart';

class ChatPrincipalScreen extends StatefulWidget {
  final String roomId;

  const ChatPrincipalScreen({
    super.key,
    required this.roomId,
  });

  @override
  State<ChatPrincipalScreen> createState() => _ChatPrincipalScreenState();
}

class _ChatPrincipalScreenState extends State<ChatPrincipalScreen> {
  @override
  void initState() {
    super.initState();
    // Escuchar evento de actualización de comentarios en tiempo real
    SocketService.instance.socket?.on('comentarios_actualizados', (data) {
      if (data == null || !mounted) return;
      final contenidoId = data['contenidoId']?.toString();
      if (contenidoId == null) return;
      setState(() {
        final idx = contenidoMultimedia.indexWhere((c) => c.id == contenidoId);
        if (idx != -1) {
          if (data['comentariosTexto'] != null) {
            contenidoMultimedia[idx] = contenidoMultimedia[idx].copyWith(comentariosTexto: data['comentariosTexto']);
          }
          if (data['comentariosAudio'] != null) {
            contenidoMultimedia[idx] = contenidoMultimedia[idx].copyWith(comentariosAudio: data['comentariosAudio']);
          }
        }
      });
    });
    _loadCurrentUser();
    _cargaInicialFeed();
    _setupSocketConnection();
  }
  bool _mostrarBliz = false;
  String? _currentUserName;
  String? _currentUserAvatar;
  // Indicador de carga inicial HTTP
  bool _cargandoInicial = false;
  // Set para deduplicar IDs provenientes de HTTP + sockets
  final Set<String> _idsContenido = {};

  // Usuarios del proyecto (se actualizan en tiempo real)
  List<Usuario> usuarios = [
    Usuario(id: '1', nombre: 'Tú', conectado: true),
    Usuario(id: '8', nombre: 'Diego', conectado: true),
  ];
  
  // Contadores dinámicos de usuarios
  int _usuariosConectados = 2;
  int _usuariosSuscritos = 0;


  Future<void> _cargaInicialFeed() async {
    setState(() { _cargandoInicial = true; });
    try {
      final lista = await MediaFeedService.instance.obtenerFeedRoom(widget.roomId);
      if (!mounted) return;
      // Lista REST viene en orden DESC (más nuevo primero). Insertamos respetando eso.
      contenidoMultimedia.clear();
      for (final c in lista) {
        if (!_idsContenido.contains(c.id)) {
          _idsContenido.add(c.id);
          contenidoMultimedia.add(c); // ya está DESC (0 = más nuevo)
        }
      }
    } catch (e) {
      // Ignoramos error pero mantenemos UI funcional
      debugPrint('Error carga inicial feed: $e');
    } finally {
      if (mounted) setState(() { _cargandoInicial = false; });
    }
  }

  void _loadCurrentUser() async {
    try {
      final result = await AuthService.verifyToken();
      if (result.success && result.user != null) {
        setState(() {
          _currentUserName = result.user!.username;
          _currentUserAvatar = result.user!.avatar;
        });
        debugPrint('👤 Usuario principal cargado: ${result.user!.username}');
      }
    } catch (e) {
      debugPrint('Error cargando usuario: $e');
    }
  }

  void _setupSocketConnection() {
    // Conectar al servidor si no está conectado
    if (!SocketService.instance.isConnected) {
      SocketService.instance.connect();
    }

    // Unirse a la sala del proyecto
    SocketService.instance.joinRoom(widget.roomId);

    // Escuchar usuarios online/offline
    SocketService.instance.on('user_online', (data) {
      if (mounted) {
        _actualizarUsuarioOnline(data['username']);
        // Actualizar contadores con datos del backend
        setState(() {
          _usuariosConectados = data['totalConnected'] ?? _usuariosConectados;
          _usuariosSuscritos = data['totalRegistered'] ?? _usuariosSuscritos;
        });
        debugPrint('🟢 Usuario online: ${data['username']} | Conectados: $_usuariosConectados | Total con app: $_usuariosSuscritos');
      }
    });

    SocketService.instance.on('user_offline', (data) {
      if (mounted) {
        _actualizarUsuarioOffline(data['username']);
        // Actualizar contadores con datos del backend
        setState(() {
          _usuariosConectados = data['totalConnected'] ?? _usuariosConectados;
          _usuariosSuscritos = data['totalRegistered'] ?? _usuariosSuscritos;
        });
        debugPrint('🔴 Usuario offline: ${data['username']} | Conectados: $_usuariosConectados | Total con app: $_usuariosSuscritos');
      }
    });

    // Escuchar nuevos contenidos multimedia
    SocketService.instance.on('nuevo_contenido', (data) {
      if (mounted) {
        _agregarContenidoDesdeSocket(data);
      }
    });

    // Escuchar multimedia compartido (nuevo evento para feed)
    SocketService.instance.on('multimedia_compartido', (data) {
      debugPrint('🎉 RECIBIDO multimedia_compartido: ${data.toString()}');
      if (mounted) {
        debugPrint('💫 Procesando multimedia_compartido en UI...');
        _agregarContenidoDesdeSocket(data);
        debugPrint('✅ Multimedia_compartido procesado');
      } else {
        debugPrint('❌ Widget no mounted, ignorando multimedia_compartido');
      }
    });

    // Escuchar historial de contenido al conectarse (socket). Puede solaparse con HTTP.
    SocketService.instance.on('historial_contenido', (data) {
      if (mounted) {
        _cargarHistorialContenido(data);
      }
    });
  }

  void _actualizarUsuarioOnline(String? username) {
    if (username == null) return;
    setState(() {
      final index = usuarios.indexWhere((u) => u.nombre == username);
      if (index != -1) {
        usuarios[index] = Usuario(
          id: usuarios[index].id,
          nombre: usuarios[index].nombre,
          conectado: true,
        );
      }
    });
  }

  void _actualizarUsuarioOffline(String? username) {
    if (username == null) return;
    setState(() {
      final index = usuarios.indexWhere((u) => u.nombre == username);
      if (index != -1) {
        usuarios[index] = Usuario(
          id: usuarios[index].id,
          nombre: usuarios[index].nombre,
          conectado: false,
        );
      }
    });
  }

  void _agregarContenidoDesdeSocket(Map<String, dynamic> data) {
    debugPrint('🔍 _agregarContenidoDesdeSocket llamado con data: $data');
    
    // Determinar tipo de contenido
    TipoContenido tipo = TipoContenido.imagen;
    final tipoString = data['tipo']?.toString() ?? '';
    debugPrint('🎭 Tipo detectado: $tipoString');
    
    if (tipoString.contains('audio')) {
      tipo = TipoContenido.audio;
    } else if (tipoString.contains('video')) {
      tipo = TipoContenido.video;
    }

    final nuevoContenido = ContenidoMultimedia(
      id: data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      autorId: data['autorId']?.toString() ?? '0',
      autorNombre: data['autorNombre']?.toString() ?? 'Usuario',
      tipo: tipo,
      url: data['url'] ?? '',
      fechaCreacion: DateTime.tryParse(data['fechaCreacion'] ?? '') ?? DateTime.now(),
      comentariosTexto: data['comentariosTexto'] ?? 0,
      comentariosAudio: data['comentariosAudio'] ?? 0,
      duracionSegundos: data['duracionSegundos'],
    );

    if (_idsContenido.contains(nuevoContenido.id)) {
      debugPrint('⚠️ Contenido ya existe con ID: ${nuevoContenido.id}');
      return; // ya existe (probablemente vino por HTTP o historial socket)
    }

    debugPrint('🎯 Agregando nuevo contenido a la UI: ${nuevoContenido.id}');
    setState(() {
      _idsContenido.add(nuevoContenido.id);
      contenidoMultimedia.insert(0, nuevoContenido);
    });
    debugPrint('✅ Contenido agregado. Total items: ${contenidoMultimedia.length}');
  }

  void _cargarHistorialContenido(List<dynamic> historial) {
    // Socket puede mandar items quizá ya cargados vía HTTP -> deduplicar
    bool huboCambio = false;
    for (final data in historial) {
      TipoContenido tipo = TipoContenido.imagen;
      final tipoString = data['tipo']?.toString() ?? '';
      if (tipoString.contains('audio')) {
        tipo = TipoContenido.audio;
      } else if (tipoString.contains('video')) {
        tipo = TipoContenido.video;
      }

      final id = data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
      if (_idsContenido.contains(id)) continue; // saltar duplicado

      final contenido = ContenidoMultimedia(
        id: id,
        autorId: data['autorId']?.toString() ?? '0',
        autorNombre: data['autorNombre']?.toString() ?? 'Usuario',
        tipo: tipo,
        url: data['url'] ?? '',
        fechaCreacion: DateTime.tryParse(data['fechaCreacion'] ?? '') ?? DateTime.now(),
        comentariosTexto: data['comentariosTexto'] ?? 0,
        comentariosAudio: data['comentariosAudio'] ?? 0,
        duracionSegundos: data['duracionSegundos'],
      );

      _idsContenido.add(id);
      contenidoMultimedia.add(contenido); // historial socket asumimos ya ordenado
      huboCambio = true;
    }

    if (huboCambio && mounted) {
      setState(() {});
    }
    if (huboCambio) {
      debugPrint('📚 Historial socket añadió nuevos (no duplicados). Total: ${contenidoMultimedia.length}');
    }
  }

  List<ContenidoMultimedia> contenidoMultimedia = [];

  void _navegarASalaComentarios(ContenidoMultimedia contenido, bool esAudio) {
    Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (context) => SalaComentariosScreen(
          contenido: contenido,
          esAudio: esAudio,
        ),
      ),
    ).then((nuevoConteo) {
      if (nuevoConteo != null) {
        setState(() {
          final idx = contenidoMultimedia.indexWhere((c) => c.id == contenido.id);
          if (idx != -1) {
            if (esAudio) {
              contenidoMultimedia[idx] = contenidoMultimedia[idx].copyWith(comentariosAudio: nuevoConteo);
            } else {
              contenidoMultimedia[idx] = contenidoMultimedia[idx].copyWith(comentariosTexto: nuevoConteo);
            }
          }
        });
      }
    });
  }

  void _agregarContenido(ContenidoMultimedia nuevoContenido) {
    if (_idsContenido.contains(nuevoContenido.id)) return; // seguridad
    setState(() {
      _idsContenido.add(nuevoContenido.id);
      contenidoMultimedia.insert(0, nuevoContenido);
    });

    // Enviar por socket para que otros usuarios lo vean
    String tipoString = 'image';
    if (nuevoContenido.tipo == TipoContenido.video) {
      tipoString = 'video';
    } else if (nuevoContenido.tipo == TipoContenido.audio) {
      tipoString = 'audio';
    }

    SocketService.instance.emit('nuevo_multimedia', {
      'roomId': widget.roomId,
      'contenido': {
        'id': nuevoContenido.id,
        'autorId': nuevoContenido.autorId,
        'autorNombre': nuevoContenido.autorNombre,
        'tipo': tipoString,
        'url': nuevoContenido.url,
        'fechaCreacion': nuevoContenido.fechaCreacion.toIso8601String(),
        'comentariosTexto': nuevoContenido.comentariosTexto,
        'comentariosAudio': nuevoContenido.comentariosAudio,
        'duracionSegundos': nuevoContenido.duracionSegundos,
      }
    });
  }

  void _toggleBliz() {
    setState(() {
      _mostrarBliz = !_mostrarBliz;
    });
  }

  void _cerrarBliz() {
    setState(() {
      _mostrarBliz = false;
    });
  }

  @override
  void dispose() {
    // Salir de la sala del proyecto
    SocketService.instance.leaveRoom('proyecto_x');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          // Contenido principal
          Column(
            children: [
              // Header con perfil del usuario
              HeaderWidget(
                titulo: 'Proyecto X 🚀',
                miembrosTotal: usuarios.length,
                miembrosConectados: _usuariosConectados,
                userName: _currentUserName,
                userAvatar: _currentUserAvatar,
                suscritos: _usuariosSuscritos,
              ),
              // Indicador de carga inicial
              if (_cargandoInicial)
                const LinearProgressIndicator(minHeight: 2),
              // Contenido multimedia
              Expanded(
                child: contenidoMultimedia.isEmpty && !_cargandoInicial
                    ? const Center(
                        child: Text(
                          'No hay contenido aún\n¡Comparte algo!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        itemCount: contenidoMultimedia.length,
                        itemBuilder: (context, index) {
                          final contenido = contenidoMultimedia[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ContenidoMultimediaWidget(
                              contenido: contenido,
                              onTextoTap: () => _navegarASalaComentarios(contenido, false),
                              onAudioTap: () => _navegarASalaComentarios(contenido, true),
                            ),
                          );
                        },
                      ),
              ),
              
              // Widget Mapa que se despliega desde abajo
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _mostrarBliz ? MediaQuery.of(context).size.height * 0.65 : 0,
                child: _mostrarBliz
                    ? Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        child: MapaWidget(
                          onClose: _cerrarBliz,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          
          // Botones flotantes en la esquina inferior derecha
          InputMultimediaWidget(
            roomId: widget.roomId,
            onContenidoAgregado: _agregarContenido,
            onMapaTap: _toggleBliz,
          ),
        ],
      ),
    );
  }
}