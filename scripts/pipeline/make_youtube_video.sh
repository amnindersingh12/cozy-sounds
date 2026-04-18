#!/usr/bin/env bash
# make_youtube_video.sh
# ─────────────────────────────────────────────────────────────────────────────
# End-to-end pipeline for llooffiisounds:
#   1. Start ML server (if not running)
#   2. Download a random anime GIF from waifu.vercel.app as background
#   3. Generate lofi audio from the engine (ML → MIDI → WAV → lofi FX → 3h loop)
#   4. Render a 4K (3840×2160) 16:9 MP4, 3 hours — GIF loops with 4px blur
#   5. Generate a YouTube thumbnail (1280×720) from the GIF's first frame
#   6. Upload to YouTube with rich title, description, and tags
#
# No external audio/video files needed — uses the engine + waifu API.
#
# Usage:
#   bash scripts/pipeline/make_youtube_video.sh
#
# Optional env overrides:
#   WAIFU_EP=dance   Force a specific waifu endpoint. Default: random.
#   DURATION=10800   Duration in seconds. Default: 10800 (3h).
#   PRIVACY=public   YouTube privacy. Default: public.
#   SKIP_UPLOAD=1    Skip YouTube upload. Default: 0.
#   MOOD=rainy       Mood title word. Default: auto.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV="$REPO_ROOT/.venv-pipeline"
ML_VENV_311="$REPO_ROOT/.venv-ml311/bin/python"
ML_VENV="$REPO_ROOT/.venv-ml/bin/python"
ML_SERVER_URL="${ML_SERVER_URL:-http://localhost:5050}"
DURATION="${DURATION:-10800}"
PRIVACY="${PRIVACY:-public}"
SKIP_UPLOAD="${SKIP_UPLOAD:-0}"
OUTPUT_DIR="$REPO_ROOT/output/pipeline"
THUMB_DIR="$REPO_ROOT/output/thumbnails"
GIF_CACHE_DIR="$REPO_ROOT/output/waifu-cache"

# All waifu endpoint names (SFW)
WAIFU_ENDPOINTS=("waifu" "neko" "shinobu" "bully" "cry" "hug" "kiss" "smug" \
  "highfive" "nom" "bite" "slap" "wink" "poke" "dance" "cringe" "blush" "happy")
WAIFU_BASE="https://waifu.vercel.app/sfw/"
# Pick a random endpoint unless overridden
if [ -n "${WAIFU_EP:-}" ]; then
  WAIFU_ENDPOINT="$WAIFU_EP"
else
  WAIFU_ENDPOINT="${WAIFU_ENDPOINTS[$((RANDOM % ${#WAIFU_ENDPOINTS[@]}))]}"
fi

mkdir -p "$OUTPUT_DIR" "$THUMB_DIR" "$GIF_CACHE_DIR"

# ── Colours ──────────────────────────────────────────────────────────────────
C0='\033[0m'; BOLD='\033[1m'
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
log()  { echo -e "${CYAN}${BOLD}[$(date '+%H:%M:%S')]${C0} $*"; }
ok()   { echo -e "${GREEN}${BOLD}[$(date '+%H:%M:%S')] ✓${C0} $*"; }
warn() { echo -e "${YELLOW}${BOLD}[$(date '+%H:%M:%S')] ⚠${C0} $*"; }
die()  { echo -e "${RED}${BOLD}[$(date '+%H:%M:%S')] ✗${C0} $*" >&2; exit 1; }

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOURS=$((DURATION / 3600))
MINS=$(( (DURATION % 3600) / 60 ))

echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C0}"
echo -e "${BOLD}${CYAN}  🎵 llooffiisounds — 4K YouTube Pipeline${C0}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C0}"
echo -e "  Duration : ${HOURS}h ${MINS}m   Privacy: $PRIVACY"
echo ""

