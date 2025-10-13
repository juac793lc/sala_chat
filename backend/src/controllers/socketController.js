const jwt = require('jsonwebtoken');
const { getJwtSecret } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');
const sqlite = require('../config/sqlite_db');
const pushController = require('./pushController');

// SUPER SIMPLE: Solo variables en memoria para pruebas
const connectedUsers = new Map(); // usuarios conectados ahora
const registeredUsersSet = new Set(); // IDs de usuarios únicos que han usado la app
const markerTimers = new Map(); // timers para auto-eliminación de estrellas
// Ubicaciones en memoria (última por socket)
const userLocations = new Map(); // socketId -> { lat, lng, ts }
// Marcadores activos en memoria para notificaciones por proximidad
const activeMarkers = new Map(); // markerId -> markerData
// Registro de quién ya fue notificado por cada marker
const notifiedForMarker = new Map(); // markerId -> Set(socketId)

// Parámetros de proximidad
const TTL_LOCATION_MS = 60 * 1000; // 60s
const PROXIMITY_RADIUS_METERS = 2000; // 2000m (solicitado)
const MAX_NOTIF_PER_MARKER = 200;
// Auto-remove for stars (50 minutes)
const AUTO_REMOVE_MS = 50 * 60 * 1000; // 50 minutos

// Internal flag to ensure we schedule existing markers only once
let _markersInitialized = false;
// Io instance exposable para que rutas REST puedan emitir
let _ioInstance = null;

function setIoInstance(io) {
  try {
    _ioInstance = io;
    console.log('🔌 setIoInstance OK');
    // Schedule any existing markers now that we have io
    try { scheduleExistingMarkers(io); } catch (e) { console.warn('Could not schedule on setIoInstance:', e.message || e); }
  } catch (e) {
    console.warn('🔌 setIoInstance error:', e.message || e);
  }
}

/**
 * Schedule a single auto-remove timer for a marker using remaining time calculated
 * from its created_at timestamp (createdAtMs). Emits via the provided io instance.
 */
function _scheduleAutoRemove(markerId, createdAtMs, normalizedTipo, io) {
  try {
    const expiresAt = (createdAtMs || Date.now()) + AUTO_REMOVE_MS;
    const remaining = expiresAt - Date.now();

    if (remaining <= 0) {
      // Already expired -> deactivate immediately
      sqlite.deactivateMarker(markerId).then(() => {
        try {
          io && io.emit && io.emit('marker_auto_removed', {
            markerId,
            reason: 'expired',
            message: 'Estrella eliminada automáticamente (50 min)'
          });
        } catch (e) { console.warn('Emit error after immediate deactivate:', e); }
        markerTimers.delete(markerId);
        activeMarkers.delete(markerId);
        notifiedForMarker.delete(markerId);
      }).catch(e => console.error('Error deactivating expired marker on startup:', e));
      return;
    }

    // If there's already a timer, clear it first
    if (markerTimers.has(markerId)) {
      clearTimeout(markerTimers.get(markerId));
      markerTimers.delete(markerId);
    }

    const timer = setTimeout(async () => {
      try {
        await sqlite.deactivateMarker(markerId);
        try {
          io && io.emit && io.emit('marker_auto_removed', {
            markerId: markerId,
            reason: 'expired',
            message: 'Estrella eliminada automáticamente (50 min)'
          });
        } catch (e) { console.warn('Emit error on auto-remove:', e); }

        markerTimers.delete(markerId);
        activeMarkers.delete(markerId);
        notifiedForMarker.delete(markerId);
        console.log(`🗑️ Estrella ${markerId} auto-eliminada por timer (startup/reschedule)`);
      } catch (error) {
        console.error('❌ Error auto-eliminando marcador (timer):', error);
      }
    }, remaining);

    markerTimers.set(markerId, timer);
    console.log(`⏰ (rescheduled) Timer de ${Math.round(remaining/1000)}s para marcador ${markerId} tipo=${normalizedTipo}`);
  } catch (e) {
    console.error('Error scheduling auto-remove for marker:', e);
  }
}

/**
 * Load existing active markers from DB and schedule their auto-remove timers.
 * This should be called once after the server has a valid io instance.
 */
