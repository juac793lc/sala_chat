import 'package:flutter/material.dart';

enum TipoReporte {
  interes, // antes 'policia'
  emergencia,
  accidente,
  trafico,
  borracha,
  aviso,
  peligro,
}

class TipoReporteInfo {
  final TipoReporte tipo;
  final String nombre;
  final IconData icono;
  final Color color;
  final String descripcion;

  const TipoReporteInfo({
    required this.tipo,
    required this.nombre,
    required this.icono,
    required this.color,
    required this.descripcion,
  });
}

class TiposReporte {
  static const List<TipoReporteInfo> todos = [
    TipoReporteInfo(
      tipo: TipoReporte.interes,
      nombre: 'Punto',
      icono: Icons.star,
      color: Colors.blue,
      descripcion: 'Punto de interés especial',
    ),
    TipoReporteInfo(
      tipo: TipoReporte.emergencia,
      nombre: 'Emergencia',
      icono: Icons.emergency,
      color: Colors.red,
      descripcion: 'Situación de emergencia',
    ),
    TipoReporteInfo(
      tipo: TipoReporte.accidente,
      nombre: 'Accidente',
      icono: Icons.car_crash,
      color: Colors.orange,
      descripcion: 'Accidente de tránsito',
    ),
    TipoReporteInfo(
      tipo: TipoReporte.trafico,
      nombre: 'Tráfico',
      icono: Icons.traffic,
      color: Colors.red,
      descripcion: 'Congestión vehicular',
    ),
    TipoReporteInfo(
      tipo: TipoReporte.borracha,
      nombre: 'Reparación',
      icono: Icons.circle_outlined,
      color: Colors.black,
      descripcion: 'Reparación de llanta y servicios',
    ),
    TipoReporteInfo(
      tipo: TipoReporte.aviso,
      nombre: 'Cámara',
      icono: Icons.videocam,
      color: Colors.cyan,
      descripcion: 'Cámara de tráfico y carreteras',
    ),
    TipoReporteInfo(
      tipo: TipoReporte.peligro,
      nombre: 'Peligro',
      icono: Icons.warning,
      color: Colors.deepOrange,
      descripcion: 'Situación peligrosa',
    ),
  ];

  static TipoReporteInfo obtenerPorTipo(TipoReporte tipo) {
    return todos.firstWhere((info) => info.tipo == tipo);
  }
}