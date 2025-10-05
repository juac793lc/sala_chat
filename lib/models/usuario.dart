
class Usuario {
  final String id;
  final String nombre;
  final bool conectado;
  final String? avatar;

  Usuario({
    required this.id,
    required this.nombre,
    required this.conectado,
    this.avatar,
  });

  Usuario copyWith({
    String? id,
    String? nombre,
    bool? conectado,
    String? avatar,
  }) {
    return Usuario(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      conectado: conectado ?? this.conectado,
      avatar: avatar ?? this.avatar,
    );
  }
}