async function scheduleExistingMarkers(io) {
  if (_markersInitialized) return;
  _markersInitialized = true;
  try {
    const markers = await sqlite.getAllActiveMarkers();
    if (!markers || markers.length === 0) return;
    console.log(`🔁 Rescheduling ${markers.length} marker timers from DB`);
    for (const m of markers) {
      const markerId = m.marker_id;
      const createdAtMs = m.created_at_ms || (m.created_at ? Date.parse(m.created_at) : Date.now());
      const tipo = m.tipo_reporte || 'interes';
      // Keep in-memory activeMarkers in sync
      activeMarkers.set(markerId, {
        id: markerId,
        userId: m.user_id,
        username: m.user_nombre,
        latitude: m.latitude,
        longitude: m.longitude,
        tipoReporte: tipo,
        timestamp: createdAtMs,
        expiresAt: createdAtMs + AUTO_REMOVE_MS
      });
      notifiedForMarker.set(markerId, new Set());
      _scheduleAutoRemove(markerId, createdAtMs, tipo, io);
    }
  } catch (e) {
    console.error('❌ Error rescheduling existing markers:', e);
  }
}

// Periodic sweep as a safety net: every minute check DB for expired markers and deactivate them.
setInterval(async () => {
  try {
    const markers = await sqlite.getAllActiveMarkers();
    const now = Date.now();
    for (const m of markers) {
      const createdAtMs = m.created_at_ms || (m.created_at ? Date.parse(m.created_at) : now);
      const expiresAt = createdAtMs + AUTO_REMOVE_MS;
      if (expiresAt <= now) {
        try {
          await sqlite.deactivateMarker(m.marker_id);
          // emit a broadcast if io available via any connected socket - we don't have io here,
          // clients will discover via their next refresh/requests, but we log it.
          console.log(`🧹 Sweep: marker ${m.marker_id} expired and deactivated`);
          markerTimers.delete(m.marker_id);
          activeMarkers.delete(m.marker_id);
          notifiedForMarker.delete(m.marker_id);
        } catch (e) {
          console.warn('Sweep: error deactivating marker', m.marker_id, e.message || e);
        }
      }
    }
  } catch (e) {
    // Non-fatal
    // console.debug('Sweep error:', e.message || e);
  }
}, 60 * 1000);

