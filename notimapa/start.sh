#!/usr/bin/env bash
set -euo pipefail

# Root delegator script para Railpack/Railway
# Normaliza y llama al start.sh dentro de sala_chat si existe, o ejecuta node directamente
ROOT_DIR=$(dirname "$0")
if [ -f "$ROOT_DIR/sala_chat/start.sh" ]; then
  echo "[root start.sh] Delegando a sala_chat/start.sh"
  chmod +x "$ROOT_DIR/sala_chat/start.sh" || true
  exec "$ROOT_DIR/sala_chat/start.sh"
else
  echo "[root start.sh] start.sh interno no encontrado, buscando package.json en sala_chat/backend"
  if [ -f "$ROOT_DIR/sala_chat/backend/package.json" ]; then
    cd "$ROOT_DIR/sala_chat/backend"
    echo "[root start.sh] Ejecutando npm start en sala_chat/backend"
    exec npm run start
  else
    echo "[root start.sh] No se encontró start.sh ni package.json; saliendo"
    exit 1
  fi
fi
