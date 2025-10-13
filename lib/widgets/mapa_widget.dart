import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// 'kIsWeb' not needed in this widget file
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
    try { SocketService.instance.off('connected', () {}); } catch (_) {}
    _timeUpdateTimer?.cancel();
    super.dispose();
  }

  // Configurar listeners de socket para marcadores
  void _setupSocketListeners() {
    // Usar el mecanismo de callbacks centralizado del SocketService para
    // que los listeners sobrevivan a reconexiones y se registren una vez.
    SocketService.instance.on('marker_added', (data) {
      if (mounted) _addSharedMarker(data);
    });

    SocketService.instance.on('marker_removed', (data) {
      if (mounted) _removeSharedMarker(data['markerId']);
    });

    SocketService.instance.on('marker_confirmed', (data) {
      // Actualizar contadores cuando recibimos confirmaciones (no re-add)
      try {
        debugPrint('marker_confirmed recibido: $data');
        if (data is Map) {
          final id = data['id'] ?? data['markerId'];
          if (id != null && _markerData.containsKey(id)) {
            final entry = _markerData[id]!;
            entry['confirms'] = data['confirms'] ?? entry['confirms'] ?? 0;
            entry['denies'] = data['denies'] ?? entry['denies'] ?? 0;
            setState(() {});
          }
        }
      } catch (e) {
        debugPrint('Error procesando marker_confirmed: $e');
      }
    });

    SocketService.instance.on('existing_markers', (data) {
      if (mounted && data is List) _loadExistingMarkers(data);
    });

    SocketService.instance.on('marker_auto_removed', (data) {
      if (!mounted) return;
      _removeSharedMarker(data['markerId']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['message'] ?? 'Marcador removido automaticamente'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    });

    // Actualizaciones de conteos (confirms/denies)
    SocketService.instance.on('marker_updated', (data) {
      try {
        debugPrint('marker_updated recibido: $data');
        if (data is Map) {
          final id = data['id'] ?? data['markerId'];
          if (id != null && _markerData.containsKey(id)) {
            final entry = _markerData[id]!;
            entry['confirms'] = data['confirms'] ?? entry['confirms'] ?? 0;
            entry['denies'] = data['denies'] ?? entry['denies'] ?? 0;
            setState(() {});
          }
        }
      } catch (e) {
        debugPrint('Error procesando marker_updated: $e');
      }
    });

    // Pedir marcadores existentes ahora si ya estamos conectados;
    // si no, pediremos al reconectarnos (SocketService emite 'connected').
    void _onConnected(dynamic _) {
      try {
        debugPrint('SocketService conectado -> solicitando existing_markers');
        SocketService.instance.emit('request_existing_markers', {});
      } catch (e) {
        debugPrint('Error emitiendo request_existing_markers: $e');
      }
      // Una sola vez
      try { SocketService.instance.off('connected', _onConnected); } catch (_) {}
    }

    if (SocketService.instance.isConnected) {
      SocketService.instance.emit('request_existing_markers', {});
    } else {
      SocketService.instance.on('connected', _onConnected);
    }
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
            // No notificar al tocar la estrella para evitar reenvíos.
            _showSharedMarkerInfo(data, tipoInfo);
          },
          child: Container(
            decoration: BoxDecoration(
              color: tipoInfo.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 1,
                  offset: const Offset(0, 0.5),
                ),
              ],
            ),
            // Mostrar icono y, si es una estrella/"interes", un pequeño badge con minutos restantes
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  tipoInfo.icono,
                  color: Colors.white,
                  size: iconSize,
                ),
                // Mostrar badge para tipos 'interes' o cuando el backend envía 'policia' en data
                if (tipoReporte == TipoReporte.interes || (data['tipoReporte']?.toString() == 'policia')) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      // Mostrar minutos restantes como "Xm" o "Expirado"
                      (_minutesRemaining(data) > 0) ? '${_minutesRemaining(data)}m' : 'Exp',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
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
            _addMarker(newLocation, '📍 Minha localização (±${position.accuracy.round()}m)', Colors.green);
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
  // ignore: unused_element
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

  // (Se eliminó el envío automático de Telegram al tocar una estrella para evitar reenvíos)

  Future<void> _sendTelegramNotify(String text, {bool broadcast = true}) async {
    if (!mounted) return;
    try {
      // Si broadcast=true, enviamos al grupo configurado en el backend.
      if (broadcast) {
        final uri = Uri.parse('${Endpoints.base}/api/telegram/broadcast');
        final body = json.encode({'text': text});
        final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: body).timeout(const Duration(seconds: 8));

          if (resp.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notificação enviada para o Telegram (grupo)'), backgroundColor: Colors.green),
          );
        } else {
          debugPrint('Error notificando Telegram (broadcast): ${resp.statusCode} ${resp.body}');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erro ao enviar notificação'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // Modo user-specific (compatibilidad): intentar enviar por userId
      final userId = _currentUserId;
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum usuário autenticado para notificar'), backgroundColor: Colors.orange),
        );
        return;
      }

      final uri = Uri.parse('${Endpoints.base}/api/telegram/notify');
      final body = json.encode({'userId': userId, 'text': text});
      final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: body).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notificação enviada para o Telegram'), backgroundColor: Colors.green),
        );
      } else {
        debugPrint('Error notificando Telegram: ${resp.statusCode} ${resp.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao enviar notificação'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint('Excepción notificando Telegram: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao enviar notificação (timeout ou rede)'), backgroundColor: Colors.red),
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
    final confirms = (data['confirms'] ?? _markerData[data['id']]?['confirms']) ?? 0;
    final denies = (data['denies'] ?? _markerData[data['id']]?['denies']) ?? 0;
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
            if (isEstrella)
              Row(
                children: const [
                  Icon(Icons.warning, color: Colors.red, size: 18),
                  SizedBox(width: 6),
                  Text('Alerta', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              )
            else
              const SizedBox.shrink(),
            const SizedBox(height: 8),
            Text(tipoInfo.descripcion),
            if (isEstrella) ...[
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final minsLeft = _minutesRemaining(data);
                final minutesText = minsLeft > 0 ? '$minsLeft min restantes' : 'Expirado';
                return Text(
                  minutesText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                );
              }),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await _confirmMarkerHttp(data['id']);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirmado (via REST)'), backgroundColor: Colors.green));
                      } catch (e) {
                        debugPrint('Error confirmando via HTTP: $e');
                        try {
                          SocketService.instance.emit('confirm_marker', {'markerId': data['id']});
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirmado (via Socket)'), backgroundColor: Colors.green));
                        } catch (e2) {
                          debugPrint('Error confirm via socket fallback: $e2');
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo confirmar (sin conexión)'), backgroundColor: Colors.orange));
                        }
                      }
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check),
                    label: Text('Confirmar ($confirms)'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await _denyMarkerHttp(data['id']);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Negado (via REST)'), backgroundColor: Colors.red));
                      } catch (e) {
                        debugPrint('Error negando via HTTP: $e');
                        try {
                          SocketService.instance.emit('deny_marker', {'markerId': data['id']});
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Negado (via Socket)'), backgroundColor: Colors.red));
                        } catch (e2) {
                          debugPrint('Error deny via socket fallback: $e2');
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo negar (sin conexión)'), backgroundColor: Colors.orange));
                        }
                      }
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close),
                    label: Text('Negar ($denies)'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeMarkerFromServer(data['id']);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${tipoInfo.nombre} removido'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Remover', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
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
    SocketService.instance.emit('remove_marker', {
      'markerId': markerId,
    });
    
    // Eliminar localmente también
    _removeSharedMarker(markerId);
  }

  // HTTP helpers para confirmar/denegar via REST (fallback cuando WS falla)
  Future<void> _confirmMarkerHttp(String markerId) async {
    final uri = Uri.parse('${Endpoints.base}/api/markers/confirm');
    final headers = await AuthService.getHeaders();
    final resp = await http.post(uri, headers: headers, body: json.encode({'markerId': markerId})).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('HTTP confirm failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<void> _denyMarkerHttp(String markerId) async {
    final uri = Uri.parse('${Endpoints.base}/api/markers/deny');
    final headers = await AuthService.getHeaders();
    final resp = await http.post(uri, headers: headers, body: json.encode({'markerId': markerId})).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('HTTP deny failed: ${resp.statusCode} ${resp.body}');
    }
  }

  // Función auxiliar para mostrar tiempo transcurrido
  // ignore: unused_element
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

  // Devuelve minutos transcurridos desde la creación del marcador, en el rango 1..50.
  // Si no hay información de tiempo válida retorna 0 (indefinido/expirado).
  int _minutesRemaining(Map<String, dynamic> data) {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      const autoRemoveMs = 50 * 60 * 1000; // 50 minutos

      int timestamp = 0;
      if (data.containsKey('timestamp') && data['timestamp'] is int) {
        timestamp = data['timestamp'] as int;
        // Normalizar segundos -> milisegundos si fuera necesario
        if (timestamp < 1000000000000) {
          timestamp = timestamp * 1000;
        }
      } else if (data.containsKey('expiresAt') && data['expiresAt'] is int) {
        final expiresAt = data['expiresAt'] as int;
        timestamp = expiresAt - autoRemoveMs;
      } else {
        return 0; // sin datos temporales
      }

      final elapsedMs = now - timestamp;
      if (elapsedMs < 0) return 0;
      final minutes = (elapsedMs / (1000 * 60)).floor();
      if (minutes < 1) return 1; // mostrar 1 minuto al crearse
      if (minutes > 50) return 50; // cap a 50
      return minutes;
    } catch (e) {
      return 0;
    }
  }

  // Función para agregar un marcador local simple (seguro y que compila)
  void _addMarker(LatLng position, String label, Color color) {
    final markerId = 'local_ ${_markerCounter++}';
    setState(() {
      _markers.add(
        Marker(
          key: Key(markerId),
          point: position,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showMarkerInfo(label),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.0),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2, offset: const Offset(0, 1)),
                ],
              ),
              child: const Center(
                child: Icon(Icons.location_pin, color: Colors.white, size: 20),
              ),
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
                    color: Colors.black.withOpacity(0.1),
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
  Future<void> _onMapTap(LatLng position) async {
  // Si el tap está sobre un marcador existente (compartido o local),
  // evitamos que el onTap global del mapa cree uno nuevo y envíe notificaciones.
  // Aumentamos el umbral para robustez contra desplazamientos en la interacción web.
  const double _tapThresholdMeters = 80.0; // umbral en metros para considerar "tap sobre marcador"

      try {
        // 1) Verificar marcadores locales creados en esta vista (_markers)
        for (final m in _markers) {
          try {
            final LatLng mp = m.point;
            final d = Geolocator.distanceBetween(mp.latitude, mp.longitude, position.latitude, position.longitude);
            if (d <= _tapThresholdMeters) {
              // Asumir que el GestureDetector del marcador gestionó el tap; no crear nada ni notificar
              return;
            }
          } catch (_) {}
        }

        // 1b) Verificar marcadores compartidos renderizados (_sharedMarkers)
        for (final m in _sharedMarkers) {
          try {
            final LatLng mp = m.point;
            final d = Geolocator.distanceBetween(mp.latitude, mp.longitude, position.latitude, position.longitude);
            if (d <= _tapThresholdMeters) {
              // Tap sobre marcador compartido: mostrar su info si la tenemos
              final key = m.key?.toString() ?? '';
              // Buscar id en key: 'shared_<id>'
              final match = RegExp(r'shared_(.+)');
              final mm = match.firstMatch(key);
              if (mm != null) {
                final id = mm.group(1);
                final data = id != null ? _markerData[id] : null;
                if (data != null) {
                  final tipoStr = data['tipoReporte'] ?? 'interes';
                  TipoReporte tipoEnum;
                  try {
                    tipoEnum = TipoReporte.values.firstWhere((e) => e.toString() == 'TipoReporte.$tipoStr');
                  } catch (_) {
                    tipoEnum = TipoReporte.interes;
                  }
                  final tipoInfo = TiposReporte.obtenerPorTipo(tipoEnum);
                  _showSharedMarkerInfo(data, tipoInfo);
                }
              }
              return;
            }
          } catch (_) {}
        }

        // 2) Verificar marcadores compartidos (datos en _markerData)
        String? nearestMarkerId;
        Map<String, dynamic>? nearestData;
        double nearestDist = double.infinity;
        for (final entry in _markerData.entries) {
          try {
            final lat = entry.value['latitude'];
            final lng = entry.value['longitude'];
            if (lat == null || lng == null) continue;
            final d = Geolocator.distanceBetween(lat as double, lng as double, position.latitude, position.longitude);
            if (d <= _tapThresholdMeters && d < nearestDist) {
              nearestDist = d;
              nearestMarkerId = entry.key;
              nearestData = entry.value;
            }
          } catch (_) {}
        }

        if (nearestData != null && nearestMarkerId != null) {
          // Mostrar info del marcador compartido en lugar de crear uno nuevo
          final tipoStr = nearestData['tipoReporte'] ?? 'interes';
          TipoReporte tipoEnum;
          try {
            tipoEnum = TipoReporte.values.firstWhere((e) => e.toString() == 'TipoReporte.$tipoStr');
          } catch (_) {
            tipoEnum = TipoReporte.interes;
          }
          final tipoInfo = TiposReporte.obtenerPorTipo(tipoEnum);
          _showSharedMarkerInfo(nearestData, tipoInfo);
          return;
        }
      } catch (e) {
        debugPrint('Error detecting marker proximity in _onMapTap: $e');
        // Si falla la detección, seguimos con el flujo normal (se creará un marcador si _tipoSeleccionado != null)
      }

      if (_tipoSeleccionado != null) {
        final tipoInfo = TiposReporte.obtenerPorTipo(_tipoSeleccionado!);
        _addReporteMarker(position, tipoInfo);
        
        // Enviar marcador a otros usuarios a través de SocketService
        if (!SocketService.instance.isConnected) {
          // Mostrar feedback claro: no estamos conectados, el marcador no se compartirá
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No conectado al servidor. Inicia sesión para compartir el marcador.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ));
          }
        } else {
          SocketService.instance.emit('add_marker', {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'tipoReporte': _tipoSeleccionado!.toString().split('.').last,
          });
        }
        
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
            // Pedir confirmación antes de enviar la notificación para evitar envíos accidentales
            final shouldSend = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Enviar notificação'),
                content: const Text('Deseja enviar uma notificação para o Telegram sobre este alerta?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Não')),
                  TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sim')),
                ],
              ),
            ) ?? false;

            if (shouldSend) {
              _sendTelegramNotify(text);
            }
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
      // Mostrar mensagem para selecionar tipo
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um tipo de relatório primeiro'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // (helpers removed: escapeHtml and distanceStatus were unused after message simplification)

  // Construye un mensaje HTML preformateado (monospace) con columnas para Telegram
  String _buildTelegramStarMessage(String author, int distanceMeters) {
  // Mensaje general al grupo con alarma
  return '🚨 <b>ALERTA</b>\n\n'
    '⭐ <b>Estrela ativa</b>\n'
    'Por favor, veja o mapa.';
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
                color: Colors.white.withOpacity(0.8),
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.22),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title row compact
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.map, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Mapa',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Smaller vertical list of report-type icons
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(TiposReporte.todos.length, (index) {
                      final tipoInfo = TiposReporte.todos[index];
                      final isSelected = _tipoSeleccionado == tipoInfo.tipo;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _tipoSeleccionado = isSelected ? null : tipoInfo.tipo;
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isSelected ? tipoInfo.color : Colors.white.withOpacity(0.06),
                              shape: BoxShape.circle,
                              border: Border.all(color: tipoInfo.color, width: isSelected ? 2 : 1),
                            ),
                            child: Icon(
                              tipoInfo.icono,
                              color: isSelected ? Colors.white : tipoInfo.color,
                              size: 14,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 6),
                  // Compact Telegram register button
                  if (_currentUserId != null)
                    TextButton.icon(
                      onPressed: () {
                        final botUsername = 'notificamapa_bot';
                        final startParam = Uri.encodeComponent(_currentUserId!);
                        final url = 'https://t.me/$botUsername?start=$startParam';
                        showDialog(context: context, builder: (_) => AlertDialog(
                          title: const Text('Registrar en Telegram'),
                          content: Text('Abra este enlace en Telegram para completar el registro:\n\n$url'),
                          actions: [
                            TextButton(onPressed: () { Navigator.pop(context); }, child: const Text('Cerrar')),
                            TextButton(onPressed: () {
                              Navigator.pop(context);
                              Clipboard.setData(ClipboardData(text: url));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enlace copiado al portapapeles')));
                            }, child: const Text('Copiar enlace')),
                          ],
                        ));
                      },
                      icon: const Icon(Icons.telegram, color: Colors.white, size: 16),
                      label: const Text('Telegram', style: TextStyle(color: Colors.white, fontSize: 12)),
                      style: TextButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                    ),

                  // Action buttons (ubicación y cerrar) compact
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _getCurrentLocation,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _isLoading
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.my_location, color: Colors.white, size: 14),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: widget.onClose,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 14),
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