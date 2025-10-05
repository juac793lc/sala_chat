import 'package:flutter/material.dart';

class HeaderWidget extends StatelessWidget {
  final String titulo;
  final int miembrosTotal;
  final int miembrosConectados;
  final String? userAvatar;
  final String? userName;

  const HeaderWidget({
    super.key,
    required this.titulo,
    required this.miembrosTotal,
    required this.miembrosConectados,
    this.userAvatar,
    this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar del usuario actual
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 25,
                  backgroundColor: _getAvatarColor(userName ?? 'User'),
                  child: Text(
                    _getAvatarText(userName, userAvatar),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Información del grupo
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre del grupo
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Información de miembros
                    Text(
                      '$miembrosTotal miembros, $miembrosConectados conectados',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getAvatarText(String? userName, String? userAvatar) {
    if (userAvatar != null && userAvatar.contains(':')) {
      return userAvatar.split(':')[0];
    }
    return (userName ?? 'U')[0].toUpperCase();
  }

  Color _getAvatarColor(String name) {
    final colors = [
      Colors.blue.shade600,
      Colors.green.shade600,
      Colors.orange.shade600,
      Colors.purple.shade600,
      Colors.red.shade600,
      Colors.teal.shade600,
      Colors.indigo.shade600,
      Colors.pink.shade600,
    ];
    final index = name.length % colors.length;
    return colors[index];
  }
}