# Lofi Pipeline — Oracle VM Setup Guide

## What this does

Every 3 hours, automatically:
1. Calls the local ML server → gets a unique lofi chord/melody/BPM blueprint
2. Synthesizes MIDI audio → renders via fluidsynth → applies lofi FX via FFmpeg
3. Loops audio to 3 hours → combines with animated background video
4. Uploads to YouTube channel **llooffiisounds** with auto-generated titles

---

## One-time setup on Oracle VM

### 1. Clone + copy background assets

```bash
git clone https://github.com/amnindersingh12/lofi-engine /opt/lofi-engine
cd /opt/lofi-engine
# Copy your background images to public/assets/background/ (webp/jpg/png)
```

### 2. Install system deps

```bash
# Ubuntu/Oracle Linux
sudo apt update
sudo apt install -y python3 python3-venv ffmpeg fluidsynth

# Install a GM soundfont (required for MIDI → WAV)
sudo apt install -y fluid-soundfont-gm
# This installs to /usr/share/sounds/sf2/FluidR3_GM.sf2
# The script auto-detects this path.
```

### 3. Set up the ML server Python environment

```bash
cd /opt/lofi-engine
python3 -m venv .venv-ml
source .venv-ml/bin/activate
pip install -r integrations/jacbz-lofi/server/requirements.txt
deactivate
```

### 4. Set up YouTube API credentials

1. Go to https://console.cloud.google.com/
2. Create a project (e.g., "lofi-youtube")
3. Enable **YouTube Data API v3**
4. Go to **Credentials** → **Create credentials** → **OAuth 2.0 Client ID**
5. Application type: **Desktop app**
6. Download the JSON → save as:
   ```
   /opt/lofi-engine/scripts/pipeline/client_secret.json
   ```

#### First-run auth (do this once with a terminal, not headless)

```bash
cd /opt/lofi-engine
python3 scripts/pipeline/upload_to_youtube.py --video /dev/null --privacy unlisted
# This opens a browser or prints a URL for console auth
# After auth, token is saved to scripts/pipeline/youtube_token.pickle
# All future runs use the saved token — no browser needed
```

### 5. Test the full pipeline manually

```bash
cd /opt/lofi-engine
bash scripts/pipeline/lofi_pipeline.sh
# Takes ~20-40 minutes for a 3h video (FFmpeg rendering time)
# Check: output/pipeline/lofi_TIMESTAMP.mp4
```

### 6. Install as systemd timer (runs every 3 hours, forever)

```bash
# Copy service + timer files
sudo cp scripts/pipeline/lofi-pipeline@.service /etc/systemd/system/
sudo cp scripts/pipeline/lofi-pipeline@.timer   /etc/systemd/system/

# Update WorkingDirectory to actual path
sudo sed -i 's|/opt/lofi-engine|'"$PWD"'|g' /etc/systemd/system/lofi-pipeline@.service

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable --now "lofi-pipeline@$(whoami).timer"

# Check status
systemctl status "lofi-pipeline@$(whoami).timer"
journalctl -u "lofi-pipeline@$(whoami).service" -f
```

### 7. Monitor

```bash
# Live log
tail -f /var/log/lofi_pipeline.log

# Upload history
cat /opt/lofi-engine/scripts/pipeline/upload_log.json | python3 -m json.tool
```

---

## Environment variables you can override

| Variable | Default | Description |
|---|---|---|
| `ML_SERVER_URL` | `http://localhost:5050` | ML server endpoint |
| `LOFI_DURATION` | `10800` | Video duration in seconds (10800 = 3h) |
| `LOFI_PRIVACY` | `public` | YouTube privacy: `public`, `unlisted`, `private` |

Set in `/etc/systemd/system/lofi-pipeline@.service` under `[Service]`.

---

## YouTube quota notes

- YouTube Data API v3 gives **10,000 units/day** free
- A video upload costs **1,600 units**
- At 3h per video: **8 uploads/day** max on free quota
- For the llooffiisounds channel, 1 upload every 3h = **8/day** — right at the limit
- If you want buffer, set `LOFI_DURATION=14400` (4h) and upload every 4h (6/day)

---

## Troubleshooting

**"no soundfont found"**
```bash
sudo apt install fluid-soundfont-gm
# or: sudo apt install musescore-general-soundfont
```

**"ML server unreachable"** — pipeline auto-falls back to procedural generation. No action needed.

**"quota exceeded"** — lower upload frequency. Edit the timer: `OnUnitActiveSec=4h`

**Token expired** — delete `scripts/pipeline/youtube_token.pickle` and re-run the first-run auth step once.

---

## Bring-Your-Own-Assets mode (`stitch_and_prep.sh`)

Use this when you have pre-made audio clips (from Suno, Udio, ElevenLabs, etc.) and a
background video (from RunwayML, Pika Labs, Pixabay, lofi.cafe, etc.).
No Python, no ML server needed — pure FFmpeg.

```bash
# Basic usage: stitch clips + animated video → 3h MP4 → upload
bash scripts/pipeline/stitch_and_prep.sh \
  -a ~/Downloads/suno-clips/ \
  -b ~/Downloads/anime-bg.mp4

# Still image background, custom channel name, skip upload
bash scripts/pipeline/stitch_and_prep.sh \
  -a ./clips/ \
  -b ./bg.jpg \
  -t "mysoundpage" \
  --no-upload

# 4h video, unlisted, skip lofi FX (keep clips as-is)
bash scripts/pipeline/stitch_and_prep.sh \
  -a ./clips/ -b ./bg.mp4 \
  -d 14400 -p unlisted --no-fx
```

### Options reference

| Flag | Default | Description |
|---|---|---|
| `-a / --audio-dir` | **required** | Folder of `.mp3`/`.wav`/`.flac`/`.ogg` clips |
| `-b / --background` | none | Background `.mp4`/`.mov`/`.webm` (animated) or `.jpg`/`.png`/`.webp` (still) |
| `-o / --output` | auto-timestamped | Output MP4 path |
| `-d / --duration` | `10800` | Total seconds (10800 = 3h) |
| `-t / --title` | `llooffiisounds` | Channel name overlay |
| `-s / --subtitle` | auto | Subtitle / track name overlay |
| `-p / --privacy` | `public` | `public` / `unlisted` / `private` |
| `--no-fx` | off | Skip lofi audio FX (keep clips raw) |
| `--no-upload` | off | Skip YouTube upload |
| `--crf` | `23` | Video quality (18=best, 28=smallest) |
| `--preset` | `slow` | FFmpeg encode speed preset |

### Audio FX applied by default

1. Lowpass @ 3500 Hz (removes harsh highs)
2. Highpass @ 60 Hz (removes sub-rumble)
3. Subtle room echo (tape feel)
4. `atempo=0.97` — slight tape slowdown
5. Pink noise vinyl crackle (blended at 4.5%)

---

## Animated background support in `generate_lofi_video.py`

The ML-server pipeline now auto-detects your asset type.

Place assets in `public/assets/background/`:

| File type | Render mode |
|---|---|
| `.mp4` / `.mov` / `.webm` | **stream_loop -1** — loops the video seamlessly |
| `.jpg` / `.png` / `.webp` | **Ken Burns** — slow zoom-pan over the still image |
| *(nothing)* | **Dark gradient fallback** — channel name centered |

Or pass an explicit file with `--background`:

```bash
python3 scripts/pipeline/generate_lofi_video.py \
  --background ~/Downloads/anime-rain-loop.mp4 \
  --duration 10800 \
  --output output/pipeline/lofi_custom.mp4
```

**Asset priority order:** `--background` arg → video in `background/` → image in `background/` → dark fallback.
