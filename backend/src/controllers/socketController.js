const jwt = require('jsonwebtoken');
const { getJwtSecret } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');
const sqlite = require('../config/sqlite_db');

// SUPER SIMPLE: Solo variables en memoria para pruebas
const connectedUsers = new Map(); // usuarios conectados ahora
const registeredUsersSet = new Set(); // IDs de usuarios únicos que han usado la app
const markerTimers = new Map(); // timers para auto-eliminación de estrellas
const simpleBD = {
  users: [],
  messages: []
};

// Autenticar socket - BUSCAR USUARIO REAL DE LA BD
const authenticateSocket = async (socket) => {
  try {
    const token = socket.handshake.auth.token;
    console.log(`🔍 Token recibido: ${token ? 'SÍ' : 'NO'}`);
    
    if (!token) {
      throw new Error('No token provided');
    }

  const decoded = jwt.verify(token, getJwtSecret());
    console.log(`✅ Token decodificado para usuario: ${decoded.userId} (${decoded.username})`);
    
    // Registrar usuario único (acumula total de usuarios con la app)
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
      // Actualizar con nombre del token
      user.username = decoded.username || user.username;
      user.isOnline = true;
      user.socketId = socket.id;
      console.log(`👤 Usuario reconectado: ${user.username} (Total registrados: ${registeredUsersSet.size})`);
    }
    
    return user;
  } catch (error) {
    console.log(`❌ Error auth: ${error.message}`);
    throw new Error('Token inválido');
  }
};

// Manejar conexión - VERSION SUPER SIMPLE
const handleSocketConnection = async (socket, io) => {
  try {
    // Autenticar
    const user = await authenticateSocket(socket);
    
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
          const historialContenido = mediaRows.map(m => ({
            id: m.media_id,
            mediaId: m.media_id,
            autorId: m.user_id || '0',
            autorNombre: `User_${m.user_id || '0'}`, // placeholder; podría resolverse si hubiera tabla usuarios
            tipo: m.tipo || 'image',
            url: m.url || '',
            fechaCreacion: m.created_at,
            comentariosTexto: 0,
            comentariosAudio: 0,
            duracionSegundos: m.duration_seconds || 0,
            roomId: m.room_id,
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
        timestamp: Date.now()
      };

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
        
        // Enviar a todos los usuarios conectados (incluyendo el que lo creó)
        socket.broadcast.emit('marker_added', markerData);
        socket.emit('marker_confirmed', markerData);
        
        console.log(`✅ Marcador ${markerId} guardado en BD`);
        
        // Si es estrella (policia), configurar auto-eliminación en 50 minutos
  if (normalizedTipo === 'interes') {
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
              
              console.log(`🗑️ Estrella ${markerId} auto-eliminada después de 50 min`);
            } catch (error) {
              console.error('❌ Error auto-eliminando marcador:', error);
            }
          }, 50 * 60 * 1000); // 50 minutos
          
          // Guardar referencia del timer
          markerTimers.set(markerId, timer);
          console.log(`⏰ Timer de 50min configurado para estrella ${markerId}`);
        }
      } catch (error) {
        console.error('❌ Error guardando marcador:', error);
        socket.emit('marker_error', { message: 'Error guardando marcador' });
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
          timestamp: marker.created_at_ms || new Date(marker.created_at).getTime()
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
  connectedUsers
};