#!/usr/bin/env bash
# lofi_pipeline.sh
# Full pipeline: generate lofi video → upload to YouTube
# Designed to run unattended on Oracle VM via cron/systemd.
#
# Usage:  bash lofi_pipeline.sh
# Cron:   0 */3 * * * /path/to/lofi_pipeline.sh >> /var/log/lofi_pipeline.log 2>&1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PIPELINE_DIR="$SCRIPT_DIR"
OUTPUT_DIR="$REPO_ROOT/output/pipeline"
VENV="$REPO_ROOT/.venv-pipeline"
ML_SERVER_URL="${ML_SERVER_URL:-http://localhost:5050}"
DURATION="${LOFI_DURATION:-10800}"   # 3 hours in seconds
PRIVACY="${LOFI_PRIVACY:-public}"

mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="$OUTPUT_DIR/lofi_${TIMESTAMP}.mp4"
TITLE="lofi hip hop • $(date '+%B %Y') mix • beats to study/relax to 🎵"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
# 1. Ensure venv + deps
# ---------------------------------------------------------------------------
log "Checking Python environment..."
if [ ! -d "$VENV" ]; then
  log "Creating venv at $VENV"
  python3 -m venv "$VENV"
fi
source "$VENV/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet pretty_midi google-api-python-client google-auth-oauthlib google-auth-httplib2

# ---------------------------------------------------------------------------
# 2. Check ML server (start if not running)
# ---------------------------------------------------------------------------
log "Checking ML server at $ML_SERVER_URL..."
if ! curl -sf "$ML_SERVER_URL/" > /dev/null 2>&1; then
  log "ML server not running — starting it..."
  ML_PY="$REPO_ROOT/.venv-ml311/bin/python"
  [ -x "$ML_PY" ] || ML_PY="$REPO_ROOT/.venv-ml/bin/python"
  [ -x "$ML_PY" ] || ML_PY="$(command -v python3)"
  cd "$REPO_ROOT/integrations/jacbz-lofi"
  "$ML_PY" -m flask --app=server/app.py run --host=0.0.0.0 --port=5050 &
  ML_PID=$!
  log "ML server PID: $ML_PID — waiting 15s for startup..."
  sleep 15
  cd "$REPO_ROOT"
else
  log "ML server already running."
  ML_PID=""
fi

# ---------------------------------------------------------------------------
# 3. Generate lofi video
# ---------------------------------------------------------------------------
log "Generating lofi video (duration=${DURATION}s)..."
python3 "$PIPELINE_DIR/generate_lofi_video.py" \
  --duration "$DURATION" \
  --output "$OUTPUT_FILE" \
  --server "$ML_SERVER_URL" \
  --title "$TITLE"

log "Video generated: $OUTPUT_FILE ($(du -sh "$OUTPUT_FILE" | cut -f1))"

# ---------------------------------------------------------------------------
# 4. Upload to YouTube
# ---------------------------------------------------------------------------
log "Uploading to YouTube channel llooffiisounds..."
python3 "$PIPELINE_DIR/upload_to_youtube.py" \
  --video "$OUTPUT_FILE" \
  --title "$TITLE" \
  --privacy "$PRIVACY"

log "Upload complete."

# ---------------------------------------------------------------------------
# 5. Cleanup old videos (keep last 5)
# ---------------------------------------------------------------------------
log "Cleaning old videos (keeping last 5)..."
ls -t "$OUTPUT_DIR"/lofi_*.mp4 2>/dev/null | tail -n +6 | xargs -r rm -v

# Kill ML server if we started it
if [ -n "$ML_PID" ]; then
  kill "$ML_PID" 2>/dev/null || true
fi

log "Pipeline complete. Next run in 3 hours."
