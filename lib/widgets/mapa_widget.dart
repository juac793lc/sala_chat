import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/tipo_reporte.dart';

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
  List<Marker> _markers = [];
  LatLng _currentCenter = const LatLng(18.4861, -69.9312); // Santo Domingo, RD
  bool _isLoading = false;
  TipoReporte? _tipoSeleccionado;
  int _markerCounter = 0; // Para IDs únicos de marcadores

  // Función para obtener la ubicación actual
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Servicios de ubicación desactivados')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación denegado')),
          );
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition();
      LatLng newLocation = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _currentCenter = newLocation;
        _addMarker(newLocation, '📍 Mi ubicación', Colors.blue);
      });
      
      _mapController.move(newLocation, 15.0);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error obteniendo ubicación: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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
    final isPolicia = tipoInfo.tipo == TipoReporte.policia;
    
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
  void _onMapTap(LatLng position) {
    if (_tipoSeleccionado != null) {
      final tipoInfo = TiposReporte.obtenerPorTipo(_tipoSeleccionado!);
      _addReporteMarker(position, tipoInfo);
      
      // Mostrar confirmación
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tipoInfo.nombre} reportado'),
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
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header con controles
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.map, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Mapa - Reportes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const Spacer(),
                // Botón Mi ubicación
                GestureDetector(
                  onTap: _getCurrentLocation,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.my_location,
                            color: Colors.green.shade700,
                            size: 16,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                // Botón cerrar
                GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.close,
                      color: Colors.red.shade700,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Panel de selección compacto
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: TiposReporte.todos.length,
              itemBuilder: (context, index) {
                final tipoInfo = TiposReporte.todos[index];
                final isSelected = _tipoSeleccionado == tipoInfo.tipo;
                
                return Container(
                  width: 46, // Más compacto
                  margin: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _tipoSeleccionado = isSelected ? null : tipoInfo.tipo;
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isSelected ? tipoInfo.color : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: tipoInfo.color,
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected ? [
                              BoxShadow(
                                color: tipoInfo.color.withOpacity(0.2),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ] : null,
                          ),
                          child: Icon(
                            tipoInfo.icono,
                            color: isSelected ? Colors.white : tipoInfo.color,
                            size: 14,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          tipoInfo.nombre,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 7,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? tipoInfo.color : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Mapa real con panel lateral
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
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
                    markers: _markers,
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