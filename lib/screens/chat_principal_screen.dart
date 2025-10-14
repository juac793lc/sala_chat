import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html; // solo para web: obtener geolocalización y recibir mensajes del service worker
import '../models/usuario.dart';
import '../models/contenido_multimedia.dart';
import '../widgets/header_widget.dart';
import '../widgets/contenido_multimedia_widget.dart';
import '../widgets/input_multimedia_widget.dart';
import '../widgets/mapa_widget.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';
import '../services/media_feed_service.dart'; // nuevo
import '../services/push_service.dart';
import '../config/endpoints.dart';
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
    // Pedir ubicación al iniciar la aplicación (solo una vez) y guardarla
    // No preguntar ubicación al iniciar para evitar diálogo molesto.

    if (kIsWeb) {
      _pushService = PushService(Endpoints.base);
      // Registrar service worker y suscripción de push sin requerir
      // que el usuario comparta su ubicación. Esto evita que se pida
      // geolocalización automáticamente al abrir la pantalla.
      _pushService!.getVapidPublicKey().then((key) {
        if (key != null) {
          _pushService!.registerServiceWorkerAndSubscribe(key, null).then((ok) {
            if (ok) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notificaciones activadas')));
            } else {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo activar notificaciones')));
            }
          });
        }
      });
    }

    // Listener para mensajes enviados desde el Service Worker (postMessage)
    if (kIsWeb) {
      try {
        html.window.onMessage.listen((event) {
          try {
            final data = event.data;
            if (data == null || data is! Map) return;
            final type = data['type'];
            final payload = data['payload'];
            if (type == 'push') {
              // Mensaje de push: mostrar SnackBar y opcionalmente abrir UI
              if (!mounted) return;
              final title = payload['title'] ?? 'Sala Chat';
              final body = payload['body'] ?? '';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$title • $body'),
                  duration: const Duration(seconds: 6),
                  action: SnackBarAction(
                    label: 'Ver',
                    onPressed: () => setState(() { _mostrarBliz = true; }),
                  ),
                ),
              );
            } else if (type == 'notificationclick') {
              // Usuario clickeó notificación: abrir mapa (o navegar)
              if (!mounted) return;
              setState(() { _mostrarBliz = true; });
            }
          } catch (e) {
            debugPrint('Error procesando mensaje SW: $e');
          }
        });
      } catch (e) {
        debugPrint('No se pudo registrar listener mensaje SW: $e');
      }
    }

    // Registrar listener para notificaciones de mapa (proximidad)
    SocketService.instance.on('map_notification', (data) {
      if (!mounted) return;
      try {
        final marker = data is Map ? data['marker'] : null;
        final dist = data is Map ? data['distanceMeters'] : null;
        final title = marker != null ? (marker['tipoReporte'] ?? 'Marcador cercano') : 'Marcador cercano';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title • ${dist ?? '?'} m'),
            action: SnackBarAction(
              label: 'Ver',
              onPressed: () => setState(() { _mostrarBliz = true; }),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      } catch (e) {
        debugPrint('Error procesando map_notification: $e');
      }
    });

    // Enviar ubicación inicial y manejo periódico sólo si el usuario
    // ha optado por compartir ubicación. Al mantener el registro de
    // push fuera de este bloque evitamos que el navegador pida
    // geolocalización automáticamente al abrir la pantalla.
    if (_compartirUbicacion && kIsWeb) {
      Future.delayed(const Duration(milliseconds: 500), () => _sendBrowserLocation());
      // Iniciar envío periódico
      _startPeriodicLocation();
    }
  }
  bool _mostrarBliz = false;
  // Para pruebas locales en web activamos envío de ubicación por defecto.
  // Puedes cambiar a false para exigir opt-in.
  bool _compartirUbicacion = false;
  double? _savedLat;
  double? _savedLng;
  PushService? _pushService;
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

  Future<void> _setupSocketConnection() async {
    // Conectar al servidor si no está conectado (esperar resultado)
    bool ok = true;
    if (!SocketService.instance.isConnected) {
      ok = await SocketService.instance.connect();
    }

    if (!ok || !SocketService.instance.isConnected) {
      // Mostrar aviso al usuario para que inicie sesión/registre el token
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No conectado: por favor inicia sesión para sincronizar el mapa'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ));
      }
      return;
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
    // Al abrir el mapa no pedimos consentimiento ni mostramos diálogos.
    // Si hay ubicación guardada enviaremos la ubicación al servidor.
    if (_mostrarBliz && kIsWeb && _compartirUbicacion) {
      _sendBrowserLocation();
    }
    // Solicitar marcadores existentes al backend cada vez que abrimos el mapa
    // para asegurar que los marcadores persistidos se muestran al reabrir.
    if (_mostrarBliz) {
      // Emitir después del frame para que el MapaWidget ya haya inicializado sus listeners
      // Nota: MapaWidget ya solicita existing_markers en su initState/post-frame.
      // Evitamos emitir aquí para no duplicar y crear condiciones de carrera.
    }
  }

  // Consentimiento manual eliminado: no mostrar diálogos al abrir el mapa.

  // Nota: la solicitud de ubicación al iniciar fue eliminada por ser molesta.

  void _cerrarBliz() {
    setState(() {
      _mostrarBliz = false;
    });
  }

  // Obtener ubicación del navegador (web) y enviarla al servidor
  Future<void> _sendBrowserLocation() async {
    if (!kIsWeb) return;
    try {
      final geo = html.window.navigator.geolocation;
      final pos = await geo.getCurrentPosition();
      final lat = pos.coords?.latitude;
      final lng = pos.coords?.longitude;
      if (lat != null && lng != null) {
        SocketService.instance.emit('update_location', {
          'lat': lat,
          'lng': lng,
          'ts': DateTime.now().toIso8601String()
        });
        debugPrint('📡 Ubicación enviada: $lat,$lng');
      }
    } catch (e) {
      debugPrint('Error getCurrentPosition: $e');
    }
  }

  // Periodically send location while compartir is true (web only)
  Timer? _locationTimer;
  void _startPeriodicLocation() {
    if (!kIsWeb) return;
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_compartirUbicacion) _sendBrowserLocation();
    });
  }
  void _stopPeriodicLocation() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  @override
  void dispose() {
    _stopPeriodicLocation();
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
                titulo: 'notimapa',
                miembrosTotal: usuarios.length,
                miembrosConectados: _usuariosConectados,
                userName: _currentUserName,
                userAvatar: _currentUserAvatar,
                suscritos: _usuariosSuscritos,
                onNotificationTap: null,
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
                            padding: const EdgeInsets.only(bottom: 20),
                            child: ContenidoMultimediaWidget(
                              contenido: contenido,
                              onTextoTap: () => _navegarASalaComentarios(contenido, false),
                              onAudioTap: () => _navegarASalaComentarios(contenido, true),
                              onDelete: (id) {
                                setState(() {
                                  contenidoMultimedia.removeWhere((c) => c.id == id);
                                });
                              },
                            ),
                          );
                        },
                      ),
              ),
              
              // Nota: el mapa se muestra como overlay Positioned abajo (más abajo en el árbol)
              // para evitar que su altura afecte el layout principal y provoque overflows.
            ],
          ),
          
          // Botones flotantes en la esquina inferior derecha
          InputMultimediaWidget(
            roomId: widget.roomId,
            onContenidoAgregado: _agregarContenido,
            onMapaTap: _toggleBliz,
          ),
          // Mapa como overlay para evitar overflow del Column
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _mostrarBliz ? MediaQuery.of(context).size.height * 0.9 : 0,
              // Sólo construir el widget del mapa cuando realmente se muestre.
              child: _mostrarBliz ? MapaWidget(
                onClose: _cerrarBliz,
                allowAutoLocation: _compartirUbicacion,
                initialLat: _savedLat,
                initialLng: _savedLng,
              ) : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}