#!/usr/bin/env bash
# NeuroNudge dev runner: FastAPI backend + Flutter web frontend
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$ROOT/backend"
FRONTEND_DIR="$ROOT/frontend"
VENV_DIR="$BACKEND_DIR/.venv"
PORT="${PORT:-8000}"
AI_URL="${AI_BASE_URL:-http://127.0.0.1:${PORT}}"
LOG_FILE="$ROOT/.backend.log"

die() { echo "❌ $*"; exit 1; }
log() { echo "👉 $*"; }

# --- Sanity checks ---
[ -d "$BACKEND_DIR" ]  || die "Missing backend/ directory"
[ -d "$FRONTEND_DIR" ] || die "Missing frontend/ directory"
command -v curl >/dev/null     || die "curl not found (brew install curl)"
command -v python3 >/dev/null  || die "python3 not found"
command -v flutter >/dev/null  || die "flutter not found (install Flutter & add to PATH)"

# --- Backend venv & deps ---
log "Creating/using virtualenv at $VENV_DIR"
python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
python -m pip -q install -U pip

REQ_FILE="$BACKEND_DIR/requirements.txt"
if [ -f "$REQ_FILE" ]; then
  log "Installing backend requirements.txt…"
  pip -q install -r "$REQ_FILE"
else
  log "Installing minimal backend deps (fastapi, uvicorn, pydantic)…"
  pip -q install "fastapi" "uvicorn" "pydantic>=1.10,<3"
fi

# --- Free port if needed (handle multiple PIDs) ---
PIDS="$(lsof -ti tcp:"$PORT" || true)"
if [ -n "$PIDS" ]; then
  log "Killing old processes on port $PORT: $PIDS"
  echo "$PIDS" | xargs -n1 kill || true
  sleep 1
fi

# --- Start backend once ---
cd "$BACKEND_DIR"
[ -f main.py ] || die "backend/main.py not found"
log "Starting backend: uvicorn main:app --port $PORT"
uvicorn main:app --reload --host 0.0.0.0 --port "$PORT" > "$LOG_FILE" 2>&1 &
BACKEND_PID=$!
log "Backend PID: $BACKEND_PID (logs: $(basename "$LOG_FILE"))"

# --- Wait for health ---
log "Waiting for backend health at $AI_URL/health …"
for i in {1..40}; do
  if curl -fsS "$AI_URL/health" >/dev/null 2>&1; then
    log "Backend is up ✅"
    break
  fi
  sleep 0.25
  if [ $i -eq 40 ]; then
    echo "---- Backend log tail ----"
    tail -n 80 "$LOG_FILE" || true
    die "Backend did not become healthy on $AI_URL"
  fi
done

# --- Cleanup on exit ---
cleanup() {
  log "Stopping backend (PID $BACKEND_PID)…"
  kill "$BACKEND_PID" 2>/dev/null || true
}
trap cleanup EXIT

# --- Frontend (enable web, then run Chrome target) ---
cd "$FRONTEND_DIR"
log "Ensuring Flutter web support is enabled…"
flutter config --enable-web >/dev/null 2>&1 || true

log "Running Flutter (Chrome) with AI_BASE_URL=$AI_URL"
# If you already default to 127.0.0.1:8000 in ai_service.dart, you can remove --dart-define.
flutter run -d chrome --dart-define=AI_BASE_URL="$AI_URL"
