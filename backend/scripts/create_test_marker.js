const ioClient = require('socket.io-client');
const { v4: uuidv4 } = require('uuid');

(async () => {
  try {
    const socket = ioClient('http://127.0.0.1:3001', { transports: ['polling', 'websocket'], path: '/socket.io' });
    socket.on('connect', () => {
      console.log('Connected to server via socket:', socket.id);
      const marker = {
        latitude: -34.6037,
        longitude: -58.3816,
        tipoReporte: 'interes'
      };
      // Listen for marker_added to capture ID
      socket.on('marker_added', (m) => {
        console.log('marker_added event received:', m);
        console.log('MARKER_ID:', m.id || m.markerId || m.marker_id || 'unknown');
        socket.disconnect();
        process.exit(0);
      });

      // Emit add_marker
      socket.emit('add_marker', marker);
    });

    socket.on('connect_error', (err) => {
      console.error('Connect error:', err.message || err);
      process.exit(1);
    });
  } catch (e) {
    console.error('Error creating marker script:', e.message || e);
    process.exit(1);
  }
})();
