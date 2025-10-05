const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const sqlite = require('../config/sqlite_db');

// SUPER SIMPLE: Solo variables en memoria para pruebas
const connectedUsers = new Map();
const simpleBD = {
  users: [],
  messages: []
};

// Autenticar socket - VERSION SUPER SIMPLE
const authenticateSocket = async (socket) => {
  try {
    const token = socket.handshake.auth.token;
    console.log(`🔍 Token recibido: ${token ? 'SÍ' : 'NO'}`);
    
    if (!token) {
      throw new Error('No token provided');
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    console.log(`✅ Token decodificado para usuario: ${decoded.userId}`);
    
    // Buscar o crear usuario simple
    let user = simpleBD.users.find(u => u.id === decoded.userId);
    if (!user) {
      user = {
        id: decoded.userId,
        username: `User_${decoded.userId}`,
        avatar: 'U:#4ECDC4',
        isOnline: true,
        socketId: socket.id
      };
      simpleBD.users.push(user);
      console.log(`👤 Nuevo usuario creado: ${user.username}`);
    } else {
      user.isOnline = true;
      user.socketId = socket.id;
      console.log(`👤 Usuario reconectado: ${user.username}`);
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
    
    console.log(`🎉 ÉXITO: ${user.username} conectado por Socket.IO`);
    
    // Notificar éxito al cliente
    socket.emit('auth_success', { 
      message: 'Socket conectado exitosamente',
      user: user 
    });

    // Notificar a otros usuarios del proyecto
    socket.to('proyecto_x').emit('user_online', {
      userId: user.id,
      username: user.username
    });

    // === EVENTOS SIMPLES ===
    
    // Mensaje simple
    socket.on('send_message', (data) => {
      try {
        const { content, roomId = 'sala-general', mediaId } = data;
        const messageId = uuidv4();
        const nowIso = new Date().toISOString();

        // Persistir en SQLite
        sqlite.insertMessage({
          message_id: messageId,
          room_id: roomId,
          user_id: user.id,
          text: content || '',
          media_id: mediaId || null,
        }).then(() => {
          console.log('✅ Mensaje guardado en SQLite:', messageId);
        }).catch(dbErr => {
          console.error('⚠️ Error guardando mensaje en SQLite:', dbErr.message);
        });

        const message = {
          id: messageId,
          content: content,
          type: mediaId ? 'media' : 'text',
          mediaId: mediaId || null,
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

        console.log(`📤 ${user.username} (${roomId}): ${content || '[media]'}${mediaId ? ' mediaId=' + mediaId : ''}`);

        io.to(roomId).emit('new_message', message);
      } catch (err) {
        console.error('❌ Error en send_message:', err);
        socket.emit('error_message', { error: 'No se pudo enviar el mensaje' });
      }
    });

    // Nuevo contenido multimedia para Proyecto X
    socket.on('nuevo_contenido', async (data) => {
      console.log(`🖼️ ${user.username} compartió nuevo contenido: ${data.tipo}`);
      
      const contenidoCompleto = {
        ...data,
        autorNombre: user.username,
        autorId: user.id,
      };

      // Guardar en base de datos
      const db = require('../config/memory_db');
      await db.agregarContenido(contenidoCompleto);
      
      // Reenviar a todos en la sala del proyecto (excepto al emisor)
      socket.to('proyecto_x').emit('nuevo_contenido', contenidoCompleto);
    });

    // Unirse a sala específica
    socket.on('join_room', async (data) => {
      const { roomId } = data;
      socket.join(roomId);
      console.log(`🏠 ${user.username} se unió a sala: ${roomId}`);
      
      socket.emit('joined_room', {
        roomId: roomId,
        roomName: roomId === 'proyecto_x' ? 'Proyecto X 🚀' : roomId
      });

      // Si es la sala del proyecto, enviar todo el historial de contenido
      if (roomId === 'proyecto_x') {
        const db = require('../config/memory_db');
        const historialContenido = await db.obtenerTodoElContenido();
        socket.emit('historial_contenido', historialContenido);
        console.log(`📚 Historial enviado a ${user.username}: ${historialContenido.length} elementos`);
      }
    });

    // Salir de sala específica
    socket.on('leave_room', (data) => {
      const { roomId } = data;
      socket.leave(roomId);
      console.log(`🚪 ${user.username} salió de sala: ${roomId}`);
    });

    // Desconexión
    socket.on('disconnect', () => {
      console.log(`👋 ${user.username} desconectado`);
      connectedUsers.delete(socket.id);
      
      // Notificar a otros usuarios del proyecto
      socket.to('proyecto_x').emit('user_offline', {
        userId: user.id,
        username: user.username
      });
      
      // Actualizar estado
      if (user) {
        user.isOnline = false;
      }
      
      socket.broadcast.emit('user_offline', {
        userId: user.id,
        username: user.username
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