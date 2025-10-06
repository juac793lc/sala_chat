// Script para limpiar solo los datos de la base de datos SQLite sin borrar la estructura
const path = require('path');
const initSqlJs = require('sql.js');
const fs = require('fs');

const dbPath = path.join(__dirname, 'chat_data.db');

async function limpiarDatos() {
  if (!fs.existsSync(dbPath)) {
    console.log('No existe la base de datos.');
    return;
  }
  const SQL = await initSqlJs();
  const filebuffer = fs.readFileSync(dbPath);
  const db = new SQL.Database(filebuffer);

  // Eliminar solo los datos, no la estructura
  db.exec('DELETE FROM messages;');
  db.exec('DELETE FROM media;');
  db.exec('DELETE FROM map_markers;');

  // Guardar cambios
  const data = db.export();
  const buffer = Buffer.from(data);
  fs.writeFileSync(dbPath, buffer);
  console.log('Datos eliminados, estructura intacta.');
}

limpiarDatos();
