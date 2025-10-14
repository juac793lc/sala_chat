import 'package:flutter/material.dart';

class HeaderWidget extends StatelessWidget {
  final String titulo;
  final int miembrosTotal;
  final int miembrosConectados;
  final String? userAvatar;
  final String? userName;
  final int suscritos; // nuevo placeholder
  final VoidCallback? onNotificationTap; // nuevo

  const HeaderWidget({
    super.key,
    required this.titulo,
    required this.miembrosTotal,
    required this.miembrosConectados,
    this.userAvatar,
    this.userName,
    this.suscritos = 0,
    this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // Degradado azul de izquierda arriba a derecha abajo
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D47A1), // Azul oscuro
            Color(0xFF42A5F5), // Azul claro
          ],
          stops: [0.0, 1.0],
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SizedBox(
            height: 60, // Altura fija reducida
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Espacio izquierdo vacío (avatar eliminado).
                const SizedBox(width: 8),
                
                // Centro expandido con título y contadores
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Título centrado con icono de mapa a la izquierda
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.map, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          // Make the title flexible so it can truncate instead of overflowing
                          Flexible(
                            child: Text(
                              titulo,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: .5,
                              ),
                            ),
                          ),
                        ],
                      ),
                          const SizedBox(height: 2),
                    ],
                  ),
                ),
                
                // Espacio reservado a la derecha reducido para evitar overflow
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // (avatar helpers removed — header simplified to show only title and counters)
}

