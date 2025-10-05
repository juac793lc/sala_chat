// Eliminado: modelo Room (Mongo) ya no se utiliza.
module.exports = {};
const mongoose = require('mongoose');

const roomSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
    trim: true,
    maxlength: 50
  },
  description: {
    type: String,
    maxlength: 200,
    default: ''
  },
  type: {
    type: String,
    enum: ['public', 'private'],
    default: 'public'
  },
  creator: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  members: [{
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true
    },
    joinedAt: {
      type: Date,
      default: Date.now
    },
    role: {
      type: String,
      enum: ['admin', 'moderator', 'member'],
      default: 'member'
    }
  }],
  avatar: {
    type: String,
    default: ''
  },
  settings: {
    allowFileSharing: {
      type: Boolean,
      default: true
    },
    allowVoiceMessages: {
      type: Boolean,
      default: true
    },
    maxMembers: {
      type: Number,
      default: 100
    }
  },
  lastActivity: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Index para búsquedas eficientes
roomSchema.index({ name: 'text', description: 'text' });
roomSchema.index({ type: 1, createdAt: -1 });

// Método para verificar si un usuario es miembro
roomSchema.methods.isMember = function(userId) {
  return this.members.some(member => 
    member.user.toString() === userId.toString()
  );
};

// Método para obtener el rol de un usuario
roomSchema.methods.getUserRole = function(userId) {
  const member = this.members.find(member => 
    member.user.toString() === userId.toString()
  );
  return member ? member.role : null;
};

// Método para datos públicos de la sala
roomSchema.methods.toPublic = function() {
  return {
    id: this._id,
    name: this.name,
    description: this.description,
    type: this.type,
    avatar: this.avatar,
    memberCount: this.members.length,
    settings: this.settings,
    lastActivity: this.lastActivity,
    createdAt: this.createdAt
  };
};

module.exports = mongoose.model('Room', roomSchema);