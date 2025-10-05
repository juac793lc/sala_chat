enum TipoContenido { imagen, video, audio }

class ContenidoMultimedia {
  final String id;
  final String autorId;
  final String autorNombre;
  final TipoContenido tipo;
  final String url;
  final String? miniatura;
  final DateTime fechaCreacion;
  final int duracionSegundos; // Para audio/video
  final int comentariosTexto;
  final int comentariosAudio;

  ContenidoMultimedia({
    required this.id,
    required this.autorId,
    required this.autorNombre,
    required this.tipo,
    required this.url,
    this.miniatura,
    required this.fechaCreacion,
    this.duracionSegundos = 0,
    this.comentariosTexto = 0,
    this.comentariosAudio = 0,
  });

  ContenidoMultimedia copyWith({
    String? id,
    String? autorId,
    String? autorNombre,
    TipoContenido? tipo,
    String? url,
    String? miniatura,
    DateTime? fechaCreacion,
    int? duracionSegundos,
    int? comentariosTexto,
    int? comentariosAudio,
  }) {
    return ContenidoMultimedia(
      id: id ?? this.id,
      autorId: autorId ?? this.autorId,
      autorNombre: autorNombre ?? this.autorNombre,
      tipo: tipo ?? this.tipo,
      url: url ?? this.url,
      miniatura: miniatura ?? this.miniatura,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      duracionSegundos: duracionSegundos ?? this.duracionSegundos,
      comentariosTexto: comentariosTexto ?? this.comentariosTexto,
      comentariosAudio: comentariosAudio ?? this.comentariosAudio,
    );
  }
}