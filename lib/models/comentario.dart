enum TipoComentario { texto, audio, imagen, video }

class Comentario {
  final String id;
  final String contenidoId; // ID lógico / room o hilo
  final String autorId;
  final String autorNombre;
  final TipoComentario tipo;
  final String contenido; // Texto (si texto) o URL (legacy para audio)
  final DateTime fechaCreacion;
  final int? duracionSegundos; // Solo para audio
  final String? mediaId; // ID persistente devuelto por backend (/upload)
  final String? mediaUrl; // URL final del recurso multimedia
  // Índice de orden estable local (no necesariamente proviene del backend). Permite ordenar de forma estable
  // cuando múltiples mensajes comparten el mismo segundo de creación y el sort de Dart (no estable) podría
  // reordenarlos inesperadamente.
  final int? ordenSecuencia;

  const Comentario({
    required this.id,
    required this.contenidoId,
    required this.autorId,
    required this.autorNombre,
    required this.tipo,
    required this.contenido,
    required this.fechaCreacion,
    this.duracionSegundos,
    this.mediaId,
    this.mediaUrl,
    this.ordenSecuencia,
  });

  Comentario copyWith({
    String? id,
    String? contenidoId,
    String? autorId,
    String? autorNombre,
    TipoComentario? tipo,
    String? contenido,
    DateTime? fechaCreacion,
    int? duracionSegundos,
    String? mediaId,
    String? mediaUrl,
    int? ordenSecuencia,
  }) {
    return Comentario(
      id: id ?? this.id,
      contenidoId: contenidoId ?? this.contenidoId,
      autorId: autorId ?? this.autorId,
      autorNombre: autorNombre ?? this.autorNombre,
      tipo: tipo ?? this.tipo,
      contenido: contenido ?? this.contenido,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      duracionSegundos: duracionSegundos ?? this.duracionSegundos,
      mediaId: mediaId ?? this.mediaId,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      ordenSecuencia: ordenSecuencia ?? this.ordenSecuencia,
    );
  }

  bool get esTexto => tipo == TipoComentario.texto;
  bool get esAudio => tipo == TipoComentario.audio;
  bool get esImagen => tipo == TipoComentario.imagen;
  bool get esVideo => tipo == TipoComentario.video;

  // Serialización para futuras integraciones API
  Map<String, dynamic> toJson() => {
        'id': id,
        'contenidoId': contenidoId,
        'autorId': autorId,
        'autorNombre': autorNombre,
        'tipo': tipo.name,
        'contenido': contenido,
        'fechaCreacion': fechaCreacion.toIso8601String(),
        'duracionSegundos': duracionSegundos,
        'mediaId': mediaId,
        'mediaUrl': mediaUrl,
    'ordenSecuencia': ordenSecuencia,
      };

  factory Comentario.fromJson(Map<String, dynamic> json) => Comentario(
        id: json['id'] as String,
        contenidoId: json['contenidoId'] as String? ?? '',
        autorId: json['autorId'] as String? ?? '',
        autorNombre: json['autorNombre'] as String? ?? 'Anónimo',
        tipo: _parseTipo(json['tipo']),
        contenido: json['contenido'] as String? ?? '',
        fechaCreacion: DateTime.tryParse(json['fechaCreacion'] ?? '') ?? DateTime.now(),
        duracionSegundos: json['duracionSegundos'] as int?,
        mediaId: json['mediaId'] as String?,
        mediaUrl: json['mediaUrl'] as String?,
    ordenSecuencia: json['ordenSecuencia'] as int?,
      );

  static TipoComentario _parseTipo(String? raw) {
    if (raw == null) return TipoComentario.texto;
    return TipoComentario.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => TipoComentario.texto,
    );
  }
}