# ── Check deps ────────────────────────────────────────────────────────────────
log "[0/6] Checking system dependencies..."
command -v ffmpeg     >/dev/null || die "ffmpeg not found. Run: sudo apt install ffmpeg"
command -v fluidsynth >/dev/null || die "fluidsynth not found. Run: sudo apt install fluidsynth fluid-soundfont-gm"
command -v python3    >/dev/null || die "python3 not found."
command -v curl       >/dev/null || die "curl not found. Run: sudo apt install curl"

if ! command -v uv >/dev/null; then
  warn "  uv not found — installing it for faster deps..."
  curl -LsSf https://astral.sh/uv/install.sh | sh > /dev/null 2>&1 || true
  # Source uv immediately if it was just installed
  export PATH="$HOME/.local/bin:$PATH"
fi
ok "All system deps present (including uv)."

# ── Download trendy font (Poppins Bold from Google Fonts) ─────────────────────
FONT_DIR="$REPO_ROOT/assets/fonts"
FONT_FILE="$FONT_DIR/Poppins-Bold.ttf"
FONT_FILE_MEDIUM="$FONT_DIR/Poppins-Medium.ttf"
mkdir -p "$FONT_DIR"
if [ ! -f "$FONT_FILE" ]; then
  log "  Downloading Poppins font family from Google Fonts..."
  FONT_ZIP=$(mktemp /tmp/poppins_XXXXX.zip)
  curl -sfL -o "$FONT_ZIP" \
    "https://fonts.google.com/download?family=Poppins" || {
    warn "  Google Fonts download failed — trying GitHub mirror..."
    curl -sfL -o "$FONT_ZIP" \
      "https://github.com/google/fonts/raw/main/ofl/poppins/Poppins-Bold.ttf" && {
      cp "$FONT_ZIP" "$FONT_FILE"
      rm -f "$FONT_ZIP"
    } || true
  }
  if [ -f "$FONT_ZIP" ] && file "$FONT_ZIP" | grep -qi zip; then
    TMP_FONT=$(mktemp -d /tmp/poppins_extract_XXXXX)
    unzip -o -q "$FONT_ZIP" -d "$TMP_FONT" 2>/dev/null || true
    find "$TMP_FONT" -name "Poppins-Bold.ttf" -exec cp {} "$FONT_FILE" \;
    find "$TMP_FONT" -name "Poppins-Medium.ttf" -exec cp {} "$FONT_FILE_MEDIUM" \;
    rm -rf "$TMP_FONT" "$FONT_ZIP"
  fi
  if [ -f "$FONT_FILE" ]; then
    ok "  Poppins Bold font ready."
  else
    warn "  Could not download Poppins — will use system default font."
  fi
else
  ok "  Poppins font cached."
fi
# Build fontfile arg for ffmpeg (empty string if font not available)
if [ -f "$FONT_FILE" ]; then
  FF_BOLD="fontfile=${FONT_FILE}"
  FF_MED="fontfile=${FONT_FILE_MEDIUM:-$FONT_FILE}"
  [ -f "${FONT_FILE_MEDIUM:-}" ] || FF_MED="$FF_BOLD"
else
  FF_BOLD=""
  FF_MED=""
fi

# ── Python venv (via uv) ──────────────────────────────────────────────────────
log "[0/6] Setting up Python venv via uv..."
if [ ! -d "$VENV" ]; then
  uv venv "$VENV" --quiet
fi
source "$VENV/bin/activate"
uv pip install --quiet --upgrade pip
uv pip install --quiet pretty_midi google-api-python-client google-auth-oauthlib google-auth-httplib2 requests certifi
ok "Venv ready."

# ── ML Server venv + startup ──────────────────────────────────────────────────
log "[1/6] Setting up ML server environment..."
ML_VENV_DIR="$REPO_ROOT/.venv-ml"
ML_SERVER_DIR="$REPO_ROOT/integrations/jacbz-lofi"
ML_REQ="$ML_SERVER_DIR/server/requirements.txt"
ML_PY="$ML_VENV_DIR/bin/python"
ML_PID=""

# Bootstrap the ML venv if missing or if dependencies are missing
if [ ! -d "$ML_VENV_DIR" ]; then
  log "  Creating new ML venv via uv..."
  uv venv "$ML_VENV_DIR" --quiet
