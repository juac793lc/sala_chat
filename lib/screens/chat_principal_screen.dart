import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../models/contenido_multimedia.dart';
import '../widgets/header_widget.dart';
import '../widgets/contenido_multimedia_widget.dart';
import '../widgets/input_multimedia_widget.dart';
import '../widgets/mapa_widget.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';
import 'sala_comentarios_screen.dart';

class ChatPrincipalScreen extends StatefulWidget {
  const ChatPrincipalScreen({super.key});

  @override
  State<ChatPrincipalScreen> createState() => _ChatPrincipalScreenState();
}

class _ChatPrincipalScreenState extends State<ChatPrincipalScreen> {
  bool _mostrarBliz = false;
  String? _currentUserName;
  String? _currentUserAvatar;
  
  // Usuarios del proyecto (se actualizan en tiempo real)
  List<Usuario> usuarios = [
    Usuario(id: '1', nombre: 'Tú', conectado: true),
    Usuario(id: '8', nombre: 'Diego', conectado: true),
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _setupSocketConnection();
  }

  void _loadCurrentUser() async {
    try {
      final result = await AuthService.verifyToken();
      if (result.success && result.user != null) {
        setState(() {
          _currentUserName = result.user!.username;
          _currentUserAvatar = result.user!.avatar;
        });
      }
    } catch (e) {
      print('Error cargando usuario: $e');
    }
  }

  void _setupSocketConnection() {
    // Conectar al servidor si no está conectado
    if (!SocketService.instance.isConnected) {
      SocketService.instance.connect();
    }

    // Unirse a la sala del proyecto
    SocketService.instance.joinRoom('proyecto_x');

    // Escuchar usuarios online/offline
    SocketService.instance.on('user_online', (data) {
      if (mounted) {
        _actualizarUsuarioOnline(data['username']);
      }
    });

    SocketService.instance.on('user_offline', (data) {
      if (mounted) {
        _actualizarUsuarioOffline(data['username']);
      }
    });

    // Escuchar nuevos contenidos multimedia
    SocketService.instance.on('nuevo_contenido', (data) {
      if (mounted) {
        _agregarContenidoDesdeSocket(data);
      }
    });

    // Escuchar historial de contenido al conectarse
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
    // Determinar tipo de contenido
    TipoContenido tipo = TipoContenido.imagen;
    final tipoString = data['tipo']?.toString() ?? '';
    if (tipoString.contains('audio')) {
      tipo = TipoContenido.audio;
    } else if (tipoString.contains('video')) {
      tipo = TipoContenido.video;
    }

    final nuevoContenido = ContenidoMultimedia(
      id: data['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      autorId: data['autorId'] ?? '0',
      autorNombre: data['autorNombre'] ?? 'Usuario',
      tipo: tipo,
      url: data['url'] ?? '',
      fechaCreacion: DateTime.parse(data['fechaCreacion'] ?? DateTime.now().toIso8601String()),
      comentariosTexto: data['comentariosTexto'] ?? 0,
      comentariosAudio: data['comentariosAudio'] ?? 0,
      duracionSegundos: data['duracionSegundos'],
    );

    setState(() {
      contenidoMultimedia.insert(0, nuevoContenido);
    });
  }

  void _cargarHistorialContenido(List<dynamic> historial) {
    final List<ContenidoMultimedia> contenidoHistorial = historial.map((data) {
      // Determinar tipo de contenido
      TipoContenido tipo = TipoContenido.imagen;
      final tipoString = data['tipo']?.toString() ?? '';
      if (tipoString.contains('audio')) {
        tipo = TipoContenido.audio;
      } else if (tipoString.contains('video')) {
        tipo = TipoContenido.video;
      }

      return ContenidoMultimedia(
        id: data['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        autorId: data['autorId'] ?? '0',
        autorNombre: data['autorNombre'] ?? 'Usuario',
        tipo: tipo,
        url: data['url'] ?? '',
        fechaCreacion: DateTime.parse(data['fechaCreacion'] ?? DateTime.now().toIso8601String()),
        comentariosTexto: data['comentariosTexto'] ?? 0,
        comentariosAudio: data['comentariosAudio'] ?? 0,
        duracionSegundos: data['duracionSegundos'],
      );
    }).toList();

    setState(() {
      // Reemplazar contenido con el historial del servidor
      contenidoMultimedia.clear();
      contenidoMultimedia.addAll(contenidoHistorial);
    });
    
    print('📚 Historial cargado: ${contenidoHistorial.length} elementos');
  }

  List<ContenidoMultimedia> contenidoMultimedia = [];

  void _navegarASalaComentarios(ContenidoMultimedia contenido, bool esAudio) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SalaComentariosScreen(
          contenido: contenido,
          esAudio: esAudio,
        ),
      ),
    );
  }

  void _agregarContenido(ContenidoMultimedia nuevoContenido) {
    setState(() {
      contenidoMultimedia.insert(0, nuevoContenido);
    });

    // Enviar por socket para que otros usuarios lo vean
    SocketService.instance.socket?.emit('nuevo_contenido', {
      'id': nuevoContenido.id,
      'autorId': nuevoContenido.autorId,
      'autorNombre': nuevoContenido.autorNombre,
      'tipo': nuevoContenido.tipo.toString(),
      'url': nuevoContenido.url,
      'fechaCreacion': nuevoContenido.fechaCreacion.toIso8601String(),
      'comentariosTexto': nuevoContenido.comentariosTexto,
      'comentariosAudio': nuevoContenido.comentariosAudio,
      'duracionSegundos': nuevoContenido.duracionSegundos,
      'roomId': 'proyecto_x',
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
                miembrosConectados: usuarios.where((u) => u.conectado).length,
                userName: _currentUserName,
                userAvatar: _currentUserAvatar,
              ),
              
              // Contenido multimedia
              Expanded(
                child: contenidoMultimedia.isEmpty
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
            onContenidoAgregado: _agregarContenido,
            onMapaTap: _toggleBliz,
          ),
        ],
      ),
    );
  }
}