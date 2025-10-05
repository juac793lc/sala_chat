// Almacenamiento en memoria para desarrollo/pruebas
class InMemoryDB {
  constructor() {
    this.users = new Map();
    this.rooms = new Map();
    this.messages = new Map();
    this.contenidoMultimedia = []; // Almacenar contenido multimedia del proyecto
    this.userCounter = 1;
    this.roomCounter = 1;
    this.messageCounter = 1;
    this.contenidoCounter = 1;

    // Crear sala por defecto
    this.createDefaultRoom();
  }

  createDefaultRoom() {
    // Sala General del Proyecto
    const proyectoGeneral = {
      _id: 'room_1',
      name: '💼 Proyecto - General',
      description: 'Sala principal del proyecto de chat grupal',
      type: 'public',
      creator: null,
      members: [],
      settings: {
        allowFileSharing: true,
        allowVoiceMessages: true,
        maxMembers: 100
      },
      lastActivity: new Date(),
      createdAt: new Date()
    };

    // Sala de Texto del Proyecto
    const proyectoTexto = {
      _id: 'room_texto',
      name: '📝 Proyecto - Texto',
      description: 'Sala para comentarios de texto del proyecto',
      type: 'public',
      creator: null,
      members: [],
      settings: {
        allowFileSharing: true,
        allowVoiceMessages: false,
        maxMembers: 50
      },
      lastActivity: new Date(),
      createdAt: new Date()
    };

    // Sala de Audio del Proyecto
    const proyectoAudio = {
      _id: 'room_audio',
      name: '🎤 Proyecto - Audio',
      description: 'Sala para comentarios de audio del proyecto',
      type: 'public',
      creator: null,
      members: [],
      settings: {
        allowFileSharing: false,
        allowVoiceMessages: true,
        maxMembers: 50
      },
      lastActivity: new Date(),
      createdAt: new Date()
    };

    this.rooms.set('room_1', proyectoGeneral);
    this.rooms.set('room_texto', proyectoTexto);
    this.rooms.set('room_audio', proyectoAudio);
    
    console.log('✅ Salas del proyecto creadas: General, Texto y Audio');
  }

  // === USUARIOS ===
  
  async createUser(userData) {
    const id = `user_${this.userCounter++}`;
    const user = {
      _id: id,
      username: userData.username,
      avatar: this._generateAvatar(userData.username),
      isOnline: true,
      lastSeen: new Date(),
      socketId: '',
      joinedRooms: ['room_1'], // Unir automáticamente a sala general
      createdAt: new Date(),
      updatedAt: new Date()
    };

    this.users.set(id, user);

    // Agregar a sala general
    const generalRoom = this.rooms.get('room_1');
    if (generalRoom) {
      generalRoom.members.push({
        user: id,
        joinedAt: new Date(),
        role: 'member'
      });
    }

    return { ...user, id };
  }

  async findUserByUsername(username) {
    for (const user of this.users.values()) {
      if (user.username === username) {
        return { ...user, id: user._id };
      }
    }
    return null;
  }

  async findUserById(id) {
    const user = this.users.get(id);
    return user ? { ...user, id: user._id } : null;
  }

  async updateUser(id, updates) {
    const user = this.users.get(id);
    if (user) {
      Object.assign(user, updates, { updatedAt: new Date() });
      return { ...user, id: user._id };
    }
    return null;
  }

  async getOnlineUsers() {
    const onlineUsers = Array.from(this.users.values())
      .filter(user => user.isOnline)
      .map(user => ({ ...user, id: user._id }));
    return onlineUsers;
  }

  // === SALAS ===

  async findRoomById(id) {
    const room = this.rooms.get(id);
    return room ? { ...room, id: room._id } : null;
  }

  async getPublicRooms() {
    const publicRooms = Array.from(this.rooms.values())
      .filter(room => room.type === 'public')
      .map(room => ({ ...room, id: room._id, memberCount: room.members.length }));
    return publicRooms;
  }

  async getUserRooms(userId) {
    const userRooms = Array.from(this.rooms.values())
      .filter(room => room.members.some(member => member.user === userId))
      .map(room => ({ ...room, id: room._id, memberCount: room.members.length }));
    return userRooms;
  }

  // === MENSAJES ===

  async createMessage(messageData) {
    const id = `msg_${this.messageCounter++}`;
    const message = {
      _id: id,
      content: messageData.content || '',
      type: messageData.type || 'text',
      sender: messageData.sender,
      room: messageData.room,
      fileUrl: messageData.fileUrl,
      fileName: messageData.fileName,
      fileSize: messageData.fileSize,
      mimeType: messageData.mimeType,
      replyTo: messageData.replyTo,
      reactions: [],
      readBy: [],
      editedAt: null,
      isDeleted: false,
      createdAt: new Date(),
      updatedAt: new Date()
    };

    if (!this.messages.has(messageData.room)) {
      this.messages.set(messageData.room, []);
    }

    this.messages.get(messageData.room).push(message);

    // Actualizar actividad de la sala
    const room = this.rooms.get(messageData.room);
    if (room) {
      room.lastActivity = new Date();
    }

    return { ...message, id };
  }

  async getRoomMessages(roomId, limit = 50) {
    const roomMessages = this.messages.get(roomId) || [];
    
    return roomMessages
      .slice(-limit) // Últimos N mensajes
      .map(msg => ({ ...msg, id: msg._id }));
  }

  // === CONTENIDO MULTIMEDIA ===

  async agregarContenido(contenido) {
    const nuevoContenido = {
      id: `contenido_${this.contenidoCounter++}`,
      ...contenido,
      fechaCreacion: new Date().toISOString(),
    };
    
    this.contenidoMultimedia.unshift(nuevoContenido); // Agregar al inicio
    console.log(`📱 Contenido agregado: ${contenido.tipo} por ${contenido.autorNombre}`);
    
    return nuevoContenido;
  }

  async obtenerTodoElContenido() {
    // Devolver todo el contenido ordenado por fecha (más reciente primero)
    return [...this.contenidoMultimedia];
  }

  // === UTILIDADES ===

  _generateAvatar(username) {
    const initials = username.substring(0, 2).toUpperCase();
    const colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD', '#98D8C8'];
    const randomColor = colors[Math.floor(Math.random() * colors.length)];
    return `${initials}:${randomColor}`;
  }

  // Verificar si un usuario es miembro de una sala
  isRoomMember(roomId, userId) {
    const room = this.rooms.get(roomId);
    return room ? room.members.some(member => member.user === userId) : false;
  }

  // Obtener estadísticas
  getStats() {
    return {
      users: this.users.size,
      onlineUsers: Array.from(this.users.values()).filter(u => u.isOnline).length,
      rooms: this.rooms.size,
      totalMessages: Array.from(this.messages.values()).reduce((total, msgs) => total + msgs.length, 0),
      contenidoMultimedia: this.contenidoMultimedia.length
    };
  }
}

module.exports = new InMemoryDB();