fi

# Check if deps are actually installed
if ! "$ML_PY" -c "import flask" 2>/dev/null; then
  log "  Installing missing ML deps (this may take a moment)..."
  
  # Check if we are on ARM (aarch64/arm64)
  ARCH=$(uname -m)
  if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
    log "  ARM detected: installing standard torch (stripping +cpu tag)..."
    # Create a patched requirements file without +cpu tags
    sed 's/+cpu//g' "$ML_REQ" > "${ML_REQ}.arm"
    uv pip install --quiet -r "${ML_REQ}.arm" --python "$ML_PY"
  else
    # Standard x86_64 CPU install
    uv pip install --quiet -r "$ML_REQ" \
      --python "$ML_PY" \
      --extra-index-url https://download.pytorch.org/whl/cpu
  fi
  ok "  ML dependencies installed."
else
  ok "  ML environment is ready (reusing existing venv)."
fi

# Download model checkpoints if missing
CKPT_DIR="$ML_SERVER_DIR/checkpoints"
CKPT_URL="https://github.com/jacbz/Lofi/files/7519187/checkpoints.zip"
if [ ! -f "$CKPT_DIR/lofi2lofi_decoder.pth" ] || [ ! -f "$CKPT_DIR/lyrics2lofi.pth" ]; then
  log "  Downloading ML model checkpoints..."
  mkdir -p "$CKPT_DIR"
  TMP_ZIP=$(mktemp /tmp/lofi_ckpt_XXXXX.zip)
  TMP_EXTRACT=$(mktemp -d /tmp/lofi_ckpt_extract_XXXXX)
  
  curl -sfL -o "$TMP_ZIP" "$CKPT_URL" || die "Failed to download checkpoints from $CKPT_URL"
  log "  Downloaded $(du -sh "$TMP_ZIP" | cut -f1). Extracting..."
  
  unzip -o -q "$TMP_ZIP" -d "$TMP_EXTRACT"
  
  # Debug: show what's inside
  log "  Zip contents:"
  find "$TMP_EXTRACT" -type f -name "*.pth" | while read f; do
    log "    $(basename "$f") — $(du -sh "$f" | cut -f1)"
  done
  
  # Find and copy .pth files regardless of folder structure
  find "$TMP_EXTRACT" -name "lofi2lofi_decoder.pth" -exec cp {} "$CKPT_DIR/" \;
  find "$TMP_EXTRACT" -name "lyrics2lofi.pth" -exec cp {} "$CKPT_DIR/" \;
  
  # If exact names not found, try any .pth files
  if [ ! -f "$CKPT_DIR/lofi2lofi_decoder.pth" ]; then
    log "  Exact name not found — copying all .pth files..."
    find "$TMP_EXTRACT" -name "*.pth" -exec cp {} "$CKPT_DIR/" \;
    log "  Checkpoints dir now contains: $(ls "$CKPT_DIR"/ 2>/dev/null)"
  fi
  
  rm -rf "$TMP_ZIP" "$TMP_EXTRACT"
  
  if [ -f "$CKPT_DIR/lofi2lofi_decoder.pth" ]; then
    ok "  Checkpoints ready."
  else
    warn "  Could not find expected checkpoint files. Contents of $CKPT_DIR:"
    ls -la "$CKPT_DIR/" 2>/dev/null
    die "  ML checkpoints missing — cannot start server."
  fi
else
  ok "  Model checkpoints present."
fi

