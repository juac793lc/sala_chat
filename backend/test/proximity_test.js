const io = require('socket.io-client');
const jwt = require('jsonwebtoken');

const SERVER = 'http://localhost:3001';
const SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';

function makeToken(userId, username) {
  return jwt.sign({ userId, username }, SECRET, { expiresIn: '1h' });
}

async function wait(ms) { return new Promise(r => setTimeout(r, ms)); }

async function runTest() {
  console.log('Iniciando test de proximidad...');

  const tokenNear = makeToken('user-near', 'Alice');
  const tokenFar = makeToken('user-far', 'Bob');

  const nearCoords = { lat: 40.001, lng: -3.001 }; // cercano al marcador
  const farCoords = { lat: 41.0, lng: -3.0 }; // lejos

  const results = { near: false, far: false };

  const socketNear = io(SERVER, { auth: { token: tokenNear }, reconnection: false });
  const socketFar = io(SERVER, { auth: { token: tokenFar }, reconnection: false });

  socketNear.on('connect', () => console.log('[NEAR] conectado, id=', socketNear.id));
  socketFar.on('connect', () => console.log('[FAR] conectado, id=', socketFar.id));

  socketNear.on('auth_success', (d) => console.log('[NEAR] auth_success', d.message));
  socketFar.on('auth_success', (d) => console.log('[FAR] auth_success', d.message));

  socketNear.on('map_notification', (n) => {
    console.log('[NEAR] map_notification recibida:', n);
    results.near = true;
  });
  socketFar.on('map_notification', (n) => {
    console.log('[FAR] map_notification recibida:', n);
    results.far = true;
  });

  socketNear.on('marker_confirmed', (m) => console.log('[NEAR] marker_confirmed', m.id));
  socketFar.on('marker_confirmed', (m) => console.log('[FAR] marker_confirmed', m.id));

  // Esperar conexiones
  await wait(800);

  console.log('Enviando ubicación inicial de ambos sockets...');
  socketNear.emit('update_location', { lat: nearCoords.lat, lng: nearCoords.lng, ts: new Date().toISOString() });
  socketFar.emit('update_location', { lat: farCoords.lat, lng: farCoords.lng, ts: new Date().toISOString() });

  await wait(500);

  console.log('Cliente NEAR crea un marcador cerca de sus coordenadas...');
  socketNear.emit('add_marker', { latitude: nearCoords.lat, longitude: nearCoords.lng, tipoReporte: 'interes' });

  // Después de crear marcador, enviar update_location de nuevo para que el servidor evalúe proximidad
  await wait(400);
  console.log('Re-enviando ubicaciones para disparar notificaciones...');
  socketNear.emit('update_location', { lat: nearCoords.lat, lng: nearCoords.lng, ts: new Date().toISOString() });
  socketFar.emit('update_location', { lat: farCoords.lat, lng: farCoords.lng, ts: new Date().toISOString() });

  // Esperar 3s para recibir notificaciones
  await wait(3000);

  console.log('\nResultados del test:');
  console.log('near recibió notificación? ', results.near);
  console.log('far recibió notificación?  ', results.far);

  socketNear.disconnect();
  socketFar.disconnect();

  if (results.near && !results.far) {
    console.log('\n✅ Test OK: sólo el cliente cercano recibió la notificación.');
    process.exit(0);
  } else {
    console.log('\n❌ Test FAILED: comportamiento inesperado.');
    process.exit(2);
  }
}

runTest().catch(e => { console.error('ERROR en test:', e); process.exit(3); });
