#!/usr/bin/env bash
# stitch_and_prep.sh
# Assemble a YouTube-ready 3-hour lofi MP4 from pre-made audio clips and a background video.
# No Python, no ML server required — pure FFmpeg.
#
# Usage:
#   bash stitch_and_prep.sh [OPTIONS]
#
# Options:
#   -a, --audio-dir   DIR     Directory of audio clips (.mp3/.wav/.flac/.ogg) [required]
#   -b, --background  FILE    Background video (.mp4/.mov/.webm) or image (.jpg/.png/.webp)
#   -o, --output      FILE    Output MP4 path [default: output/lofi_stitched_TIMESTAMP.mp4]
#   -d, --duration    SECS    Total duration in seconds [default: 10800 = 3h]
#   -t, --title       TEXT    Channel name overlay text [default: "llooffiisounds"]
#   -s, --subtitle    TEXT    Subtitle overlay text [default: auto from timestamp]
#   -p, --privacy     VALUE   For upload_to_youtube.py: public|unlisted|private [default: public]
#   --no-fx                   Skip lofi audio FX (lowpass, crackle, warmth)
#   --no-upload               Skip YouTube upload step even if credentials exist
#   --crf             N       Video quality: 18 (best) → 28 (smallest) [default: 23]
#   --preset          VALUE   FFmpeg preset: ultrafast|fast|medium|slow [default: slow]
#   -h, --help                Show this help
#
# Examples:
#   # Stitch clips + animated background → 3h video + upload
#   bash stitch_and_prep.sh -a ~/Downloads/suno-clips/ -b ~/Downloads/anime-bg.mp4
#
#   # Just make the video, skip upload, custom duration
#   bash stitch_and_prep.sh -a ./clips/ -b ./bg.mp4 -d 7200 --no-upload
#
#   # Still image background, custom title
#   bash stitch_and_prep.sh -a ./clips/ -b ./bg.jpg -t "mysoundpage" -s "rainy night mix"

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
AUDIO_DIR=""
BACKGROUND=""
DURATION=10800
OUTPUT=""
CHANNEL_TITLE="llooffiisounds"
SUBTITLE=""
PRIVACY="public"
SKIP_FX=false
SKIP_UPLOAD=false
CRF=23
PRESET="slow"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK_DIR="$REPO_ROOT/output/pipeline"
VENV="$REPO_ROOT/.venv-pipeline"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠${NC} $*"; }
die()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✗${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--audio-dir)   AUDIO_DIR="$2";    shift 2 ;;
    -b|--background)  BACKGROUND="$2";   shift 2 ;;
    -o|--output)      OUTPUT="$2";       shift 2 ;;
    -d|--duration)    DURATION="$2";     shift 2 ;;
    -t|--title)       CHANNEL_TITLE="$2"; shift 2 ;;
    -s|--subtitle)    SUBTITLE="$2";     shift 2 ;;
    -p|--privacy)     PRIVACY="$2";      shift 2 ;;
    --no-fx)          SKIP_FX=true;      shift ;;
    --no-upload)      SKIP_UPLOAD=true;  shift ;;
    --crf)            CRF="$2";          shift 2 ;;
    --preset)         PRESET="$2";       shift 2 ;;
    -h|--help)        usage ;;
    *) die "Unknown option: $1  (use -h for help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
[[ -z "$AUDIO_DIR" ]] && die "No audio directory specified. Use -a /path/to/clips/"
[[ -d "$AUDIO_DIR" ]] || die "Audio directory not found: $AUDIO_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
[[ -z "$OUTPUT" ]] && OUTPUT="$WORK_DIR/lofi_stitched_${TIMESTAMP}.mp4"
[[ -z "$SUBTITLE" ]] && SUBTITLE="lofi hip hop • beats to study/relax to 🎵 $(date '+%B %Y')"

mkdir -p "$WORK_DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Check deps
# ---------------------------------------------------------------------------
log "Checking dependencies..."
command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg not found — sudo apt install ffmpeg"
FFMPEG_VER=$(ffmpeg -version 2>&1 | head -1)
log "  $FFMPEG_VER"

HOURS=$((DURATION / 3600))
MINS=$(( (DURATION % 3600) / 60 ))
log "Target duration: ${HOURS}h ${MINS}m (${DURATION}s)"

# ---------------------------------------------------------------------------
# Step 1: Collect audio clips
# ---------------------------------------------------------------------------
log "━━━ [1/5] Scanning audio clips in: $AUDIO_DIR"
CLIP_LIST=()
while IFS= read -r -d '' f; do
  CLIP_LIST+=("$f")