if ! curl -sf "$ML_SERVER_URL/" >/dev/null 2>&1; then
  log "  Starting ML server on port 5050..."
  cd "$ML_SERVER_DIR"
  FLASK_APP=server/app.py "$ML_PY" -m flask run --host=0.0.0.0 --port=5050 \
    > /tmp/ml_server_$$.log 2>&1 &
  ML_PID=$!
  ML_LOGFILE="/tmp/ml_server_$$.log"
  log "  Waiting for ML server to be ready (PID $ML_PID)..."
  log "  (Loading PyTorch models on ARM takes ~30-60s...)"
  # Poll up to 90s — ARM model loading is slow
  for i in $(seq 1 90); do
    sleep 1
    if curl -sf "$ML_SERVER_URL/" >/dev/null 2>&1; then
      ok "  ML server is up (took ${i}s)."
      break
    fi
    # Print progress every 10s
    if [ $((i % 10)) -eq 0 ]; then
      log "  Still waiting... ${i}s"
    fi
    # Check if process died
    if ! kill -0 "$ML_PID" 2>/dev/null; then
      warn "  ML server process died. Log output:"
      cat "$ML_LOGFILE" 2>/dev/null | tail -20
      warn "  Will use procedural fallback."
      ML_PID=""
      break
    fi
    if [ $i -eq 90 ]; then
      warn "  ML server did not respond in 90s. Log tail:"
      tail -20 "$ML_LOGFILE" 2>/dev/null
      warn "  Will use procedural fallback for this run."
    fi
  done
  cd "$REPO_ROOT"
else
  ok "  ML server already running."
fi

# Ensure ML server cleanup on exit
cleanup() {
  if [ -n "${ML_PID:-}" ]; then
    kill "$ML_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# ── Download waifu GIF background ────────────────────────────────────────────
log "[2/6] Fetching anime GIF background (endpoint: ${WAIFU_ENDPOINT})..."
WAIFU_URL="${WAIFU_BASE}${WAIFU_ENDPOINT}"

# Use nekos.best GIF endpoints (verified working) with waifu.pics as fallback
log "  Downloading anime GIF/image via nekos.best API..."
BG_GIF=$(python3 - <<PYFETCH
import requests, sys, random
from pathlib import Path

cache_dir = Path("$GIF_CACHE_DIR")
cache_dir.mkdir(parents=True, exist_ok=True)
ep = "$WAIFU_ENDPOINT"
ts = "$TIMESTAMP"

# nekos.best endpoints that actually return GIFs (NOT png):
#   neko/kitsune/waifu/husbando return PNG — do NOT use for GIF mode.
#   Verified GIF-returning endpoints from /api/v2/endpoints:
NEKOS_GIF_ENDPOINTS = [
    "hug", "dance", "pat", "smile", "happy", "wave", "cuddle",
    "spin", "kiss", "cry", "laugh", "wink", "blush", "smug",
    "poke", "highfive", "nom", "bite", "slap", "bonk", "yeet",
]
nekos_ep = random.choice(NEKOS_GIF_ENDPOINTS)

UA = {"User-Agent": "LofiPipeline/1.0 (https://github.com/llooffiisounds)"}

apis = [
    # 1. nekos.best — GIF endpoints (reliable, free, no key)
    {
        "url": f"https://nekos.best/api/v2/{nekos_ep}?amount=1",
        "parse": lambda d: d["results"][0]["url"],
        "ext": "gif",
        "name": f"nekos.best/{nekos_ep}",
    },
    # 2. waifu.pics — returns PNG (still usable as Ken Burns still image)
    {
        "url": "https://api.waifu.pics/sfw/waifu",
        "parse": lambda d: d["url"],
        "ext": "png",
        "name": "waifu.pics/waifu",
    },
]

for api in apis:
    try:
        r = requests.get(api["url"], headers=UA, timeout=15, allow_redirects=True)
        r.raise_for_status()
        if not r.content:
            raise ValueError("empty response body")
        img_url = api["parse"](r.json())
        if not img_url:
            raise ValueError("empty image url")
        ext = api["ext"]
        dest = cache_dir / f"bg_{ep}_{ts}.{ext}"
        sys.stderr.write(f"[gif] downloading from {api['name']} → {dest.name}\n")
        r2 = requests.get(img_url, headers=UA, timeout=60, stream=True)
        r2.raise_for_status()
        dest.write_bytes(r2.content)
        if dest.stat().st_size < 1024:
            raise ValueError(f"file too small ({dest.stat().st_size}B)")
        print(str(dest))
        break
    except Exception as e:
        sys.stderr.write(f"[gif] {api['name']} failed: {e}\n")
        continue
else:
    sys.stderr.write("[gif] all APIs failed\n")
    print("")
PYFETCH
)

# Validation and fallback
if [ -z "$BG_GIF" ] || [ ! -s "$BG_GIF" ]; then
  warn "  waifu API fetch failed — falling back to local background."
  EXISTING_BG=$(ls -S "$REPO_ROOT/public/assets/background"/bg*.webp 2>/dev/null | head -1)
  [ -n "$EXISTING_BG" ] || die "No local background fallback found in $REPO_ROOT/public/assets/background/"
  # Keep the real extension so ffmpeg knows what it's dealing with
  BG_GIF="$EXISTING_BG"
  WAIFU_ENDPOINT="local-fallback"
fi

BG_SIZE=$(du -sh "$BG_GIF" 2>/dev/null | cut -f1 || echo "?")
ok "Background: $(basename "$BG_GIF") (${BG_SIZE}) — endpoint: ${WAIFU_ENDPOINT}"

# ── Build title & metadata ────────────────────────────────────────────────────
MOODS=("chill" "rainy evening" "late night" "study session" "coffee shop" "midnight" "focus")
VIBES=("relax / study to" "work / focus to" "code to" "read to" "sleep to")
MOOD="${MOOD:-${MOODS[$((RANDOM % ${#MOODS[@]}))]}}"
VIBE="${VIBES[$((RANDOM % ${#VIBES[@]}))]}"
MONTH=$(date '+%B %Y')

TITLE="lofi hip hop • ${MOOD} beats to ${VIBE} 🎵 ${HOURS} hour mix"
OVERLAY_TITLE="${MOOD} lofi • ${HOURS}hr mix"

DESCRIPTION="$(cat <<EOF
${TITLE}

A continuous ${HOURS}-hour lofi mix — generated live with the Lofi Engine.

🎵  Perfect for studying, working, or relaxing.
🌙  No ads, no interruptions — just pure lofi vibes.
☕  ${MONTH} — fresh beats every upload.

─────────────────────────────
➤ Subscribe to llooffiisounds for daily lofi drops
➤ Hit the 🔔 bell so you never miss a mix
─────────────────────────────

Generated with the jacbz-lofi ML model + Tone.js engine.
Background: lofi anime scene.

#lofi #lofihiphop #studymusic #chillbeats #relaxingmusic #focusmusic
#lofimix #3hourslofi #beatstorelaxto #lofi2025 #chillhop #ambientmusic
EOF
)"

