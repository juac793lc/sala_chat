README: Conectar Flutter (desarrollo) al backend (local o Railway)

Resumen:
- Este proyecto soporta apuntar el cliente Flutter al backend local o a la URL remota (Railway).
- Control mediante --dart-define en tiempo de ejecución/compilación.

Opciones disponibles (en `lib/config/endpoints.dart`):
- USE_LOCAL (true|false) -> si true usa la URL local (http://localhost:3001)
- API_BASE -> si definido, sobreescribe cualquier base y se usa como endpoint completo

Comandos útiles (PowerShell)

1) Ejecutar Flutter apuntando al backend local (dev):
flutter run -d chrome --web-renderer html --dart-define=USE_LOCAL=true

2) Ejecutar Flutter apuntando al backend en Railway (producción):
# Reemplaza la URL por la tuya (sin slash final)
flutter run -d chrome --web-renderer html --dart-define=USE_LOCAL=false --dart-define=API_BASE="https://<tu-servicio>.up.railway.app"

3) Compilar para producción (web) apuntando a Railway:
flutter build web --web-renderer html --dart-define=USE_LOCAL=false --dart-define=API_BASE="https://<tu-servicio>.up.railway.app"

4) Probar sockets y push
- Asegúrate de que la URL en `API_BASE` es accesible desde el navegador.
- Para websockets: el cliente usará `Endpoints.socketUrl` que transforma http->ws.
- Para Push: registra service worker (web/register_push.js y web/push_worker.js) y asegúrate de que el servidor tenga VAPID keys y endpoint `/api/push/vapidPublicKey`.

5) Ejemplo mínimo en Dart (usar Endpoints desde cualquier parte del cliente):
import 'package:tu_app/config/endpoints.dart';

final base = Endpoints.base; // base correcta según dart-define
final ws = Endpoints.socketUrl; // para conectar sockets

6) Notas y recomendaciones
- Cuando pruebas local, ejecuta `node backend/server.js` o desde VSCode el backend para tener los endpoints locales.
- Si usas Railway y el servicio está detrás de HTTPS, asegúrate de usar la misma URL en `API_BASE` (https://...)
- Si tu web está servida desde otra origin, activa CORS en el backend (ya configurado en este repo).

7) Cambios recientes en UI y funcionalidades
- Mapa: Los iconos de selección de tipo de reporte (policía, incendio, etc.) ahora están organizados en una columna flotante en la esquina izquierda con fondo semi-transparente, en lugar de una fila horizontal en la cabecera. Esto mejora la vista profesional y evita recortar el mapa.
- Multimedia: Los contenedores de imágenes y videos ahora usan un 65% de la altura de pantalla para previews más grandes, con zoom interactivo en imágenes y BoxFit dinámico para mejor ajuste (fitWidth para panorámicas, contain para otras).
- Notificaciones Push: Corregidas notificaciones duplicadas; ahora solo se envían para marcadores tipo 'estrella' (interes), con emoji ⭐ en el título. Deduplicación por clave de cliente (p256dh) y endpoint.

Si quieres, puedo añadir un script `run_dev.ps1` que lance el backend local y el comando `flutter run` con tus flags preferidos.