done < <(find "$AUDIO_DIR" -maxdepth 2 -type f \( \
  -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \
  -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.aac" \
\) -print0 | sort -z)

[[ ${#CLIP_LIST[@]} -eq 0 ]] && die "No audio files found in $AUDIO_DIR"
log "  Found ${#CLIP_LIST[@]} clip(s)"
for f in "${CLIP_LIST[@]}"; do
  CLIP_DUR=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null || echo "?")
  log "    $(basename "$f")  [${CLIP_DUR%.*}s]"
done

# ---------------------------------------------------------------------------
# Step 2: Stitch audio clips → raw concat
# ---------------------------------------------------------------------------
log "━━━ [2/5] Stitching clips..."
CONCAT_LIST="$TMP/concat.txt"
> "$CONCAT_LIST"
for f in "${CLIP_LIST[@]}"; do
  echo "file '$(realpath "$f")'" >> "$CONCAT_LIST"
done

RAW_CONCAT="$TMP/raw_concat.wav"
log "  Concatenating ${#CLIP_LIST[@]} clips..."
ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" \
  -ar 44100 -ac 2 \
  "$RAW_CONCAT" 2>/dev/null
ok "  Concat done: $(du -sh "$RAW_CONCAT" | cut -f1)"

# ---------------------------------------------------------------------------
# Step 3: Apply lofi FX (optional)
# ---------------------------------------------------------------------------
if $SKIP_FX; then
  warn "Skipping lofi FX (--no-fx flag set)"
  PROCESSED_AUDIO="$RAW_CONCAT"
else
  log "━━━ [3/5] Applying lofi FX (lowpass + warmth + vinyl crackle)..."
  FX_AUDIO="$TMP/lofi_fx.wav"
  FX_CHAIN=(
    "[0:a]"
    "aformat=sample_rates=44100,"
    "lowpass=f=3500,"
    "highpass=f=60,"
    "aecho=0.8:0.9:60:0.3,"
    "atempo=0.97,"
    "volume=0.82"
    "[lofi];"
    "anoisesrc=r=44100:color=pink:a=0.008:d=9999"
    "[noise];"
    "[lofi][noise]amix=inputs=2:weights=1 0.045[out]"
  )
  FX_CHAIN_STR="${FX_CHAIN[*]}"
  FX_CHAIN_STR="${FX_CHAIN_STR// /}"  # collapse spaces inside chain

  ffmpeg -y \
    -i "$RAW_CONCAT" \
    -filter_complex "$FX_CHAIN_STR" \
    -map "[out]" \
    -ar 44100 -ac 2 \
    "$FX_AUDIO" 2>/dev/null
  ok "  FX applied: $(du -sh "$FX_AUDIO" | cut -f1)"
  PROCESSED_AUDIO="$FX_AUDIO"
fi

# ---------------------------------------------------------------------------
# Step 4: Loop audio to target duration
# ---------------------------------------------------------------------------
log "━━━ [4/5] Looping audio to ${DURATION}s..."
LONG_AUDIO="$TMP/long_audio.wav"
ffmpeg -y \
  -stream_loop -1 \
  -i "$PROCESSED_AUDIO" \
  -t "$DURATION" \
  -ar 44100 -ac 2 \
  "$LONG_AUDIO" 2>/dev/null
ok "  Audio ready: $(du -sh "$LONG_AUDIO" | cut -f1)"

# ---------------------------------------------------------------------------
# Step 5: Composite video
# ---------------------------------------------------------------------------
log "━━━ [5/5] Rendering video..."

# Escape text for FFmpeg drawtext
esc_text() { printf '%s' "$1" | sed "s/:/\\\\:/g; s/'/\\\\'/g"; }
TITLE_ESC=$(esc_text "$CHANNEL_TITLE")
SUBTITLE_ESC=$(esc_text "$SUBTITLE")

if [[ -n "$BACKGROUND" && -f "$BACKGROUND" ]]; then
  EXT="${BACKGROUND##*.}"
  EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

  case "$EXT_LOWER" in
    mp4|mov|webm|mkv|avi)
      # ── Animated background (MP4/video) ──
      log "  Background mode: animated video (stream_loop)"
      log "  Rendering ${DURATION}s @ 1920x1080 — ETA ~$(( DURATION / 60 / 3 )) min..."
      ffmpeg -y \
        -stream_loop -1 -i "$BACKGROUND" \
        -i "$LONG_AUDIO" \
        -map 0:v -map 1:a \
        -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,\
drawtext=text='${TITLE_ESC}':fontcolor=white@0.35:fontsize=28:x=40:y=h-60:\
shadowcolor=black@0.5:shadowx=2:shadowy=2,\
drawtext=text='${SUBTITLE_ESC}':fontcolor=white@0.45:fontsize=17:x=40:y=h-32:\
shadowcolor=black@0.4:shadowx=1:shadowy=1" \
        -c:v libx264 -preset "$PRESET" -crf "$CRF" \
        -c:a aac -b:a 192k \
        -t "$DURATION" \
        -movflags +faststart \
        "$OUTPUT" 2>&1 | \
          grep -E --line-buffered "(frame=|fps=|time=|error|Error)" | \
          while IFS= read -r line; do echo "  $line"; done
      ;;

    jpg|jpeg|png|webp|bmp)
      # ── Still image background (Ken Burns zoom-pan) ──
      log "  Background mode: still image (Ken Burns effect)"
      ZOOM_RATE=$(echo "scale=8; 0.08 / $DURATION" | bc)
      log "  Rendering ${DURATION}s @ 1920x1080 — ETA ~$(( DURATION / 60 / 5 )) min..."
      ffmpeg -y \
        -loop 1 -framerate 25 -i "$BACKGROUND" \
        -i "$LONG_AUDIO" \
        -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,\
zoompan=z='min(zoom+${ZOOM_RATE},1.08)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$(( DURATION * 25 )):s=1920x1080:fps=25,\
drawtext=text='${TITLE_ESC}':fontcolor=white@0.35:fontsize=28:x=40:y=h-60:\
shadowcolor=black@0.5:shadowx=2:shadowy=2,\
drawtext=text='${SUBTITLE_ESC}':fontcolor=white@0.45:fontsize=17:x=40:y=h-32:\
shadowcolor=black@0.4:shadowx=1:shadowy=1" \
        -c:v libx264 -preset "$PRESET" -crf "$CRF" \
        -c:a aac -b:a 192k \
        -t "$DURATION" \
        -movflags +faststart \
        "$OUTPUT" 2>&1 | \
          grep -E --line-buffered "(frame=|fps=|time=|error|Error)" | \
          while IFS= read -r line; do echo "  $line"; done
      ;;

    *)
      warn "Unrecognised background extension .$EXT_LOWER — using dark fallback"
      BACKGROUND=""
      ;;
  esac
fi

if [[ -z "$BACKGROUND" ]] || [[ ! -f "$BACKGROUND" ]]; then
  # ── Dark gradient fallback (no background asset) ──
  log "  Background mode: dark gradient fallback"
  ffmpeg -y \
    -f lavfi -i "color=c=0x0d0d1a:size=1920x1080:rate=25" \
    -i "$LONG_AUDIO" \
    -vf "drawtext=text='${TITLE_ESC}':fontcolor=white@0.4:fontsize=40:\
x=(w-text_w)/2:y=(h-text_h)/2:shadowcolor=black@0.5:shadowx=3:shadowy=3,\
drawtext=text='${SUBTITLE_ESC}':fontcolor=white@0.3:fontsize=22:\
x=(w-text_w)/2:y=(h+text_h)/2+20:shadowcolor=black@0.4:shadowx=1:shadowy=1" \
    -c:v libx264 -preset "$PRESET" -crf "$CRF" \
    -c:a aac -b:a 192k \
    -t "$DURATION" \
    -movflags +faststart \
    "$OUTPUT" 2>/dev/null
fi

ok "Video rendered: $OUTPUT"
FILE_SIZE=$(du -sh "$OUTPUT" | cut -f1)
ok "File size: $FILE_SIZE"

# ---------------------------------------------------------------------------
# Optional: Upload to YouTube
# ---------------------------------------------------------------------------
if $SKIP_UPLOAD; then
  warn "Skipping YouTube upload (--no-upload)"
else
  TOKEN_PATH="$SCRIPT_DIR/youtube_token.pickle"
  CLIENT_SECRET_PATH="$SCRIPT_DIR/client_secret.json"

  if [[ ! -f "$TOKEN_PATH" && ! -f "$CLIENT_SECRET_PATH" ]]; then
    warn "No YouTube credentials found — skipping upload."
    warn "  See SETUP.md §4 to configure OAuth2."
  else
    log "Uploading to YouTube (privacy=$PRIVACY)..."
    # Activate venv if present
    if [[ -d "$VENV" ]]; then
      source "$VENV/bin/activate"
    fi
    python3 "$SCRIPT_DIR/upload_to_youtube.py" \
      --video "$OUTPUT" \
      --title "$SUBTITLE" \
      --privacy "$PRIVACY"
    ok "Upload complete."
  fi
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✓  All done!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Output : $OUTPUT"
echo "  Size   : $FILE_SIZE"
echo "  Channel: $CHANNEL_TITLE"
echo ""