log "  Title: $TITLE"

# ── Generate audio ────────────────────────────────────────────────────────────
log "[3/6] Generating lofi audio (${HOURS}h) via ML + fluidsynth..."
AUDIO_WAV="$OUTPUT_DIR/lofi_audio_${TIMESTAMP}.wav"

# We call the generation logic via a Python wrapper that uses the generation scripts directly
python3 - <<PYEOF
import sys, os
sys.path.insert(0, "$SCRIPT_DIR")
from pathlib import Path
from generate_lofi_video import fetch_track, build_midi, midi_to_wav, apply_lofi_fx, loop_audio_to_duration
import tempfile

tmp = Path(tempfile.mkdtemp())
print("[py] Fetching track blueprint...")
track = fetch_track("$ML_SERVER_URL")
print(f"[py] key={track.get('key')} bpm={track.get('bpm')}")

print("[py] Building MIDI...")
midi_path = tmp / "track.mid"
build_midi(track, midi_path, loop_bars=32)

print("[py] Rendering MIDI → WAV...")
raw_wav = tmp / "raw.wav"
midi_to_wav(midi_path, raw_wav)

print("[py] Applying lofi FX...")
lofi_wav = tmp / "lofi.wav"
apply_lofi_fx(raw_wav, lofi_wav)

print(f"[py] Looping to ${DURATION}s...")
loop_audio_to_duration(lofi_wav, Path("$AUDIO_WAV"), ${DURATION})
print(f"[py] Audio ready: $AUDIO_WAV")
PYEOF

ok "Audio generated: $(du -sh "$AUDIO_WAV" | cut -f1)"