function haversineMeters(lat1, lon1, lat2, lon2) {
  const toRad = (v) => v * Math.PI / 180;
  const R = 6371000; // Earth radius in meters
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Purga periódica de ubicaciones antiguas
setInterval(() => {
  const now = Date.now();
  for (const [sockId, loc] of userLocations.entries()) {
    if (!loc || (now - loc.ts) > TTL_LOCATION_MS) {
      userLocations.delete(sockId);
    }
  }
}, 30 * 1000);
const simpleBD = {
  users: [],
  messages: []
};

// Autenticar socket - BUSCAR USUARIO REAL DE LA BD
const authenticateSocket = async (socket) => {
  try {
    const token = socket.handshake.auth.token;
    console.log(`🔍 Token recibido: ${token ? 'SÍ' : 'NO'}`);

    if (token) {
      try {
        const decoded = jwt.verify(token, getJwtSecret());
        console.log(`✅ Token decodificado para usuario: ${decoded.userId} (${decoded.username})`);
        registeredUsersSet.add(decoded.userId);
        let user = simpleBD.users.find(u => u.id === decoded.userId);
        if (!user) {
          user = {
            id: decoded.userId,
            username: decoded.username || `User_${decoded.userId}`,
            avatar: `${(decoded.username || 'U').substring(0, 2).toUpperCase()}:#4ECDC4`,
            isOnline: true,
            socketId: socket.id
          };
          simpleBD.users.push(user);
          console.log(`👤 Nuevo usuario registrado: ${user.username} (Total registrados: ${registeredUsersSet.size})`);
        } else {
          user.username = decoded.username || user.username;
          user.isOnline = true;
          user.socketId = socket.id;
          console.log(`👤 Usuario reconectado: ${user.username} (Total registrados: ${registeredUsersSet.size})`);
        }
        return user;
      } catch (err) {
        console.log(`❌ Token inválido: ${err.message}, se conectará como anónimo`);
        // fallthrough to anonymous
      }
    }

    // Si no hay token o es inválido, crear usuario anónimo en desarrollo
    const anonId = `anon_${uuidv4()}`;
    registeredUsersSet.add(anonId);
    const anonUser = {
      id: anonId,
      username: `Anon_${anonId.substring(0,6)}`,
      avatar: `AN:#CCCCCC`,
      isOnline: true,
      socketId: socket.id
    };
    simpleBD.users.push(anonUser);
    console.log(`👤 Conexión anónima creada: ${anonUser.username} (Total registrados: ${registeredUsersSet.size})`);
    return anonUser;
  } catch (error) {
    console.log(`❌ Error auth inesperado: ${error.message}`);
    // En caso extremo, permitir conexión anónima
    const anonId = `anon_${uuidv4()}`;
    registeredUsersSet.add(anonId);
    const anonUser = {
      id: anonId,
      username: `Anon_${anonId.substring(0,6)}`,
      avatar: `AN:#CCCCCC`,
      isOnline: true,
      socketId: socket.id
    };
    simpleBD.users.push(anonUser);
    return anonUser;
  }
};

// Manejar conexión - VERSION SUPER SIMPLE
const handleSocketConnection = async (socket, io) => {
  try {
    // Autenticar
    const user = await authenticateSocket(socket);
    // On first connection, reschedule any existing markers from DB
    try { scheduleExistingMarkers(io); } catch (e) { console.warn('Could not schedule existing markers:', e.message || e); }
    
    // Agregar a conectados
    connectedUsers.set(socket.id, user);
    
    // Unirse a sala general y proyecto
    socket.join('sala-general');
    socket.join('proyecto_x');
    socket.join('general'); // Añadir sala 'general' que usa el frontend
    
    console.log(`🎉 ÉXITO: ${user.username} conectado por Socket.IO`);
    console.log(`🏠 ${user.username} se unió automáticamente a salas: sala-general, proyecto_x, general`);
    
    // Notificar éxito al cliente
    socket.emit('auth_success', { 
      message: 'Socket conectado exitosamente',
      user: user 
    });

    // Notificar a otros usuarios del proyecto con contadores actualizados
    const totalConnected = connectedUsers.size;
    const totalRegistered = registeredUsersSet.size;
    
    socket.to('proyecto_x').emit('user_online', {
      userId: user.id,
      username: user.username,
      totalConnected: totalConnected,
      totalRegistered: totalRegistered
    });
    
    // También notificar al propio usuario
    socket.emit('user_online', {
      userId: user.id,
      username: user.username,
      totalConnected: totalConnected,
      totalRegistered: totalRegistered
    });

    // === EVENTOS SIMPLES ===
    
    // Mensaje simple
    socket.on('send_message', (data) => {
      try {
        const { content, roomId = 'sala-general', mediaId, type } = data;
        const messageId = uuidv4();
        const nowIso = new Date().toISOString();

        // Persistir en SQLite
        sqlite.insertMessage({
          message_id: messageId,
          room_id: roomId,
          user_id: user.id,
          user_nombre: user.username,
          text: content || '',
          media_id: mediaId || null,
        }).then(async () => {
          console.log('✅ Mensaje guardado en SQLite:', messageId);
          // Contar comentarios después de guardar
          const comentariosTexto = await sqlite.countComentariosTexto(roomId);
          const comentariosAudio = await sqlite.countComentariosAudio(roomId);
          io.emit('comentarios_actualizados', {
            contenidoId: roomId,
            comentariosTexto,
            comentariosAudio
          });
        }).catch(dbErr => {
          console.error('⚠️ Error guardando mensaje en SQLite:', dbErr.message);
        });

        const message = {
          id: messageId,
          content: content,
          type: mediaId ? 'audio' : (type || 'text'), // estandarizar a 'audio' si trae mediaId
          mediaId: mediaId || null,
          fileUrl: null, // se completa si es audio
          durationSeconds: null,
          sender: {
            id: user.id,
            username: user.username,
            avatar: user.avatar
          },
          roomId: roomId,
          reactions: [],
          readBy: [],
          isDeleted: false,
          createdAt: nowIso,
          updatedAt: nowIso
        };

        // Si es un mensaje con media/audio, intentar enriquecer con datos de la tabla media
        if (mediaId) {
          sqlite.getMediaByMediaId(mediaId).then(mediaRow => {
            if (mediaRow) {
              // Normalizar tipo: si la media es audio, forzar message.type = 'audio'
              if (mediaRow.tipo === 'audio') {
                message.type = 'audio';
              }
              message.fileUrl = mediaRow.url || null;
              message.durationSeconds = mediaRow.duration_seconds || null;
            } else {
              console.warn(`⚠️ Media no encontrada todavía (mediaId=${mediaId}) al emitir new_message`);
            }
            io.to(roomId).emit('new_message', message);
          }).catch(err => {
            console.error('⚠️ Error obteniendo media para mensaje:', err.message);
            io.to(roomId).emit('new_message', message); // emitir sin enriquecer
          });
          return; // evitar doble emisión
        }

        console.log(`📤 ${user.username} (${roomId}): ${content || '[media]'}${mediaId ? ' mediaId=' + mediaId : ''}`);

        io.to(roomId).emit('new_message', message);
      } catch (err) {
        console.error('❌ Error en send_message:', err);
        socket.emit('error_message', { error: 'No se pudo enviar el mensaje' });
      }
    });

    // Nuevo contenido multimedia (evento de la app mobile/legacy)
    socket.on('nuevo_contenido', async (data) => {
      try {
        console.log(`🖼️ ${user.username} compartió nuevo contenido (raw tipo='${data.tipo}')`);

        // Normalizar tipo a valores esperados: image|video|audio
        const rawTipo = (data.tipo || '').toString().toLowerCase();
        let tipo = 'image';
        if (rawTipo.contains?.('video') || rawTipo.includes('video')) tipo = 'video';
        else if (rawTipo.contains?.('audio') || rawTipo.includes('audio')) tipo = 'audio';

        // Asegurar ID estable: el cliente manda 'id'; si no, generar uno (uuid)
        const mediaId = data.id || uuidv4();
        const roomId = data.roomId || 'proyecto_x';
        const nowIso = new Date().toISOString();

        // Insertar en SQLite (si ya existe ignorar error UNIQUE)
        try {
          await sqlite.insertMedia({
            media_id: mediaId,
            room_id: roomId,
            user_id: user.id,
            tipo: tipo,
            url: data.url || '',
            mime: data.mime || null,
            size_bytes: data.size_bytes || null,
            duration_seconds: data.duracionSegundos || data.duration_seconds || null,
            original_name: data.originalName || data.fileName || null,
          });
          console.log(`💾 Media persistida en SQLite: ${mediaId}`);
        } catch (persistErr) {
          console.warn(`⚠️ No se pudo insertar media (puede ser duplicado) media_id=${mediaId}: ${persistErr.message}`);
        }

        // Payload unificado que esperan los clientes Flutter
        const contenidoCompleto = {
          id: mediaId, // cliente usa id
          mediaId: mediaId,
          autorNombre: user.username,
          autorId: user.id,
          tipo: tipo, // cliente hace contains('video'|'audio')
          url: data.url || '',
          fechaCreacion: nowIso,
          comentariosTexto: data.comentariosTexto || 0,
            comentariosAudio: data.comentariosAudio || 0,
          duracionSegundos: data.duracionSegundos || data.duration_seconds || 0,
          roomId: roomId,
        };

        // Emitir a TODOS (incluyendo emisor) para unificar vía socket (cliente hará dedupe contra su inserción optimista)
        io.to(roomId).emit('nuevo_contenido', contenidoCompleto);
      } catch (e) {
        console.error('❌ Error procesando nuevo_contenido:', e);
        socket.emit('error_message', { error: 'No se pudo procesar el contenido multimedia' });
      }
    });

    // Nuevo multimedia (evento específico para feed compartido)
    socket.on('nuevo_multimedia', async (data) => {
      try {
        const { roomId, contenido } = data;
        console.log(`📸 ${user.username} compartió multimedia en sala ${roomId}`);
        console.log(`📋 Datos recibidos:`, JSON.stringify(data, null, 2));

        // Validar datos requeridos
        if (!contenido || !contenido.id) {
          console.error('❌ Error: Contenido multimedia inválido', { contenido });
          throw new Error('Contenido multimedia inválido');
        }

        const mediaId = contenido.id;
        const tipo = contenido.tipo || 'imagen';
        const nowIso = contenido.fechaCreacion || new Date().toISOString();

        // Intentar persistir en SQLite (si ya existe, ignorar)
        try {
          await sqlite.insertMedia({
            media_id: mediaId,
            room_id: roomId || 'general',
            user_id: contenido.autorId || user.id,
            user_nombre: contenido.autorNombre || user.username,
            tipo: tipo === 'imagen' ? 'image' : tipo,
            url: contenido.url || '',
            mime: null,
            size_bytes: null,
            duration_seconds: contenido.duracionSegundos || 0,
            original_name: null,
          });
          console.log(`💾 Multimedia persistido en SQLite: ${mediaId}`);
        } catch (persistErr) {
          console.warn(`⚠️ No se pudo insertar multimedia (puede ser duplicado): ${persistErr.message}`);
        }

        // Reenviar a todos los usuarios en la sala
        const targetRoom = roomId || 'general';
        console.log(`📡 Emitiendo multimedia_compartido a sala: ${targetRoom}`);
        console.log(`👥 Usuarios en sala ${targetRoom}:`, io.sockets.adapter.rooms.get(targetRoom)?.size || 0);
        
        io.to(targetRoom).emit('multimedia_compartido', {
          id: mediaId,
          autorId: contenido.autorId || user.id,
          autorNombre: contenido.autorNombre || user.username,
          tipo: tipo,
          url: contenido.url || '',
          fechaCreacion: nowIso,
          duracionSegundos: contenido.duracionSegundos || 0,
          roomId: targetRoom,
        });
        
        console.log(`✅ Multimedia enviado a ${io.sockets.adapter.rooms.get(targetRoom)?.size || 0} usuarios`);

      } catch (e) {
        console.error('❌ Error procesando nuevo_multimedia:', e);
        socket.emit('error_message', { error: 'No se pudo procesar el multimedia' });
      }
    });

    // Unirse a sala específica
    socket.on('join_room', async (data) => {
      const { roomId } = data;
      socket.join(roomId);
      console.log(`🏠 ${user.username} se unió a sala: ${roomId}`);
      
      // Contadores: sala actual vs totales
      const roomSize = io.sockets.adapter.rooms.get(roomId)?.size || 0;
      const totalConnected = connectedUsers.size;
      const totalRegistered = registeredUsersSet.size;
      
      socket.emit('joined_room', {
        roomId: roomId,
        roomName: roomId === 'proyecto_x' ? 'Proyecto X 🚀' : roomId,
        roomSubscribers: roomSize,
        totalConnected: totalConnected,
        totalRegistered: totalRegistered
      });

      // Si es la sala del proyecto o general, enviar todo el historial de contenido
      if (roomId === 'proyecto_x' || roomId === 'general') {
        try {
          // Obtener desde SQLite (orden DESC ya aplicado en listMedia)
          const mediaRows = await sqlite.listMedia(roomId, 200, 0);
          // Enriquecer cada media con contadores de comentarios
          const historialContenido = await Promise.all(mediaRows.map(async (m) => {
            try {
              const comentariosTexto = await sqlite.countComentariosTexto(m.media_id || m.id || m.mediaId || '');
              const comentariosAudio = await sqlite.countComentariosAudio(m.media_id || m.id || m.mediaId || '');
              return {
                id: m.media_id,
                mediaId: m.media_id,
                autorId: m.user_id || '0',
                autorNombre: m.user_nombre || `User_${m.user_id || '0'}`,
                tipo: m.tipo || 'image',
                url: m.url || '',
                fechaCreacion: m.created_at,
                comentariosTexto: comentariosTexto || 0,
                comentariosAudio: comentariosAudio || 0,
                duracionSegundos: m.duration_seconds || 0,
                roomId: m.room_id,
              };
            } catch (e) {
              return {
                id: m.media_id,
                mediaId: m.media_id,
                autorId: m.user_id || '0',
                autorNombre: m.user_nombre || `User_${m.user_id || '0'}`,
                tipo: m.tipo || 'image',
                url: m.url || '',
                fechaCreacion: m.created_at,
                comentariosTexto: 0,
                comentariosAudio: 0,
                duracionSegundos: m.duration_seconds || 0,
                roomId: m.room_id,
              };
            }
          }));
          socket.emit('historial_contenido', historialContenido);
          console.log(`📚 Historial(SQLite) enviado a ${user.username}: ${historialContenido.length} elementos`);
        } catch (histErr) {
          console.error('⚠️ Error obteniendo historial desde SQLite, fallback memory_db:', histErr.message);
          try {
            const db = require('../config/memory_db');
            const fallback = await db.obtenerTodoElContenido();
            socket.emit('historial_contenido', fallback);
            console.log(`📚 Historial(fallback memory) enviado a ${user.username}: ${fallback.length} elementos`);
          } catch (inner) {
            console.error('❌ Error también en fallback de historial:', inner);
          }
        }
      }
    });

    // Salir de sala específica
    socket.on('leave_room', (data) => {
      const { roomId } = data;
      socket.leave(roomId);
      console.log(`🚪 ${user.username} salió de sala: ${roomId}`);
    });

    // Evento para agregar marcador al mapa
    socket.on('add_marker', async (data) => {
      console.log(`🗺️ Nuevo marcador de ${user.username}:`, data);
      
      const markerId = uuidv4();
      // Normalizar tipo: aceptar 'policia' legado como 'interes'
      const rawTipo = data.tipoReporte;
      const normalizedTipo = rawTipo === 'policia' ? 'interes' : rawTipo;

      const markerData = {
        id: markerId,
        userId: user.id,
        username: user.username,
        latitude: data.latitude,
        longitude: data.longitude,
        tipoReporte: normalizedTipo,
        timestamp: Date.now(),
        expiresAt: Date.now() + AUTO_REMOVE_MS
      };

      // Initialize confirmation counters
      markerData.confirms = 0;
      markerData.denies = 0;

      // Normalized lower-case tipo for later checks
      const tipoLower = (normalizedTipo || '').toString().toLowerCase();

      try {
        // Guardar en base de datos
        await sqlite.insertMarker({
          marker_id: markerId,
          user_id: user.id,
          user_nombre: user.username,
          latitude: data.latitude,
          longitude: data.longitude,
          tipo_reporte: normalizedTipo
        });
        
        // Mantener marker activo en memoria para notificaciones por proximidad
        activeMarkers.set(markerId, markerData);
        notifiedForMarker.set(markerId, new Set());

        // Notificar inmediatamente a sockets que tienen ubicación reciente y estén dentro del radio
        try {
          const now = Date.now();
          const notifiedSet = notifiedForMarker.get(markerId) || new Set();
          for (const [sockId, loc] of userLocations.entries()) {
            if (!loc) continue;
            if ((now - loc.ts) > TTL_LOCATION_MS) continue; // ubicación vieja
            if (notifiedSet.size >= MAX_NOTIF_PER_MARKER) break;
            const d = haversineMeters(markerData.latitude, markerData.longitude, loc.lat, loc.lng);
            if (d <= PROXIMITY_RADIUS_METERS) {
              // emitir notificación al socket (con mensaje legible)
              try {
                const distRound = Math.round(d);
                console.log(`📣 Enviando map_notification a socket=${sockId} (dist=${distRound}m)`);
                io.to(sockId).emit('map_notification', {
                  notificationId: uuidv4(),
                  type: 'marker',
                  marker: markerData,
                  distanceMeters: distRound,
                  message: `Estrella activa • ${distRound} m`
                });
                notifiedSet.add(sockId);
              } catch (emitErr) {
                console.warn('⚠️ Error emitiendo map_notification a', sockId, emitErr.message || emitErr);
              }
            }
          }
          notifiedForMarker.set(markerId, notifiedSet);
        } catch (notifyErr) {
          console.error('❌ Error en notificación inicial de proximidad:', notifyErr);
        }

        // Enviar Web-Push a TODAS las suscripciones registradas sólo para estrellas ('interes')
        try {
          if (tipoLower === 'interes') {
            const subs = await sqlite.listPushSubscriptionsNear();
            if (subs && subs.length > 0) {
              const rebuilt = subs.map(s => ({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }));
              const title = '⭐ Estrella activa';
              const body = `⭐ ${markerData.username} creó una estrella`;
              const payload = { title: title, body: body, marker: markerData, timestamp: Date.now() };
              // Enviar sin bloquear la ruta principal
              pushController.sendPushToSubscriptions(rebuilt, payload).then(results => {
                console.log(`📬 Push enviados a todos los suscriptores: ${results.length}`);
              }).catch(e => console.warn('⚠️ Error enviando pushes a todos:', e.message || e));
            } else {
              console.log('ℹ️ No hay suscripciones registradas para enviar push');
            }
          } else {
            // No enviar push global para marcadores no-dinámicos
            // (los sockets cercanos ya reciben 'map_notification' por proximidad si aplica)
          }
        } catch (pushErr) {
          console.error('❌ Error intentando enviar Web-Push a todos:', pushErr.message || pushErr);
        }

        // Enviar a todos los usuarios conectados (incluyendo el que lo creó)
        try {
          const publicMarker = {
            id: markerId,
            userId: markerData.userId,
            username: markerData.username,
            latitude: markerData.latitude,
            longitude: markerData.longitude,
            tipoReporte: markerData.tipoReporte,
            timestamp: markerData.timestamp || Date.now(),
            expiresAt: markerData.expiresAt || ((markerData.timestamp || Date.now()) + AUTO_REMOVE_MS),
            confirms: markerData.confirms || 0,
            denies: markerData.denies || 0
          };
          console.log('📡 Emitting marker_added (restore):', JSON.stringify(publicMarker));
          // Prefer module-wide _ioInstance if available
          try {
            const emitter = _ioInstance || io;
            emitter && emitter.emit && emitter.emit('marker_added', publicMarker);
          } catch (emitErr) {
            io.emit('marker_added', publicMarker);
          }
        } catch (e) {
          // Fallback: broadcast original marker data
          socket.broadcast.emit('marker_added', markerData);
          socket.emit('marker_added', markerData);
        }
        
        console.log(`✅ Marcador ${markerId} guardado en BD`);
        
  // Si es estrella (policia/interes/estrella), configurar auto-eliminación en 50 minutos
  if (tipoLower === 'interes' || tipoLower === 'policia' || tipoLower === 'estrella') {
          const timer = setTimeout(async () => {
            try {
              // Auto-eliminar de la base de datos
              await sqlite.deactivateMarker(markerId);
              
              // Notificar a todos los usuarios conectados
              socket.broadcast.emit('marker_auto_removed', {
                markerId: markerId,
                reason: 'expired',
                message: 'Estrella eliminada automáticamente (50 min)'
              });
              socket.emit('marker_auto_removed', {
                markerId: markerId,
                reason: 'expired',
                message: 'Estrella eliminada automáticamente (50 min)'
              });
              
              // Limpiar timer del mapa
              markerTimers.delete(markerId);
              // limpiar estructuras de notificación
              activeMarkers.delete(markerId);
              notifiedForMarker.delete(markerId);
              
              console.log(`🗑️ Estrella ${markerId} auto-eliminada después de 50 min`);
            } catch (error) {
              console.error('❌ Error auto-eliminando marcador:', error);
            }
          }, AUTO_REMOVE_MS); // 50 minutos (const AUTO_REMOVE_MS)
          
          // Guardar referencia del timer
          markerTimers.set(markerId, timer);
          console.log(`⏰ Timer de 50min configurado para marcador ${markerId} tipo=${normalizedTipo}`);
        }
      } catch (error) {
        console.error('❌ Error guardando marcador:', error);
        socket.emit('marker_error', { message: 'Error guardando marcador' });
      }
    });

    // Handler para que cliente actualice su ubicación (opt-in)
    socket.on('update_location', (data) => {
      try {
        if (!data || typeof data.lat !== 'number' || typeof data.lng !== 'number') return;
        const ts = data.ts ? Date.parse(data.ts) : Date.now();
        userLocations.set(socket.id, { lat: data.lat, lng: data.lng, ts: ts });

        // Si hay marcadores activos en la sala, notificar a este socket si aplica
        const now = Date.now();
        for (const [markerId, marker] of activeMarkers.entries()) {
          // evitar notificar si ya fue notificado
          const notifiedSet = notifiedForMarker.get(markerId) || new Set();
          if (notifiedSet.has(socket.id)) continue;
          if ((now - ts) > TTL_LOCATION_MS) continue; // ubicación vieja
          const d = haversineMeters(marker.latitude, marker.longitude, data.lat, data.lng);
          if (d <= PROXIMITY_RADIUS_METERS) {
            const distRound = Math.round(d);
            console.log(`📣 Enviando map_notification a socket=${socket.id} (dist=${distRound}m) por update_location`);
            io.to(socket.id).emit('map_notification', {
              notificationId: uuidv4(),
              type: 'marker',
              marker: marker,
              distanceMeters: distRound,
              message: `Estrella activa • ${distRound} m`
            });
            notifiedSet.add(socket.id);
            notifiedForMarker.set(markerId, notifiedSet);
          }
        }
      } catch (err) {
        console.error('⚠️ Error en update_location:', err.message || err);
      }
    });

    // Evento para eliminar marcador del mapa
    socket.on('remove_marker', async (data) => {
      console.log(`🗑️ Eliminar marcador ${data.markerId} por ${user.username}`);
      
      try {
        // Desactivar en base de datos (no eliminar, solo marcar como inactivo)
        await sqlite.deactivateMarker(data.markerId);
        
        // Cancelar timer de auto-eliminación si existe
        if (markerTimers.has(data.markerId)) {
          clearTimeout(markerTimers.get(data.markerId));
          markerTimers.delete(data.markerId);
          console.log(`⏰ Timer cancelado para marcador ${data.markerId}`);
        }
        
        // Enviar a todos los usuarios conectados
        socket.broadcast.emit('marker_removed', {
          markerId: data.markerId,
          userId: user.id,
          username: user.username
        });
        socket.emit('marker_remove_confirmed', {
          markerId: data.markerId
        });
        
        console.log(`✅ Marcador ${data.markerId} desactivado en BD`);
      } catch (error) {
        console.error('❌ Error eliminando marcador:', error);
      }
    });

    // Solicitar marcadores existentes al conectarse
    socket.on('request_existing_markers', async () => {
      try {
        console.log(`📍 Cargando marcadores existentes para ${user.username}`);
        
        const markers = await sqlite.getAllActiveMarkers();
        const formattedMarkers = markers.map(marker => ({
          id: marker.marker_id,
          userId: marker.user_id,
          username: marker.user_nombre,
          latitude: marker.latitude,
          longitude: marker.longitude,
          tipoReporte: marker.tipo_reporte,
          // Preferir valor en ms calculado por la query; fallback a parse
          timestamp: marker.created_at_ms || new Date(marker.created_at).getTime(),
          expiresAt: (marker.created_at_ms || new Date(marker.created_at).getTime()) + AUTO_REMOVE_MS
        }));
        
        socket.emit('existing_markers', formattedMarkers);
        console.log(`✅ Enviados ${formattedMarkers.length} marcadores existentes`);
      } catch (error) {
        console.error('❌ Error cargando marcadores:', error);
        socket.emit('existing_markers', []);
      }
    });

    // Desconexión
    socket.on('disconnect', () => {
      console.log(`👋 ${user.username} desconectado`);
      connectedUsers.delete(socket.id);
      
      // Notificar a otros usuarios del proyecto con contadores actualizados
      const totalConnected = connectedUsers.size;
      const totalRegistered = registeredUsersSet.size;
      
      socket.to('proyecto_x').emit('user_offline', {
        userId: user.id,
        username: user.username,
        totalConnected: totalConnected,
        totalRegistered: totalRegistered
      });
      
      // Actualizar estado
      if (user) {
        user.isOnline = false;
      }
      
      socket.broadcast.emit('user_offline', {
        userId: user.id,
        username: user.username,
        totalConnected: totalConnected,
        totalRegistered: totalRegistered
      });
    });

  } catch (error) {
    console.log(`❌ Error conexión socket: ${error.message}`);
    socket.emit('auth_error', { message: 'Token inválido' });
    socket.disconnect();
  }
};

module.exports = {
  handleSocketConnection,
  connectedUsers,
  setIoInstance,
  scheduleExistingMarkers,
  confirmMarkerByUser,
  denyMarkerByUser
};

// Exponer funciones para llamadas REST (confirm / deny desde HTTP)
async function confirmMarkerByUser(markerId, userId) {
  try {
    if (!markerId) return { success: false, error: 'markerId missing' };
    const marker = activeMarkers.get(markerId);
    if (!marker) return { success: false, error: 'Marker not found' };
    marker.confirms = (marker.confirms || 0) + 1;
    activeMarkers.set(markerId, marker);
    try {
      const emitter = _ioInstance || null;
      if (emitter && emitter.emit) {
        emitter.emit('marker_confirmed', {
          markerId,
          userId,
          confirms: marker.confirms || 0,
          denies: marker.denies || 0
        });
      }
    } catch (e) { console.warn('Emit confirm error:', e.message || e); }
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message || e };
  }
}

async function denyMarkerByUser(markerId, userId) {
  try {
    if (!markerId) return { success: false, error: 'markerId missing' };
    const marker = activeMarkers.get(markerId);
    if (!marker) return { success: false, error: 'Marker not found' };
    marker.denies = (marker.denies || 0) + 1;
    activeMarkers.set(markerId, marker);
    try {
      const emitter = _ioInstance || null;
      if (emitter && emitter.emit) {
        // reuse 'marker_updated' to notify clients of new denies count
        emitter.emit('marker_updated', {
          markerId,
          userId,
          confirms: marker.confirms || 0,
          denies: marker.denies || 0
        });
      }
    } catch (e) { console.warn('Emit deny error:', e.message || e); }
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message || e };
  }
}