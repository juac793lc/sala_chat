# Sala Chat + Mapa (Flutter + Node/Socket.IO)

## 🇪🇸 Descripción
Aplicación de tiempo real con:
- Chat (texto + audio) estable y reconciliado
- Feed multimedia unificado
- Mapa colaborativo con marcadores y Puntos de Interés temporizados (expiran automáticamente)
- Backend Node.js + Socket.IO + SQLite (sql.js persistido en archivo)
- Frontend Flutter multiplataforma (Web, Desktop, Mobile)

Estado actual: Chat + Mapa funcionando. Los marcadores especiales (tipo `interes`) muestran tiempo transcurrido y se eliminan automáticamente a los 50 minutos.

## Características Clave (Chat & Multimedia)
1. Conexión controlada a salas (join protegido para evitar listeners duplicados)
2. UI optimista: el mensaje aparece inmediatamente con id temporal `temp_*`
3. Reconciliación: al llegar el evento real se sustituye conservando posición
4. Inserción incremental: NO se reordena toda la lista (evita saltos visuales)
5. Monotonicidad de timestamps después de cargar historial (previene que un nuevo mensaje quede arriba)
6. Reproductor de audio con playlist y bloqueo de duplicados
7. Cache de historial (mitiga 429 / rate limit)
8. Estructura de servicios (separación de responsabilidades)

## Mapa y Marcadores (Tiempo Real)
Características:
1. Marcadores compartidos se propagan vía Socket.IO inmediatamente.
2. Marcadores tipo `interes` (Punto de Interés) incluyen timestamp de creación en milisegundos.
3. El cliente recalcula cada minuto el tiempo transcurrido sin reiniciar al reconectarse.
4. Auto-eliminación programada en el backend a los 50 minutos (broadcast `marker_auto_removed`).
5. Compatibilidad retro: si algún cliente viejo envía `policia`, se normaliza a `interes`.

Eventos relacionados:
- `add_marker` (cliente → servidor)
- `marker_confirmed` (eco al creador)
- `marker_added` (a otros clientes)
- `request_existing_markers` / `existing_markers` (sincronización inicial)
- `marker_removed` (eliminación manual)
- `marker_auto_removed` (expiración automática)

Campos del marcador:
```json
{
  "id": "uuid",
  "userId": "usuario_creador",
  "username": "Nombre",
  "latitude": 0.0,
  "longitude": 0.0,
  "tipoReporte": "interes",
  "timestamp": 1730740000000  // epoch ms
}
```

## Arquitectura (Frontend)
- `services/socket_service.dart`: Conecta, maneja eventos, logging y control de join.
- `services/history_service.dart`: Cachea historial y asigna `ordenSecuencia` incremental.
- `services/audio_playlist_service.dart`: Maneja cola y reproducción de clips.
- `screens/sala_comentarios_screen.dart`: Lógica de inserción incremental y reconciliación.
- `widgets/input_comentario_widget.dart`: Crea mensajes optimistas + envío.

Modelo principal: `Comentario { id, userId, contenido, fecha, ordenSecuencia, tipo (texto|audio) }`.

## Arquitectura (Backend)
- `server.js` inicializa Express + Socket.IO
- `src/controllers/socketController.js` maneja eventos (`join_room`, `new_message`, etc.)
- `src/models/*.js` representan entidades SQLite/memoria
- `src/routes/*` endpoints REST básicos (auth/media/mensajes)

Base de datos: SQLite (puede reemplazarse por persistencia en memoria (`memory_db`)).

## Flujo Mensajes (Simplificado)
```
Usuario escribe -> crea Comentario temp -> UI lo muestra -> socket emite ->
backend persiste -> emite a la sala -> frontend recibe -> busca temp -> reemplaza ->
asegura orden -> scroll opcional al final.
```

## Orden Cronológico Estable
- No se hace `sort()` global salvo en carga de historial inicial.
- Cada mensaje nuevo se inserta con búsqueda lineal al final (ascendente por fecha, fallback `ordenSecuencia`).
- Si el timestamp del nuevo <= último conocido se ajusta a `ultimaFecha + 1 ms`.

## Audio
- Grabación (web: `web_recorder_service.dart`, otras plataformas: `platform_audio_service.dart`).
- Subida y referencia en el mensaje.
- Reproducción controlada para evitar solapes y duplicados en cola.

## Requisitos Previos
- Flutter SDK 3.x+
- Node.js 18+
- (Opcional) SQLite3 instalado para inspección directa

## Instalación y Ejecución
### Backend
```
cd backend
npm install
npm start   # o: node server.js
```
Variables de entorno (crear `.env` si se requiere):
```
PORT=3000
SQLITE_DB_PATH=./chat.db
```

### Frontend Flutter
```
flutter pub get
flutter run -d windows   # o chrome / android / etc.
```
Para Web:
```
flutter run -d chrome
```

## Estructura de Carpetas (resumen)
```
backend/
  server.js
  src/
    controllers/
    models/
    routes/
lib/
  services/
  screens/
  widgets/
  models/
assets/
```

## Roadmap Próximo
- Clustering de marcadores
- Filtros por tipo
- Persistencia de multimedia asociada a un marcador
- Moderación / roles
- Notificaciones push

## Scripts Sugeridos (Backend) — futuros
Añadir a `backend/package.json`:
```json
{
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  }
}
```

## Contribuciones / Issues
1. Clonar y crear rama feature: `git checkout -b feat/nueva-funcionalidad`
2. Commit atómico + mensaje convencional (feat:, fix:, chore:, docs:, refactor:)
3. PR describiendo cambios y pruebas manuales.

## Licencia
Sin licencia explícita aún (añadir más adelante, sugerido MIT).

---
## 🇬🇧 Overview (English)
Real-time chat room app featuring:
- Text messages (optimistic UI + reconciliation)
- Inline recorded audio clips
- Stable chronological ordering (incremental insertion + monotonic timestamps)
- Node.js + Socket.IO backend (SQLite or in-memory)
- Flutter multi-platform frontend

Current milestone: stable text/audio chat + real-time map with expiring interest points.

### Key Features
See Spanish section above (mirrors: controlled join, optimistic temp messages, reconciliation, incremental insertion, monotonic timestamps, audio playlist, history cache, service-layer separation).

### Message Flow
Same as Spanish section — optimistic temp message replaced on server echo preserving position.

### Run Backend
```
cd backend
npm install
npm start
```
(Use `.env` for PORT, DB path.)

### Run Frontend
```
flutter pub get
flutter run -d chrome   # or another device
```

### Roadmap
- Report model + in-memory storage
- Map screen (flutter_map) with markers
- Create report interaction (long press / FAB)
- Filter reports by content / room
- Persist to backend API

### License
Not defined yet (recommend MIT).

---
### Notas Técnicas Internas
- Estrategia anti-reordenamientos implementada y probada manualmente.
- Si se integra paginación histórica futura: insertar sólo bloques nuevos manteniendo `ultimaFecha`.
- Para mover a producción añadir: autenticar usuarios reales, compresión gzip, CORS estricto, tokens expiran.

---
Si necesitas que adapte el README a solo un idioma o añadir capturas, avísame.