# ── Render 4K video ───────────────────────────────────────────────────────────
OUTPUT_MP4="$OUTPUT_DIR/lofi_4k_${TIMESTAMP}.mp4"
log "[4/6] Rendering 4K (3840×2160) animated GIF background — ETA ~$(( DURATION / 60 / 3 )) minutes..."

# Text safe for ffmpeg drawtext (escape colons and apostrophes)
ESC_TITLE=$(printf '%s' "llooffiisounds" | sed "s/:/\\\\:/g; s/'/\\\\'/g")
ESC_SUB=$(printf '%s' "$OVERLAY_TITLE" | sed "s/:/\\\\:/g; s/'/\\\\'/g")

# Detect if the background is an animated GIF or a still image/webp
BG_EXT="${BG_GIF##*.}"
BG_EXT_LOWER=$(echo "$BG_EXT" | tr '[:upper:]' '[:lower:]')

if [[ "$BG_EXT_LOWER" == "gif" ]]; then
  # ── Animated GIF: loop infinitely, apply Gaussian blur ──────────────────────
  # Note: -stream_loop is NOT supported by the GIF demuxer (causes "Option not found").
  # Instead: use -ignore_loop 0 to honour the GIF loop count, then add
  # loop=-1:size=32767 as a video filter so the decoded frames repeat forever.
  log "  Mode: animated GIF loop + gblur(sigma=8) + Poppins font"
  # Build fontfile snippets (colon-prefixed so they chain into drawtext params)
  FF_B_ARG=""; [ -n "$FF_BOLD" ] && FF_B_ARG=":${FF_BOLD}"
  FF_M_ARG=""; [ -n "$FF_MED" ]  && FF_M_ARG=":${FF_MED}"
  ffmpeg -y \
    -ignore_loop 0 -i "$BG_GIF" \
    -i "$AUDIO_WAV" \
    -map 0:v -map 1:a \
    -vf "\
loop=-1:size=32767:start=0,\
scale=3840:2160:force_original_aspect_ratio=increase,\
crop=3840:2160,\
gblur=sigma=8,\
fps=30,\
format=yuv420p,\
drawtext=text='${ESC_TITLE}'${FF_B_ARG}:fontcolor=white@0.85:fontsize=80:x=(w-text_w)/2:y=(h/2)-60:\
shadowcolor=black@0.7:shadowx=4:shadowy=4,\
drawtext=text='${ESC_SUB}'${FF_M_ARG}:fontcolor=white@0.70:fontsize=54:x=(w-text_w)/2:y=(h/2)+40:\
shadowcolor=black@0.55:shadowx=3:shadowy=3\
" \
    -c:v libx264 -preset slow -crf 20 \
    -c:a aac -b:a 320k \
    -t "$DURATION" \
    -movflags +faststart \
    "$OUTPUT_MP4" \
    2>&1 | grep -E --line-buffered "frame=|fps=|time=|Error" | while IFS= read -r line; do
      echo "  $line"
    done
else
  # ── Still image fallback: Ken Burns slow zoom ───────────────────────────────
  log "  Mode: still image Ken Burns (fallback) + Poppins font"
  ZOOM_RATE=$(echo "scale=10; 0.08 / $DURATION" | bc)
  FF_B_ARG=""; [ -n "$FF_BOLD" ] && FF_B_ARG=":${FF_BOLD}"
  FF_M_ARG=""; [ -n "$FF_MED" ]  && FF_M_ARG=":${FF_MED}"
  ffmpeg -y \
    -loop 1 -framerate 30 -i "$BG_GIF" \
    -i "$AUDIO_WAV" \
    -vf "\
scale=3840:2160:force_original_aspect_ratio=increase,\
crop=3840:2160,\
zoompan=z='min(zoom+${ZOOM_RATE},1.08)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$((DURATION * 30)):s=3840x2160:fps=30,\
gblur=sigma=8,\
format=yuv420p,\
drawtext=text='${ESC_TITLE}'${FF_B_ARG}:fontcolor=white@0.85:fontsize=80:x=(w-text_w)/2:y=(h/2)-60:\
shadowcolor=black@0.7:shadowx=4:shadowy=4,\
drawtext=text='${ESC_SUB}'${FF_M_ARG}:fontcolor=white@0.70:fontsize=54:x=(w-text_w)/2:y=(h/2)+40:\
shadowcolor=black@0.55:shadowx=3:shadowy=3\
" \
    -c:v libx264 -preset slow -crf 20 \
    -c:a aac -b:a 320k \
    -t "$DURATION" \
    -movflags +faststart \
    -pix_fmt yuv420p \
    "$OUTPUT_MP4" \
    2>&1 | grep -E --line-buffered "frame=|fps=|time=|Error" | while IFS= read -r line; do
      echo "  $line"
    done
