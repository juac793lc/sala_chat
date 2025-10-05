// Eliminado: modelo User (Mongo) ya no se utiliza.
module.exports = {};
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
  username: {
    type: String,
    required: true,
    unique: true,
    trim: true,
    minlength: 2,
    maxlength: 30
  },
  avatar: {
    type: String,
    default: ''
  },
  isOnline: {
    type: Boolean,
    default: false
  },
  lastSeen: {
    type: Date,
    default: Date.now
  },
  socketId: {
    type: String,
    default: ''
  },
  joinedRooms: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Room'
  }]
}, {
  timestamps: true
});

// Generar avatar automático basado en el nombre
userSchema.pre('save', function(next) {
  if (!this.avatar) {
    // Crear avatar con las iniciales
    const initials = this.username.substring(0, 2).toUpperCase();
    const colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD', '#98D8C8'];
    const randomColor = colors[Math.floor(Math.random() * colors.length)];
    this.avatar = `${initials}:${randomColor}`;
  }
  next();
});

// Método para obtener datos públicos del usuario
userSchema.methods.toPublic = function() {
  return {
    id: this._id,
    username: this.username,
    avatar: this.avatar,
    isOnline: this.isOnline,
    lastSeen: this.lastSeen
  };
};

module.exports = mongoose.model('User', userSchema);