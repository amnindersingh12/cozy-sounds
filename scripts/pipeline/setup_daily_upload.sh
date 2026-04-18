#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup_daily_upload.sh
# One-time setup for the daily 4K lofi YouTube upload pipeline.
#
# What it does:
#   1. Validates all dependencies
#   2. Handles YouTube OAuth2 first-run auth (interactive — needs terminal)
#   3. Installs systemd service + timer for daily uploads at 06:00 UTC
#   4. Optionally runs a test upload (unlisted, 30s video)
#
# Usage:
#   bash scripts/pipeline/setup_daily_upload.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

C0='\033[0m'; BOLD='\033[1m'
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
log()  { echo -e "${CYAN}${BOLD}[setup]${C0} $*"; }
ok()   { echo -e "${GREEN}${BOLD}[setup] ✓${C0} $*"; }
warn() { echo -e "${YELLOW}${BOLD}[setup] ⚠${C0} $*"; }
die()  { echo -e "${RED}${BOLD}[setup] ✗${C0} $*" >&2; exit 1; }

echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C0}"
echo -e "${BOLD}${CYAN}  🎵 llooffiisounds — Daily Upload Setup${C0}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C0}"
echo ""

# ── Step 1: Check deps ─────────────────────────────────────────────────────
log "Step 1: Checking dependencies..."
command -v ffmpeg     >/dev/null || die "ffmpeg not found. Run: sudo apt install ffmpeg"
command -v fluidsynth >/dev/null || die "fluidsynth not found. Run: sudo apt install fluidsynth fluid-soundfont-gm"
command -v python3    >/dev/null || die "python3 not found."
command -v curl       >/dev/null || die "curl not found."
ok "All system dependencies present."

# ── Step 2: YouTube OAuth ───────────────────────────────────────────────────
log "Step 2: YouTube API credentials..."
SECRET_PATH="$SCRIPT_DIR/client_secret.json"
TOKEN_PATH="$SCRIPT_DIR/youtube_token.pickle"

if [ ! -f "$SECRET_PATH" ]; then
  die "Missing: $SECRET_PATH
  
  To create this file:
  1. Go to https://console.cloud.google.com/
  2. Create a project, enable 'YouTube Data API v3'
  3. Credentials → Create OAuth 2.0 Client ID (Desktop app)
  4. Download the JSON and save it as:
     $SECRET_PATH"
fi
ok "client_secret.json found."

if [ ! -f "$TOKEN_PATH" ]; then
  warn "No saved YouTube token found. Starting first-run OAuth flow..."
  warn "You'll need to open a URL and authorize the app."
  echo ""
  
  # Activate the pipeline venv
  VENV="$REPO_ROOT/.venv-pipeline"
  if [ ! -d "$VENV" ]; then
    python3 -m venv "$VENV" 2>/dev/null || uv venv "$VENV" --quiet
  fi
  source "$VENV/bin/activate"
  pip install --quiet google-api-python-client google-auth-oauthlib google-auth-httplib2 2>/dev/null || \
    uv pip install --quiet google-api-python-client google-auth-oauthlib google-auth-httplib2

  python3 - <<'PYAUTH'
import pickle, os, sys
from pathlib import Path
from google_auth_oauthlib.flow import InstalledAppFlow

SCRIPT_DIR = os.environ.get("SCRIPT_DIR", "scripts/pipeline")
SECRET = Path(SCRIPT_DIR) / "client_secret.json"
TOKEN = Path(SCRIPT_DIR) / "youtube_token.pickle"
SCOPES = [
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube",
]

print("\n  Starting OAuth2 flow...\n")
flow = InstalledAppFlow.from_client_secrets_file(str(SECRET), SCOPES)

# Try local server first, fall back to console (for headless VMs)
has_display = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
try:
    if has_display:
        creds = flow.run_local_server(port=0)
    else:
        creds = flow.run_console()
except Exception as e:
    print(f"  Local server auth failed: {e}")
    print("  Trying console auth instead...")
    creds = flow.run_console()

with open(TOKEN, "wb") as f:
    pickle.dump(creds, f)
print(f"\n  ✓ Token saved to {TOKEN}")
PYAUTH

  export SCRIPT_DIR
  if [ ! -f "$TOKEN_PATH" ]; then
    die "OAuth flow failed — token was not saved."
  fi
  ok "YouTube OAuth completed successfully."
else
  ok "YouTube token already exists."
fi

# ── Step 3: Install systemd timer ───────────────────────────────────────────
log "Step 3: Installing systemd daily timer..."

SERVICE_SRC="$SCRIPT_DIR/lofi-pipeline@.service"
TIMER_SRC="$SCRIPT_DIR/lofi-pipeline@.timer"
USER=$(whoami)

if [ ! -f "$SERVICE_SRC" ] || [ ! -f "$TIMER_SRC" ]; then
  die "Missing systemd files. Expected:
  $SERVICE_SRC
  $TIMER_SRC"
fi

# Create log file if it doesn't exist
sudo touch /var/log/lofi_pipeline.log
sudo chown "$USER" /var/log/lofi_pipeline.log

# Copy and install
sudo cp "$SERVICE_SRC" /etc/systemd/system/
sudo cp "$TIMER_SRC"   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now "lofi-pipeline@${USER}.timer"

ok "Systemd timer installed and enabled."
echo ""
log "Timer status:"
systemctl status "lofi-pipeline@${USER}.timer" --no-pager 2>&1 | head -10 || true
echo ""

# ── Step 4: Optional test run ──────────────────────────────────────────────
log "Step 4: Test run..."
echo ""
echo -e "  Would you like to run a quick test upload? (30s unlisted video)"
echo -e "  This will generate a short video and upload it as ${BOLD}unlisted${C0}."
echo ""
read -p "  Run test? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  log "Running test upload (30s, unlisted)..."
  cd "$REPO_ROOT"
  DURATION=30 PRIVACY=unlisted bash scripts/pipeline/make_youtube_video.sh
  ok "Test upload complete!"
else
  log "Skipping test. You can always run manually:"
  echo "  cd $REPO_ROOT && bash scripts/pipeline/make_youtube_video.sh"
fi

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C0}"
echo -e "${BOLD}${GREEN}  ✓  Daily upload pipeline is live!${C0}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C0}"
echo ""
echo "  Schedule  : Daily at 06:00 UTC"
echo "  Duration  : 3 hours (4K 3840×2160)"
echo "  Privacy   : public"
echo ""
echo "  Useful commands:"
echo "    # Check timer"
echo "    systemctl status lofi-pipeline@${USER}.timer"
echo ""
echo "    # View logs"
echo "    tail -f /var/log/lofi_pipeline.log"
echo ""
echo "    # Run manually now"
echo "    cd $REPO_ROOT && bash scripts/pipeline/make_youtube_video.sh"
echo ""
echo "    # Trigger the timer immediately"
echo "    sudo systemctl start lofi-pipeline@${USER}.service"
echo ""
echo "    # Stop daily uploads"
echo "    sudo systemctl disable --now lofi-pipeline@${USER}.timer"
echo ""
echo "    # Upload history"
echo "    cat $SCRIPT_DIR/upload_log.json | python3 -m json.tool"
echo ""
