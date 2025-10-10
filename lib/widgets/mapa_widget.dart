import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/tipo_reporte.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';
import '../config/endpoints.dart';

class MapaWidget extends StatefulWidget {
  final VoidCallback onClose;

  const MapaWidget({
    super.key,
    required this.onClose,
  });

  @override
  State<MapaWidget> createState() => _MapaWidgetState();
}

class _MapaWidgetState extends State<MapaWidget> {
  final MapController _mapController = MapController();
  final List<Marker> _markers = [];
  final List<Marker> _sharedMarkers = []; // Marcadores compartidos de otros usuarios
  final Map<String, Map<String, dynamic>> _markerData = {}; // Datos de marcadores para tiempo dinámico
  LatLng _currentCenter = const LatLng(18.4861, -69.9312); // Santo Domingo, RD (fallback)
  bool _isLoading = true; // Empezar con loading true
  TipoReporte? _tipoSeleccionado;
  int _markerCounter = 0; // Para IDs únicos de marcadores
  late final SocketService _socketService;
  Timer? _timeUpdateTimer; // Timer para actualizar tiempos de estrellas

  @override
  void initState() {
    super.initState();
    _socketService = SocketService.instance;
    _loadCurrentUser();
    // Obtener ubicación automáticamente al abrir el mapa (solo para centrar)
    _getCurrentLocationSilent();
    // Configurar listeners para marcadores compartidos
    _setupSocketListeners();
    // Iniciar timer para actualizar tiempos de estrellas cada minuto
    _startTimeUpdateTimer();
  }

  @override
  void dispose() {
    _removeSocketListeners();
    _timeUpdateTimer?.cancel();
    super.dispose();
  }

  // Configurar listeners de socket para marcadores
  void _setupSocketListeners() {
    _socketService.socket?.on('marker_added', (data) {
      if (mounted) {
        _addSharedMarker(data);
      }
    });
    
    _socketService.socket?.on('marker_removed', (data) {
      if (mounted) {
        _removeSharedMarker(data['markerId']);
      }
    });
    
    _socketService.socket?.on('marker_confirmed', (data) {
      if (mounted) {
        _addSharedMarker(data);
      }
    });

    // Listener para recibir marcadores existentes
    _socketService.socket?.on('existing_markers', (data) {
      if (mounted && data is List) {
        _loadExistingMarkers(data);
      }
    });

    // Evento para auto-eliminación de estrellas
    _socketService.socket?.on('marker_auto_removed', (data) {
      if (mounted) {
        _removeSharedMarker(data['markerId']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Marcador eliminado automáticamente'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    // Solicitar marcadores existentes
    _socketService.socket?.emit('request_existing_markers');
  }

  // Remover listeners de socket
  void _removeSocketListeners() {
    _socketService.socket?.off('marker_added');
    _socketService.socket?.off('marker_removed');
    _socketService.socket?.off('marker_confirmed');
    _socketService.socket?.off('existing_markers');
    _socketService.socket?.off('marker_auto_removed');
  }

  // Iniciar timer para actualizar tiempos de estrellas cada minuto
  void _startTimeUpdateTimer() {
    _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        // Regenerar solo las estrellas (marcadores con tiempo)
        _updateStarMarkers();
      }
    });
  }

  // Regenerar marcadores de estrellas con tiempo actualizado
  void _updateStarMarkers() {
    if (!mounted) return;
    
    // Lista de marcadores para regenerar
    final markersToRegenerate = <String, Map<String, dynamic>>{};
    
    // Encontrar todas las estrellas que necesitan actualización
    for (final entry in _markerData.entries) {
  if (entry.value['tipoReporte'] == 'interes' || entry.value['tipoReporte'] == 'policia') { // compat
        markersToRegenerate[entry.key] = entry.value;
      }
    }
    
    // Si hay estrellas para regenerar, hacerlo
    if (markersToRegenerate.isNotEmpty) {
      setState(() {
        // Eliminar todas las estrellas existentes
        _sharedMarkers.removeWhere((marker) {
          final key = marker.key.toString();
          return markersToRegenerate.keys.any((markerId) => key.contains(markerId));
        });
        
        // Regenerar todas las estrellas con tiempo actualizado
        for (final data in markersToRegenerate.values) {
          _addSharedMarkerInternal(data);
        }
      });
    }
  }

  // Función interna para agregar marcador sin guardar datos nuevamente
  void _addSharedMarkerInternal(Map<String, dynamic> data) {
    final markerId = data['id'];
    
    final tipoReporte = TipoReporte.values.firstWhere(
      (e) => e.toString() == 'TipoReporte.${data['tipoReporte']}',
      orElse: () {
        // compat si backend antiguo envía 'policia'
        if (data['tipoReporte'] == 'policia') return TipoReporte.interes;
        return TipoReporte.interes;
      },
    );
    
    final tipoInfo = TiposReporte.obtenerPorTipo(tipoReporte);
    
    // Tamaño según el tipo
  final markerSize = tipoReporte == TipoReporte.interes ? 50.0 : 20.0;
  final iconSize = tipoReporte == TipoReporte.interes ? 22.0 : 8.0;
  final borderWidth = tipoReporte == TipoReporte.interes ? 2.0 : 1.0;
    
    final marker = Marker(
      key: Key('shared_$markerId'),
      point: LatLng(data['latitude'], data['longitude']),
      width: markerSize,
      height: markerSize,
      child: GestureDetector(
        onTap: () {
          try { _maybeNotifyTelegram(data); } catch (e) { debugPrint('notify err: $e'); }
          _showSharedMarkerInfo(data, tipoInfo);
        },
        child: Container(
          decoration: BoxDecoration(
            color: tipoInfo.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white, 
              width: borderWidth
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 1,
                offset: const Offset(0, 0.5),
              ),
            ],
          ),
          child: Icon(
            tipoInfo.icono,
            color: Colors.white,
            size: iconSize,
          ),
        ),
      ),
    );
    