fi

ok "Video rendered: $OUTPUT_MP4"
VIDEO_SIZE=$(du -sh "$OUTPUT_MP4" | cut -f1)
ok "File size: $VIDEO_SIZE"

# ── Thumbnail ─────────────────────────────────────────────────────────────────
log "[5/6] Generating YouTube thumbnail (1280×720) from GIF first frame..."
THUMB_PATH="$THUMB_DIR/thumb_${TIMESTAMP}.jpg"

ESC_T1=$(printf '%s' "llooffiisounds" | sed "s/:/\\\\:/g; s/'/\\\\'/g")
ESC_T2=$(printf '%s' "${MOOD} lofi" | sed "s/:/\\\\:/g; s/'/\\\\'/g")
ESC_T3=$(printf '%s' "${HOURS} hour mix • ${MONTH}" | sed "s/:/\\\\:/g; s/'/\\\\'/g")

# For GIFs: read the first frame with -vframes 1. For still images: normal read.
if [[ "${BG_EXT_LOWER:-gif}" == "gif" ]]; then
  BG_FLAG=(-ignore_loop 0 -i "$BG_GIF")
else
  BG_FLAG=(-loop 1 -i "$BG_GIF")
fi

# Build fontfile snippets for thumbnail
TH_B_ARG=""; [ -n "${FF_BOLD:-}" ] && TH_B_ARG=":${FF_BOLD}"
TH_M_ARG=""; [ -n "${FF_MED:-}" ]  && TH_M_ARG=":${FF_MED}"
ffmpeg -y \
  "${BG_FLAG[@]}" \
  -vf "\
scale=1280:720:force_original_aspect_ratio=increase,\
crop=1280:720,\
eq=brightness=-0.05:saturation=1.18:contrast=1.05,\
gblur=sigma=4,\
drawtext=text='${ESC_T1}'${TH_B_ARG}:fontcolor=white@0.92:fontsize=48:\
x=(w-text_w)/2:y=72:\
shadowcolor=black@0.75:shadowx=3:shadowy=3:box=1:boxcolor=black@0.28:boxborderw=14,\
drawtext=text='${ESC_T2}'${TH_B_ARG}:fontcolor=white:fontsize=96:\
x=(w-text_w)/2:y=(h-text_h)/2-24:\
shadowcolor=black@0.85:shadowx=4:shadowy=4:box=1:boxcolor=black@0.32:boxborderw=20,\
drawtext=text='${ESC_T3}'${TH_M_ARG}:fontcolor=white@0.88:fontsize=38:\
x=(w-text_w)/2:y=h-72:\
shadowcolor=black@0.65:shadowx=2:shadowy=2:box=1:boxcolor=black@0.22:boxborderw=10\
" \
  -vframes 1 \
  -q:v 2 \
  "$THUMB_PATH" 2>/dev/null

ok "Thumbnail: $THUMB_PATH"

# ── Upload ────────────────────────────────────────────────────────────────────
if [ "$SKIP_UPLOAD" = "1" ]; then
  warn "[6/6] Skipping YouTube upload (SKIP_UPLOAD=1)"
