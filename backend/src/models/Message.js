// Eliminado: modelo Message (Mongo) ya no se utiliza.
module.exports = {};
const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema({
  content: {
    type: String,
    required: function() {
      return this.type === 'text';
    },
    maxlength: 1000
  },
  type: {
    type: String,
    enum: ['text', 'image', 'audio', 'video', 'file'],
    required: true,
    default: 'text'
  },
  sender: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  room: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Room',
    required: true
  },
  fileUrl: {
    type: String,
    required: function() {
      return ['image', 'audio', 'video', 'file'].includes(this.type);
    }
  },
  fileName: {
    type: String
  },
  fileSize: {
    type: Number
  },
  mimeType: {
    type: String
  },
  replyTo: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Message',
    default: null
  },
  reactions: [{
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User'
    },
    emoji: String,
    createdAt: {
      type: Date,
      default: Date.now
    }
  }],
  readBy: [{
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User'
    },
    readAt: {
      type: Date,
      default: Date.now
    }
  }],
  editedAt: {
    type: Date
  },
  isDeleted: {
    type: Boolean,
    default: false
  }
}, {
  timestamps: true
});

// Índices para consultas eficientes
messageSchema.index({ room: 1, createdAt: -1 });
messageSchema.index({ sender: 1, createdAt: -1 });
messageSchema.index({ room: 1, type: 1, createdAt: -1 });

// Método para marcar como leído por un usuario
messageSchema.methods.markAsRead = function(userId) {
  const existingRead = this.readBy.find(read => 
    read.user.toString() === userId.toString()
  );
  
  if (!existingRead) {
    this.readBy.push({
      user: userId,
      readAt: new Date()
    });
  }
};

// Método para obtener datos públicos del mensaje
messageSchema.methods.toPublic = function() {
  return {
    id: this._id,
    content: this.content,
    type: this.type,
    sender: this.sender,
    room: this.room,
    fileUrl: this.fileUrl,
    fileName: this.fileName,
    fileSize: this.fileSize,
    mimeType: this.mimeType,
    replyTo: this.replyTo,
    reactions: this.reactions,
    readBy: this.readBy,
    editedAt: this.editedAt,
    isDeleted: this.isDeleted,
    createdAt: this.createdAt,
    updatedAt: this.updatedAt
  };
};

module.exports = mongoose.model('Message', messageSchema);