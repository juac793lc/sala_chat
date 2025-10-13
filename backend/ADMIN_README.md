Cómo usar el PIN admin rápido (DEFAULT_ADMIN_PIN)

Este backend soporta identificar un usuario como administrador durante el handshake de Socket.IO mediante el envío de un PIN.

- PIN por defecto: 041990 (variable de entorno: DEFAULT_ADMIN_PIN)
- Alternativa: definir ADMIN_USER_IDS en el entorno con IDs de usuario (comma separated)

Cómo enviar el PIN desde un cliente Socket.IO (ejemplo JavaScript):

```js
const socket = io('http://localhost:3001', {
  auth: {
    token: 'Bearer <TU_JWT_AQUI>', // opcional
    pin: '041990'
  }
});
```

Cómo enviar desde Flutter usando `socket_io_client`:

```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

final socket = IO.io('http://localhost:3001', {
  'transports': ['websocket'],
  'autoConnect': false,
  'auth': {
    'token': await AuthService.getToken(),
    'pin': '041990'
  }
});

socket.connect();
```

Notas de seguridad:
- El PIN por defecto "041990" está pensado para desarrollo y pruebas. En producción deberías usar tokens JWT con `isAdmin:true` o definir `ADMIN_USER_IDS`.
- El backend también acepta admins definidos por `ADMIN_USER_IDS` (env) y por la propiedad `isAdmin` en el JWT.

Reinicia el servidor después de cambiar `DEFAULT_ADMIN_PIN` o `ADMIN_USER_IDS`.