    _sharedMarkers.add(marker);
  }

  // Función para obtener ubicación sin mostrar marcador (solo centrar)
  Future<void> _getCurrentLocationSilent() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _useFallbackLocation();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          _useFallbackLocation();
          return;
        }
      }

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (e) {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
      }
      
      if (mounted) {
        LatLng newLocation = LatLng(position.latitude, position.longitude);
        
        double zoom = 15.0;
        if (position.accuracy <= 10) {
          zoom = 18.0;
        } else if (position.accuracy <= 50) {
          zoom = 16.0;
        } else if (position.accuracy <= 100) {
          zoom = 15.0;
        } else {
          zoom = 14.0;
        }
        
        setState(() {
          _currentCenter = newLocation;
        });
        
        _mapController.move(newLocation, zoom);
      }
    } catch (e) {
      _useFallbackLocation();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Función para obtener la ubicación actual
  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Servicios de ubicación desactivados. Usando ubicación por defecto.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        _useFallbackLocation();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permiso de ubicación denegado. Usando ubicación por defecto.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          _useFallbackLocation();
          return;
        }
      }

      // Intentar obtener la ubicación más precisa posible
      Position position;
      try {
        // Primer intento con máxima precisión
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (e) {
        // Si falla, intentar con precisión alta y más tiempo
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
      }
      
      if (mounted) {
        LatLng newLocation = LatLng(position.latitude, position.longitude);
        
        // Calcular zoom basado en la precisión
        double zoom = 15.0;
        if (position.accuracy <= 10) {
          zoom = 18.0; // Muy preciso (menos de 10 metros)
        } else if (position.accuracy <= 50) {
          zoom = 16.0; // Preciso (menos de 50 metros)
        } else if (position.accuracy <= 100) {
          zoom = 15.0; // Moderadamente preciso
        } else {
          zoom = 14.0; // Menos preciso
        }
        
        setState(() {
          _currentCenter = newLocation;
          // SÍ agregar marcador cuando el usuario hace clic manualmente
          _addMarker(newLocation, '📍 Mi ubicación (±${position.accuracy.round()}m)', Colors.green);
        });
        
        _mapController.move(newLocation, zoom);
        
        String precisionText = '';
        if (position.accuracy <= 10) {
          precisionText = '📍 Ubicación muy precisa (±${position.accuracy.round()}m)';
        } else if (position.accuracy <= 50) {
          precisionText = '📍 Ubicación precisa (±${position.accuracy.round()}m)';
        } else {
          precisionText = '📍 Ubicación aproximada (±${position.accuracy.round()}m)';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(precisionText),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo obtener ubicación. Usando ubicación por defecto.'),
            backgroundColor: Colors.orange,
          ),
        );
        _useFallbackLocation();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Función para usar ubicación por defecto cuando no se puede obtener GPS
  void _useFallbackLocation() {
    if (mounted) {
      setState(() {
        _currentCenter = const LatLng(18.4861, -69.9312); // Santo Domingo, RD
      });
      _mapController.move(_currentCenter, 13.0);
    }
  }

  // Función para agregar marcador compartido de otros usuarios
  void _addSharedMarker(Map<String, dynamic> data) {
    if (!mounted) return;
    
    final markerId = data['id'];

    // Normalizar timestamp a milisegundos (algunos navegadores/servidores podrían mandar en segundos)
    if (data.containsKey('timestamp')) {
      final ts = data['timestamp'];
      if (ts is int) {
        // Si parece estar en segundos (< 10^12) multiplicar
        if (ts < 1000000000000) {
          data['timestamp'] = ts * 1000;
        }
      } else if (ts is String) {
        // Intentar parse
        final parsed = int.tryParse(ts);
        if (parsed != null && parsed < 1000000000000) {
          data['timestamp'] = parsed * 1000;
        } else if (parsed != null) {
          data['timestamp'] = parsed;
        }
      }
    } else {
      // Si no trae timestamp, usar ahora como fallback (evita null) pero marcar para debug
      data['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    }
    
    // Guardar datos del marcador para actualizaciones dinámicas
    _markerData[markerId] = data;
    
    // Evitar duplicados
    final existingIndex = _sharedMarkers.indexWhere(
      (marker) => marker.key?.toString().contains(markerId) == true
    );
    if (existingIndex != -1) {
      // Actualizar marcador existente con nuevos datos
      _sharedMarkers.removeAt(existingIndex);
    }
    
    setState(() {
      _addSharedMarkerInternal(data);
    });
  }

  // Cargar usuario actual (id) para usar en llamadas al backend
  String? _currentUserId;
  void _loadCurrentUser() async {
    try {
      final cached = AuthService.getCachedUser();
      if (cached != null) {
        _currentUserId = cached.id;
        return;
      }
      final res = await AuthService.verifyToken();
      if (res.success && res.user != null) {
        _currentUserId = res.user!.id;
      }
    } catch (e) {
      debugPrint('No se pudo cargar usuario actual: $e');
    }
  }

  // Enviar notificación a Telegram cuando se clicka una estrella
  void _maybeNotifyTelegram(Map<String, dynamic> data) {
    final tipo = data['tipoReporte'];
    if (tipo != 'interes' && tipo != 'policia') return; // solo estrellas/compat

  final lat = data['latitude'];
  final lon = data['longitude'];
  final author = data['username'] ?? 'Usuario';
  // Calcular distancia desde la posición actual ( _currentCenter siempre tiene un valor por diseño )
  int distanceMeters = 0;
  try {
    final d = Geolocator.distanceBetween(_currentCenter.latitude, _currentCenter.longitude, lat, lon);
    distanceMeters = d.round();
  } catch (e) {
    debugPrint('Error calculando distancia: $e');
  }

  // Construir mensaje con columnas e iconos
  final text = _buildTelegramStarMessage(author, distanceMeters);
  _sendTelegramNotify(text);
  }

  Future<void> _sendTelegramNotify(String text) async {
    if (!mounted) return;
    try {
      final userId = _currentUserId;
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay usuario autenticado para notificar'), backgroundColor: Colors.orange),
        );
        return;
      }

      final uri = Uri.parse('${Endpoints.base}/api/telegram/notify');
      final body = json.encode({'userId': userId, 'text': text});
      final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: body).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notificación enviada a Telegram'), backgroundColor: Colors.green),
        );
      } else {
        debugPrint('Error notificando Telegram: ${resp.statusCode} ${resp.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error enviando notificación'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint('Excepción notificando Telegram: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error enviando notificación (timeout o red)'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Función para eliminar marcador compartido
  void _removeSharedMarker(String markerId) {
    if (!mounted) return;
    
    setState(() {
      _sharedMarkers.removeWhere(
        (marker) => marker.key?.toString().contains(markerId) == true
      );
      // Limpiar datos guardados
      _markerData.remove(markerId);
    });
  }

  // Mostrar información de marcador compartido
  void _showSharedMarkerInfo(Map<String, dynamic> data, TipoReporteInfo tipoInfo) {
  final bool isEstrella = data['tipoReporte'] == 'interes' || data['tipoReporte'] == 'policia'; // compat
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(tipoInfo.icono, color: tipoInfo.color, size: 24),
            const SizedBox(width: 8),
            Text(tipoInfo.nombre),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reportado por: ${data['username']}'),
            const SizedBox(height: 8),
            Text(tipoInfo.descripcion),
            // Solo mostrar tiempo en estrella (dinámico)
            if (isEstrella) ...[
              const SizedBox(height: 8),
              Text(
                'Hace ${_getTimeAgo(data['timestamp'])}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Opción de eliminar para todos los marcadores
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeMarkerFromServer(data['id']);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${tipoInfo.nombre} eliminado'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // Función para cargar marcadores existentes desde el servidor
  void _loadExistingMarkers(List<dynamic> markersData) {
    if (!mounted) return;
    
    debugPrint('🗺️ Cargando ${markersData.length} marcadores existentes');
    
    setState(() {
      _sharedMarkers.clear(); // Limpiar marcadores actuales
    });
    
    for (final markerData in markersData) {
      if (markerData is Map<String, dynamic>) {
        // Filtrar marcadores ya expirados según expiresAt si está presente
        final expiresAt = markerData['expiresAt'];
        if (expiresAt != null && expiresAt is int) {
          if (DateTime.now().millisecondsSinceEpoch > expiresAt) continue; // ya expirado, no agregar
        }
        _addSharedMarker(markerData);
      }
    }
    
    debugPrint('✅ Marcadores cargados: ${_sharedMarkers.length}');
    
    // Mostrar mensaje informativo
    if (mounted && markersData.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📍 ${markersData.length} marcadores cargados'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Función para eliminar marcador del servidor
  void _removeMarkerFromServer(String markerId) {
    _socketService.socket?.emit('remove_marker', {
      'markerId': markerId,
    });
    
    // Eliminar localmente también
    _removeSharedMarker(markerId);
  }

  // Función auxiliar para mostrar tiempo transcurrido
  String _getTimeAgo(int timestamp) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - timestamp;
    final minutes = (diff / (1000 * 60)).floor();
    
    // Siempre mostrar al menos 1 minuto
    if (minutes < 1) {
      return '1 min';
    } else if (minutes < 60) {
      // Capear visualización a 50 minutos para estrellas
      if (minutes <= 50) return '$minutes min';
      return '50+ min';
    } else {
      final hours = (minutes / 60).floor();
      if (hours < 24) {
        return '$hours h';
      } else {
        final days = (hours / 24).floor();
        return '$days d';
      }
    }
  }

  // Función para agregar marcadores de reporte
  void _addMarker(LatLng position, String label, Color color) {
    setState(() {
      _markers.add(
        Marker(
          point: position,
          width: 80,
          height: 80,
          child: GestureDetector(
            onTap: () => _showMarkerInfo(label),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Icon(
                  Icons.location_pin,
                  color: color,
                  size: 30,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  // Función para agregar marcador de reporte con tipo específico
  void _addReporteMarker(LatLng position, TipoReporteInfo tipoInfo) {
    final markerId = 'marker_${_markerCounter++}';
  final isPolicia = tipoInfo.tipo == TipoReporte.interes;
    
    // Tamaños: policía normal, otros 50% más pequeños
  final markerSize = isPolicia ? 50.0 : 20.0;  // 40 → 20 (50% reducción)
  final iconSize = isPolicia ? 22.0 : 8.0;     // 16 → 8 (50% reducción)
  final borderWidth = isPolicia ? 2.0 : 1.0;   // 1.5 → 1 (más fino)
    
    setState(() {
      _markers.add(
        Marker(
          key: Key(markerId),
          point: position,
          width: markerSize,
          height: markerSize,
          child: GestureDetector(
            onTap: () => _showReporteOptions(tipoInfo, markerId),
            child: Container(
              decoration: BoxDecoration(
                color: tipoInfo.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: borderWidth),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 1,
                    offset: const Offset(0, 0.5),
                  ),
                ],
              ),
              child: Icon(
                tipoInfo.icono,
                color: Colors.white,
                size: iconSize,
              ),
            ),
          ),
        ),
      );
    });
  }

  // Función para eliminar marcador
  void _removeMarker(String markerId) {
    setState(() {
      _markers.removeWhere((marker) => marker.key?.toString().contains(markerId) == true);
    });
  }

  // Función para manejar toque en el mapa
  void _onMapTap(LatLng position) {
    if (_tipoSeleccionado != null) {
      final tipoInfo = TiposReporte.obtenerPorTipo(_tipoSeleccionado!);
      _addReporteMarker(position, tipoInfo);
      
      // Enviar marcador a otros usuarios a través de socket
      _socketService.socket?.emit('add_marker', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'tipoReporte': _tipoSeleccionado!.toString().split('.').last,
      });

      // Enviar notificación a Telegram si es estrella/interes
      try {
        if (_tipoSeleccionado == TipoReporte.interes) {
          final author = 'Usuario';
          int distanceMeters = 0;
          try {
            final d = Geolocator.distanceBetween(_currentCenter.latitude, _currentCenter.longitude, position.latitude, position.longitude);
            distanceMeters = d.round();
          } catch (e) {
            debugPrint('Error calculando distancia al crear marcador: $e');
          }

          final text = _buildTelegramStarMessage(author, distanceMeters);
          _sendTelegramNotify(text);
        }
      } catch (e) {
        debugPrint('Error enviando telegram notify on create: $e');
      }
      
      // Mostrar confirmación
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tipoInfo.nombre} reportado y compartido'),
          backgroundColor: tipoInfo.color,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // Mostrar mensaje para seleccionar tipo
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un tipo de reporte primero'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Escapa caracteres HTML básicos para enviar con parse_mode=HTML
  String _escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  // Clasifica el estado según la distancia (metros)
  String _distanceStatus(int meters) {
    if (meters <= 300) return 'Muito perto';
    if (meters <= 500) return 'Perto';
    if (meters >= 1000) return 'Longe';
    return 'Moderado';
  }

  // Construye un mensaje HTML preformateado (monospace) con columnas para Telegram
  String _buildTelegramStarMessage(String author, int distanceMeters) {
    final safeAuthor = _escapeHtml(author);
    final status = _distanceStatus(distanceMeters);

    // Usamos <pre> para preservar espacios y columnas en Telegram (parse_mode=HTML)
    return '⭐ Estrela ativa\n\n'
        '<pre>👑  Estrela ativa   |  Reportado por: $safeAuthor\n'
        '📏  Distância       |  ${distanceMeters} m\n'
        '📍  Estado          |  $status\n'
        '</pre>';
  }

  // Mostrar información del marcador
  void _showMarkerInfo(String info) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Información del marcador'),
        content: Text(info),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Mostrar opciones del reporte (ver info o eliminar)
  void _showReporteOptions(TipoReporteInfo tipoInfo, String markerId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(tipoInfo.icono, color: tipoInfo.color, size: 24),
            const SizedBox(width: 8),
            Text(tipoInfo.nombre),
          ],
        ),
        content: Text(tipoInfo.descripcion),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeMarker(markerId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${tipoInfo.nombre} eliminado'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final mapHeight = screenHeight * 0.7; // 70% de la pantalla

    return SizedBox(
      height: mapHeight,
      width: double.infinity,
      child: Stack(
        children: [
          // Mapa ocupando todo el area del SizedBox
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentCenter,
                initialZoom: 13.0,
                onTap: (tapPosition, point) {
                  _onMapTap(point);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.sala_chat',
                ),
                MarkerLayer(
                  markers: [..._markers, ..._sharedMarkers],
                ),
              ],
            ),
          ),

          // Overlay de carga inicial sobre el mapa
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.white.withValues(alpha: 0.8),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Obteniendo tu ubicación...',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Floating left column with controls and report-type icons
          Positioned(
            top: 12,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.28),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Small title row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.map, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Mapa',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Vertical list of report-type icons (floating)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(TiposReporte.todos.length, (index) {
                      final tipoInfo = TiposReporte.todos[index];
                      final isSelected = _tipoSeleccionado == tipoInfo.tipo;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _tipoSeleccionado = isSelected ? null : tipoInfo.tipo;
                            });
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSelected ? tipoInfo.color : Colors.white.withOpacity(0.06),
                              shape: BoxShape.circle,
                              border: Border.all(color: tipoInfo.color, width: isSelected ? 2 : 1),
                            ),
                            child: Icon(
                              tipoInfo.icono,
                              color: isSelected ? Colors.white : tipoInfo.color,
                              size: 18,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 8),

                  // Action buttons (ubicación y cerrar)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _getCurrentLocation,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _isLoading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.my_location, color: Colors.white, size: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: widget.onClose,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}