else
  TOKEN_PATH="$SCRIPT_DIR/youtube_token.pickle"
  SECRET_PATH="$SCRIPT_DIR/client_secret.json"

  if [ ! -f "$TOKEN_PATH" ] && [ ! -f "$SECRET_PATH" ]; then
    warn "[6/6] No YouTube credentials — skipping upload."
    warn "  See SETUP.md §4 to configure OAuth2, then re-run."
  else
    log "[6/6] Uploading to YouTube (privacy=$PRIVACY)..."

    python3 - <<PYEOF
import sys, json, datetime, pickle, os
sys.path.insert(0, "$SCRIPT_DIR")
from pathlib import Path

video_path = Path("$OUTPUT_MP4")
title      = """$TITLE"""[:100]
thumb_path = Path("$THUMB_PATH")

description = """$DESCRIPTION"""[:5000]

tags = [
    "lofi", "lofi hip hop", "study music", "chill beats", "relax music",
    "focus music", "lofi mix", "${HOURS} hours lofi", "beats to study to",
    "lofi chill", "ambient music", "background music", "lofi 2025",
    "chillhop", "lofi beats", "anime lofi", "coffee shop music",
    "sleep music", "beats to sleep to", "beats to code to",
]

try:
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload
    from google.auth.transport.requests import Request
    from google_auth_oauthlib.flow import InstalledAppFlow
except ImportError:
    print("Missing google deps — pip install google-api-python-client google-auth-oauthlib")
    sys.exit(1)

TOKEN = Path("$TOKEN_PATH")
SECRET = Path("$SECRET_PATH")
SCOPES = ["https://www.googleapis.com/auth/youtube.upload",
          "https://www.googleapis.com/auth/youtube"]

creds = None
if TOKEN.exists():
    with open(TOKEN, "rb") as f:
        creds = pickle.load(f)

if not creds or not creds.valid:
    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
    else:
        flow = InstalledAppFlow.from_client_secrets_file(str(SECRET), SCOPES)
        has_display = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
        creds = flow.run_local_server(port=8085, open_browser=has_display)
    with open(TOKEN, "wb") as f:
        pickle.dump(creds, f)

yt = build("youtube", "v3", credentials=creds)

body = {
    "snippet": {
        "title": title,
        "description": description,
        "tags": tags[:500],
        "categoryId": "10",
    },
    "status": {
        "privacyStatus": "$PRIVACY",
        "selfDeclaredMadeForKids": False,
    },
}

media = MediaFileUpload(str(video_path), mimetype="video/mp4",
                        resumable=True, chunksize=8*1024*1024)
req = yt.videos().insert(part="snippet,status", body=body, media_body=media)

response = None
print(f"  Uploading {video_path.name} ({video_path.stat().st_size // 1_000_000}MB)...")
while response is None:
    status, response = req.next_chunk()
    if status:
        pct = int(status.progress() * 100)
        print(f"  Progress: {pct}%", end="\r")

video_id = response["id"]
url = f"https://www.youtube.com/watch?v={video_id}"
print(f"\n  ✓ Uploaded: {url}")

# Set thumbnail
if thumb_path.exists():
    try:
        yt.thumbnails().set(
            videoId=video_id,
            media_body=MediaFileUpload(str(thumb_path), mimetype="image/jpeg")
        ).execute()
        print(f"  ✓ Thumbnail set.")
    except Exception as e:
        print(f"  ⚠ Thumbnail set failed (needs channel verification): {e}")

# Save log
log_path = Path("$SCRIPT_DIR/upload_log.json")
log_data = []
if log_path.exists():
    try:
        log_data = json.loads(log_path.read_text())
    except Exception:
        pass
log_data.append({
    "id": video_id, "url": url, "title": title,
    "uploaded_at": datetime.datetime.utcnow().isoformat(),
    "file": str(video_path), "thumbnail": str(thumb_path),
})
log_path.write_text(json.dumps(log_data, indent=2))
PYEOF
    ok "Upload complete."
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C0}"
echo -e "${BOLD}${GREEN}  ✓  Pipeline complete!${C0}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C0}"
echo -e "  Video     : $OUTPUT_MP4"
echo -e "  Size      : $VIDEO_SIZE"
echo -e "  Thumbnail : $THUMB_PATH"
echo -e "  Title     : $TITLE"
echo ""
