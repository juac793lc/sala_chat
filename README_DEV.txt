Guía rápida para pruebas locales (Flutter web + Backend local)

1) Backend local
- Abrir PowerShell en: c:\Users\Lenovo\Desktop\sala_chat\backend
- Exportar variables y ejecutar:
  $env:JWT_SECRET='dev-secret-change-me'; $env:PORT='3001'; npm run dev
- El servidor escuchará en http://localhost:3001
- Ver logs en la terminal para ver eventos 'map_notification' y otros.

2) Flutter (web) local
- En la raíz del proyecto (c:\Users\Lenovo\Desktop\sala_chat), editar el archivo:
  lib/config/endpoints.dart
  - cambiar `useLocal` a true para apuntar a http://localhost:3001
- Ejecutar la app web:
  flutter run -d chrome
- Abre dos ventanas en el navegador para simular dos usuarios.

3) Flujo de prueba
- Asegúrate de permitir geolocalización en ambas ventanas.
- Comprueba en DevTools la línea '📡 Ubicación enviada: ...' en cada ventana.
- Crea un marcador desde una ventana, y en la terminal del backend deberías ver logs similares a:
  📣 Enviando map_notification a socket=... (dist=XXXm)
- La otra ventana mostrará un SnackBar con la notificación.

4) Para volver a producción
- Cambiar `useLocal` a false en lib/config/endpoints.dart y reconstruir/reiniciar la app para que apunte al servidor remoto.

Si quieres, hago el commit de estos cambios y creo la rama `feat/map-notifications`. Dime si procedo a commitear y pushear.```