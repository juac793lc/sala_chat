Flutter — cómo apuntar la app al backend en Railway y compilar

Resumen
- Puedes seleccionar la URL del backend en tiempo de build usando `--dart-define=API_BASE=<URL>`.
- Para Flutter web debes asegurarte de que los archivos de service worker están bajo `web/` y que el servidor sirve las rutas necesarias (push worker, manifest, etc.).

1) Desarrollo local (puedes seguir usando la URL local definida en `lib/config/endpoints.dart`)
- Por defecto `useLocal = true` en `Endpoints`. Para desarrollo local no necesitas flags.

2) Construir Flutter apuntando al backend en Railway (producción)
- Reemplaza <YOUR_RAILWAY_URL> por tu URL pública (ej: https://sala-chat-backend.up.railway.app)

Flutter web:
- Desde la raíz del proyecto Flutter (donde está `pubspec.yaml`):

# limpiar cache opcional
flutter clean

# compilar web apuntando al backend en Railway
flutter build web --dart-define=API_BASE="https://<YOUR_RAILWAY_URL>"

# luego sirve la carpeta build/web con cualquier hosting estático
# o empaca el build en el proyecto web que uses.

Flutter móvil (Android/iOS):
# compilar debug/release con la URL en tiempo de build
flutter run -d chrome --dart-define=API_BASE="https://<YOUR_RAILWAY_URL>"
# o para release
flutter build apk --dart-define=API_BASE="https://<YOUR_RAILWAY_URL>"

3) Service Worker y Push (Flutter web)
- Archivos importantes (ya incluidos en el repo): `web/push_worker.js`, `web/register_push.js`.
- Asegúrate que `push_worker.js` está listado en `web/` y que `index.html` registra el service worker (o regístralo manualmente en `main.dart` usando JS interop).
- Para que las notificaciones via Web Push funcionen necesitas las VAPID keys configuradas en el backend y que los usuarios acepten la subscripción.

4) Probar sockets (runtime)
- Al compilar la app apuntando a Railway, abre la app web y verifica que el cliente se conecta al Socket.IO del backend. Revisa logs del servidor en Railway para confirmar conexiones:
railway logs --tail

5) Variables sensibles
- No embebas secretos en el cliente. Usa `--dart-define` sólo para la URL base. Variables como JWT_SECRET o VAPID_PRIVATE_KEY deben estar en Railway variables (dashboard).

6) Debug y verificación
- Si la app no se conecta, prueba desde el navegador la URL de la API:
curl -i https://<YOUR_RAILWAY_URL>/api/auth/verify

- Verifica CORS: el backend permite orígenes del dominio donde publiques tu Flutter web.

7) Despliegue continuo (opcional)
- Conecta tu repo de frontend a un hosting (Vercel, Netlify) o a GitHub Actions que ejecute `flutter build web` con `--dart-define` y despliegue.

Fin.
