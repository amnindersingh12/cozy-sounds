#!/usr/bin/env python3
"""
generate_lofi_video.py
Headless lofi generation pipeline for Oracle VM.

Steps:
  1. Fetch a lofi track blueprint from the ML server (chord/melody/BPM/key)
  2. Render it to MIDI using pretty_midi
  3. Convert MIDI → WAV via fluidsynth + LoFi soundfont
  4. Apply lofi audio effects (lowpass, vinyl crackle, tape warmth) via FFmpeg
  5. Loop audio to 3 hours
  6. Combine with animated background video via FFmpeg
  7. Output final MP4

Usage:
  python generate_lofi_video.py [--duration 10800] [--output out.mp4] [--server http://localhost:5050]
"""

import argparse
import json
import math
import os
import random
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent.parent
ASSETS_DIR = REPO_ROOT / "public" / "assets"
BACKGROUND_DIR = ASSETS_DIR / "background"
WAIFU_CACHE_DIR = REPO_ROOT / "output" / "waifu-cache"
SOUNDFONT_PATHS = [
    Path("/usr/share/sounds/sf2/FluidR3_GM.sf2"),
    Path("/usr/share/soundfonts/FluidR3_GM.sf2"),
    Path(os.path.expanduser("~/soundfonts/FluidR3_GM.sf2")),
    REPO_ROOT / "scripts" / "pipeline" / "FluidR3_GM.sf2",
]
DEFAULT_DURATION_SECS = 10800  # 3 hours
DEFAULT_SERVER = "http://localhost:5050"

# nekos.best GIF endpoints — verified via /api/v2/endpoints
# NOTE: neko/kitsune/waifu/husbando return PNG, not GIF.
WAIFU_ENDPOINTS = [
    "hug", "dance", "pat", "smile", "happy", "wave", "cuddle",
    "spin", "kiss", "cry", "laugh", "wink", "blush", "smug",
    "poke", "highfive", "nom", "bite", "slap", "bonk", "yeet",
]
NEKOS_BASE = "https://nekos.best/api/v2/"

# ---------------------------------------------------------------------------
# Music theory constants — matching the original jacbz/Lofi Tone.js engine
# ---------------------------------------------------------------------------

# Chromatic note names (key 1 = C, key 2 = C#, etc.)
CHROMATIC_NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# Mode interval patterns (semitones from root) — 7 modes
# mode 1 = ionian (major), 2 = dorian, 3 = phrygian, 4 = lydian,
# 5 = mixolydian, 6 = aeolian (minor), 7 = locrian
MODE_INTERVALS = {
    1: [0, 2, 4, 5, 7, 9, 11],   # ionian (major)
    2: [0, 2, 3, 5, 7, 9, 10],   # dorian
    3: [0, 1, 3, 5, 7, 8, 10],   # phrygian
    4: [0, 2, 4, 6, 7, 9, 11],   # lydian
    5: [0, 2, 4, 5, 7, 9, 10],   # mixolydian
    6: [0, 2, 3, 5, 7, 8, 10],   # aeolian (natural minor)
    7: [0, 1, 3, 5, 6, 8, 10],   # locrian
}

# Triad quality for each scale degree in each mode
# (semitones from chord root): [root, third, fifth]
# Major = [0,4,7], minor = [0,3,7], dim = [0,3,6], aug = [0,4,8]
def _build_diatonic_triad(scale_intervals: list[int], degree_idx: int) -> list[int]:
    """Build a triad from the scale, returning intervals from the chord root."""
    root = scale_intervals[degree_idx]
    third = scale_intervals[(degree_idx + 2) % 7]
    fifth = scale_intervals[(degree_idx + 4) % 7]
    # Wrap intervals to stay within 12 semitones
    i3 = (third - root) % 12
    i5 = (fifth - root) % 12
    return [0, i3, i5]

# Key name → MIDI root note (octave 3)
KEY_TO_MIDI = {
    "C": 48, "C#": 49, "D": 50, "D#": 51, "E": 52, "F": 53,
    "F#": 54, "G": 55, "G#": 56, "A": 57, "A#": 58, "B": 59,
}

# Common lofi chord progressions for fallback (scale degrees, 1-indexed)
LOFI_PROGRESSIONS = [
    [2, 5, 1, 6],      # ii-V-I-vi (classic jazz lofi)
    [1, 6, 4, 5],      # I-vi-IV-V (50s progression)
    [1, 5, 6, 4],      # I-V-vi-IV (pop progression)
    [2, 5, 1, 4],      # ii-V-I-IV
    [6, 4, 1, 5],      # vi-IV-I-V
    [1, 4, 6, 5],      # I-IV-vi-V
    [2, 5, 3, 6],      # ii-V-iii-vi (Coltrane)
    [1, 3, 4, 5],      # I-iii-IV-V
    [4, 5, 3, 6],      # IV-V-iii-vi
    [2, 3, 4, 5],      # ii-iii-IV-V (ascending)
]

# Bass patterns from producer_presets.ts: [startBeat, duration] tuples
BASS_PATTERNS = [
    [(0, 4)],                             # whole note
    [(0, 2), (2, 2)],                     # half notes
    [(0, 3), (3, 1)],                     # dotted half + quarter
    [(0, 3.5), (3.5, 0.5)],              # long + ghost note
    [(0, 1.5), (1.5, 1.5), (3, 1)],      # syncopated
]

# First-beat arpeggio patterns from producer_presets.ts (scale-degree offsets)
ARPEGGIO_PATTERNS = [
    [1, 5, 8, 9, 10],         # Preset1
    [1, 5, 8, 5, 10, 5, 8],   # alternate
    [1, 3, 5, 8],              # simple triad + octave
]

# Melody note mapping from model output (constants.py):
#   0 = rest
#   1-7 = scale degrees in octave 1
#   8-14 = scale degrees in octave 2
MELODY_REST = 0
NOTES_PER_CHORD = 8   # MELODY_DISCRETIZATION_LENGTH from constants.py


# ---------------------------------------------------------------------------
# ML Server fetch
# ---------------------------------------------------------------------------
def fetch_track(server_url: str, retries: int = 3) -> dict:
    url = f"{server_url.rstrip('/')}/generate"
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=15) as resp:
                data = json.loads(resp.read())
                # The server returns a pre-serialized JSON string via jsonpickle,
                # so json.loads may give back a string — decode it again if so.
                if isinstance(data, str):
                    data = json.loads(data)
                return data
        except Exception as e:
            print(f"  [fetch] attempt {attempt + 1} failed: {e}")
            if attempt < retries - 1:
                time.sleep(2)
    # Fallback: random procedural track
    print("  [fetch] ML server unreachable — using procedural fallback")
    return _procedural_fallback()


def _procedural_fallback() -> dict:
    """Generate a musically coherent fallback track using common lofi progressions."""
    prog = random.choice(LOFI_PROGRESSIONS)
    # Prefer aeolian (minor) or dorian for lofi mood — occasional major
    mode_weights = [0.08, 0.25, 0.05, 0.05, 0.10, 0.37, 0.10]
    mode = random.choices(range(1, 8), weights=mode_weights, k=1)[0]

    bpm = random.choice([75, 80, 80, 85, 85, 85, 90, 90])

    # Generate melody notes using scale degrees (model format: 0=rest, 1-14=notes)
    melodies = []
    for _ in prog:
        mel = []
        for j in range(NOTES_PER_CHORD):
            if random.random() < 0.35:
                mel.append(MELODY_REST)  # rest
            else:
                # Prefer lower octave scale degrees (1-7) with some upper (8-14)
                if random.random() < 0.7:
                    mel.append(random.randint(1, 7))
                else:
                    mel.append(random.randint(8, 14))
            melodies.append(mel)

    return {
        "key": random.randint(1, 12),
        "mode": mode,
        "bpm": bpm,
        "energy": round(random.uniform(0.15, 0.45), 3),
        "valence": round(random.uniform(0.2, 0.55), 3),
        "chords": prog,
        "melodies": melodies,
    }


def _get_scale_midi_notes(root_midi: int, mode: int) -> list[int]:
    """Return the 7 MIDI note numbers for the given root and mode."""
    intervals = MODE_INTERVALS.get(mode, MODE_INTERVALS[1])
    return [root_midi + iv for iv in intervals]


# ---------------------------------------------------------------------------
# MIDI generation — faithfully reproducing the jacbz/Lofi producer logic
# ---------------------------------------------------------------------------
def build_midi(track: dict, output_path: Path, loop_bars: int = 16) -> Path:
    try:
        import pretty_midi
    except ImportError:
        print("  [midi] pretty_midi not installed — pip install pretty_midi")
        sys.exit(1)

    bpm = max(70, min(100, track.get("bpm", 80)))
    # Snap BPM to nearest 5 (matching original: 70/75/80/85/90/95/100)
    bpm = round(bpm / 5) * 5

    key_idx = (track.get("key", 1) - 1) % 12
    mode = max(1, min(7, track.get("mode", 1)))
    root_midi = 48 + key_idx   # C3 = 48, root in octave 3
    energy = track.get("energy", 0.3)
    valence = track.get("valence", 0.4)
    chords = track.get("chords", [2, 5, 1, 6])
    melodies = track.get("melodies", [])

    scale_notes = _get_scale_midi_notes(root_midi, mode)
    scale_intervals = MODE_INTERVALS.get(mode, MODE_INTERVALS[1])

    pm = pretty_midi.PrettyMIDI(initial_tempo=bpm)
    beats_per_bar = 4
    secs_per_beat = 60.0 / bpm
    bar_dur = beats_per_bar * secs_per_beat

    # Instruments — select based on energy/valence like the original presets
    # Electric Piano 1 (program 4) for harmony — the signature lofi sound
    epiano = pretty_midi.Instrument(program=4, name="ElectricPiano")
    # Soft Piano (program 0) or Electric Piano for melody
    if energy < 0.3 and valence < 0.5:
        melody_inst = pretty_midi.Instrument(program=0, name="SoftPiano")
        melody_vel_range = (40, 62)
    elif energy < 0.6:
        melody_inst = pretty_midi.Instrument(program=4, name="MelodyEPiano")
        melody_vel_range = (45, 68)
    else:
        melody_inst = pretty_midi.Instrument(program=26, name="ElectricGuitar")
        melody_vel_range = (50, 72)

    # Bass Guitar (program 33 = Finger Bass)
    bass = pretty_midi.Instrument(program=33, name="Bass")
    # Harp for arpeggios (program 46)
    harp = pretty_midi.Instrument(program=46, name="Harp")

    # Select a bass pattern based on energy
    bass_pattern_idx = min(len(BASS_PATTERNS) - 1, int(energy * len(BASS_PATTERNS)))

    # Structure: 1 bar intro silence + main iterations + 2 bar outro
    intro_bars = 1
    num_iterations = max(1, math.ceil((loop_bars - 3) / max(len(chords), 1)))
    total_chord_bars = len(chords) * num_iterations
    outro_chords = min(2, len(chords))
    total_bars = intro_bars + total_chord_bars + outro_chords + 1  # +1 trailing silence
    print(f"  [midi] structure: {intro_bars}bar intro + {num_iterations}×{len(chords)} chords + "
          f"{outro_chords}bar outro = {total_bars} bars total")

    def _add_iteration(iteration_start_bar: int, chord_limit: int | None = None):
        """Produce one iteration of the chord progression."""
        active_chords = chords[:chord_limit] if chord_limit else chords
        for chord_idx, chord_degree_raw in enumerate(active_chords):
            bar_idx = iteration_start_bar + chord_idx
            t_start = bar_idx * bar_dur

            # Chord degree (1-7)
            degree = max(1, min(7, chord_degree_raw))
            degree_idx = degree - 1

            # Get the chord root from the scale
            chord_root = scale_notes[degree_idx]

            # Build proper diatonic triad intervals
            triad = _build_diatonic_triad(scale_intervals, degree_idx)

            # ── Harmony: Electric Piano chord (full bar) ──
            # Voiced in octave 4 with first inversion (root up an octave)
            harmony_oct = 12  # shift chord up one octave
            harm_notes = [chord_root + harmony_oct + iv for iv in triad]
            # First inversion: move root up an octave
            harm_notes[0] += 12
            # Add 7th for jazzy feel (diatonic 7th)
            seventh_interval = (scale_intervals[(degree_idx + 6) % 7] - scale_intervals[degree_idx]) % 12
            harm_notes.append(chord_root + harmony_oct + seventh_interval)

            harm_vel = int(55 + energy * 25)
            for pitch in harm_notes:
                epiano.notes.append(pretty_midi.Note(
                    velocity=random.randint(max(40, harm_vel - 8), harm_vel + 5),
                    pitch=max(36, min(96, pitch)),
                    start=t_start + random.uniform(0, 0.02),
                    end=t_start + bar_dur - random.uniform(0.02, 0.08),
                ))

            # ── Bass line: root note with pattern variation ──
            bass_vel = int(60 + energy * 20)
            bp_idx = (bass_pattern_idx + chord_idx) % len(BASS_PATTERNS)
            bass_pattern = BASS_PATTERNS[bp_idx]
            for start_beat, duration in bass_pattern:
                bass_pitch = chord_root - 12  # bass in octave 2
                bass.notes.append(pretty_midi.Note(
                    velocity=random.randint(max(45, bass_vel - 8), bass_vel + 5),
                    pitch=max(28, min(55, bass_pitch)),
                    start=t_start + start_beat * secs_per_beat + random.uniform(0, 0.01),
                    end=t_start + (start_beat + duration) * secs_per_beat - random.uniform(0.02, 0.06),
                ))

            # ── First-beat arpeggio (harp/piano, like original) ──
            if energy > 0.2 or random.random() < 0.6:
                arp_pattern = ARPEGGIO_PATTERNS[chord_idx % len(ARPEGGIO_PATTERNS)]
                arp_vel = int(30 + valence * 25)
                for arp_i, scale_offset in enumerate(arp_pattern):
                    # Map arpeggio pattern scale offset to actual pitch
                    arp_degree = (degree_idx + scale_offset - 1) % 7
                    arp_octave = (degree_idx + scale_offset - 1) // 7
                    arp_pitch = scale_notes[arp_degree] + arp_octave * 12
                    arp_time = t_start + arp_i * (secs_per_beat / 2)  # eighth notes
                    arp_dur = bar_dur - arp_i * (secs_per_beat / 2) - 0.05
                    if arp_dur > 0.1:
                        harp.notes.append(pretty_midi.Note(
                            velocity=random.randint(max(25, arp_vel - 5), arp_vel + 8),
                            pitch=max(48, min(84, arp_pitch)),
                            start=arp_time + random.uniform(0, 0.015),
                            end=arp_time + arp_dur,
                        ))

            # ── Melody: using the model's note mapping ──
            if melodies:
                mel = melodies[chord_idx % len(melodies)]
                prev_note = None
                for i, note_val in enumerate(mel):
                    if note_val == MELODY_REST:
                        continue  # rest — skip
                    # Map note value to scale degree + octave
                    # 1-7 = octave 1 scale degrees, 8-14 = octave 2
                    if 1 <= note_val <= 7:
                        mel_degree = (note_val - 1) % 7
                        mel_octave = 1
                    elif 8 <= note_val <= 14:
                        mel_degree = (note_val - 8) % 7
                        mel_octave = 2
                    else:
                        continue

                    mel_pitch = scale_notes[mel_degree] + mel_octave * 12
                    mel_pitch = max(60, min(84, mel_pitch))

                    # Sparse density — skip some notes for breathing room
                    if random.random() < 0.25:
                        continue

                    # Skip consecutive identical pitches sometimes
                    if mel_pitch == prev_note and random.random() < 0.5:
                        continue

                    note_t = t_start + i * (bar_dur / max(len(mel), 1))
                    note_dur = secs_per_beat * random.uniform(0.5, 1.2)

                    melody_inst.notes.append(pretty_midi.Note(
                        velocity=random.randint(*melody_vel_range),
                        pitch=mel_pitch,
                        start=note_t + random.uniform(0, 0.025),  # humanize
                        end=note_t + note_dur,
                    ))
                    prev_note = mel_pitch

    # ── Build the song structure ──
    current_bar = intro_bars  # start after intro silence

    # Main iterations
    for iteration in range(num_iterations):
        _add_iteration(current_bar)
        current_bar += len(chords)

    # Outro: first 2 chords only (for fade out)
    _add_iteration(current_bar, chord_limit=outro_chords)

    pm.instruments.extend([epiano, bass, harp, melody_inst])
    pm.write(str(output_path))
    key_name = CHROMATIC_NOTES[key_idx]
    mode_names = ["ionian", "dorian", "phrygian", "lydian", "mixolydian", "aeolian", "locrian"]
    mode_name = mode_names[mode - 1] if mode <= 7 else "ionian"
    print(f"  [midi] written: {output_path} | {key_name} {mode_name} | BPM={bpm} | "
          f"energy={energy:.2f} valence={valence:.2f} | {total_bars} bars")
    return output_path


# ---------------------------------------------------------------------------
# Audio rendering
# ---------------------------------------------------------------------------
def find_soundfont() -> Path | None:
    for p in SOUNDFONT_PATHS:
        if p.exists():
            return p
    return None


def midi_to_wav(midi_path: Path, wav_path: Path) -> Path:
    sf = find_soundfont()
    if sf is None:
        print("  [wav] no soundfont found — see SETUP.md for install instructions")
        sys.exit(1)

    cmd = [
        "fluidsynth", "-ni", str(sf), str(midi_path),
        "-F", str(wav_path), "-r", "44100", "-q"
    ]
    subprocess.run(cmd, check=True)
    print(f"  [wav] rendered: {wav_path}")
    return wav_path


def apply_lofi_fx(input_wav: Path, output_wav: Path) -> Path:
    """Apply lofi filter chain matching the original Tone.js engine sound.

    Inspired by the original's Reverb (decay=2, wet=0.2), low-pass filter
    at ~2400 Hz on drums, and vinyl crackle/rain FX layers.

    Chain: warm lowpass → gentle highpass → lush reverb (via aecho+chorus) →
           slight tape slowdown → vinyl crackle layer → final compression.
    """
    fx_chain = (
        "[0:a]"
        "aformat=sample_rates=44100,"
        # Warm lowpass — gentler than before (2800 Hz, soft roll-off)
        "lowpass=f=2800:p=1,"
        # Remove sub-rumble cleanly
        "highpass=f=50:p=1,"
        # Lush reverb simulation via cascaded delays (mimics Tone.Reverb decay=2, wet=0.2)
        "aecho=0.8:0.88:32|40|48:0.15|0.12|0.08,"
        # Warm chorus for width and analog feel
        "chorus=0.5:0.9:50|60|40:0.4|0.32|0.28:0.25|0.4|0.3:2,"
        # Gentle tape saturation via soft-knee compression
        "compand=attacks=0.02:decays=0.15:points=-80/-80|-30/-20|-10/-8|0/-6|20/-4:soft-knee=6:gain=3,"
        # Slight tape slowdown (signature lofi feel)
        "atempo=0.98,"
        # Final volume normalization
        "volume=0.88"
        "[lofi];"
        # Vinyl crackle — pink noise at very low level (subtle, not harsh)
        "anoisesrc=r=44100:color=pink:a=0.004:d=9999"
        "[noise];"
        # Mix: music at full weight, crackle at ~3%
        "[lofi][noise]amix=inputs=2:weights=1 0.03:dropout_transition=0[out]"
    )
    cmd = [
        "ffmpeg", "-y",
        "-i", str(input_wav),
        "-filter_complex", fx_chain,
        "-map", "[out]",
        "-ar", "44100", "-ac", "2",
        str(output_wav)
    ]
    subprocess.run(cmd, check=True, stderr=subprocess.DEVNULL)
    print(f"  [fx] lofi audio: {output_wav}")
    return output_wav


def loop_audio_to_duration(input_wav: Path, output_wav: Path, target_secs: int) -> Path:
    """Loop the input WAV to fill target_secs using FFmpeg stream_loop."""
    cmd = [
        "ffmpeg", "-y",
        "-stream_loop", "-1",
        "-i", str(input_wav),
        "-t", str(target_secs),
        "-ar", "44100",
        str(output_wav)
    ]
    subprocess.run(cmd, check=True, stderr=subprocess.DEVNULL)
    print(f"  [loop] audio looped to {target_secs}s: {output_wav}")
    return output_wav


# ---------------------------------------------------------------------------
# Anime GIF/image fetch
# ---------------------------------------------------------------------------
def fetch_waifu_gif(endpoint: str | None = None, retries: int = 3) -> Path | None:
    """Download a random anime GIF from nekos.best (primary) or waifu.pics (fallback).

    Returns the local path to the cached file, or None on failure.
    """
    WAIFU_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    ep = endpoint or random.choice(WAIFU_ENDPOINTS)
    ua = {"User-Agent": "LofiPipeline/1.0 (https://github.com/llooffiisounds)"}

    # APIs to try, in order
    apis = [
        # 1. nekos.best — GIF endpoints
        {
            "url": f"{NEKOS_BASE}{ep}?amount=1",
            "parse": lambda d: d["results"][0]["url"],
            "ext": "gif",
            "name": f"nekos.best/{ep}",
        },
        # 2. waifu.pics — returns PNG (usable as Ken Burns still)
        {
            "url": "https://api.waifu.pics/sfw/waifu",
            "parse": lambda d: d["url"],
            "ext": "png",
            "name": "waifu.pics/waifu",
        },
    ]

    for api in apis:
        for attempt in range(retries):
            try:
                req = urllib.request.Request(api["url"], headers=ua)
                with urllib.request.urlopen(req, timeout=15) as resp:
                    data = json.loads(resp.read())
                img_url = api["parse"](data)
                if not img_url:
                    raise ValueError("empty url field")

                ext = api["ext"]
                dest = WAIFU_CACHE_DIR / f"bg_{ep}_{int(time.time())}.{ext}"
                print(f"  [waifu] downloading from {api['name']} → {dest.name}")
                img_req = urllib.request.Request(img_url, headers=ua)
                with urllib.request.urlopen(img_req, timeout=30) as img_resp:
                    dest.write_bytes(img_resp.read())
                if dest.stat().st_size < 1024:
                    raise ValueError(f"file too small ({dest.stat().st_size}B)")
                print(f"  [waifu] saved: {dest} ({dest.stat().st_size // 1024}KB)")
                return dest
            except Exception as e:
                print(f"  [waifu] {api['name']} attempt {attempt + 1} failed: {e}")
                if attempt < retries - 1:
                    time.sleep(2)

    print("  [waifu] all APIs/attempts failed — will use local fallback")
    return None


# ---------------------------------------------------------------------------
# Video rendering
# ---------------------------------------------------------------------------
VIDEO_EXTS = {".mp4", ".mov", ".webm", ".mkv", ".avi"}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
GIF_EXTS   = {".gif"}


def pick_background(override: Path | None = None) -> Path | None:
    """Return the best background asset available.

    Priority:
      1. Explicit --background arg
      2. Video files in BACKGROUND_DIR (.mp4 / .mov / .webm)
      3. GIF files in BACKGROUND_DIR
      4. Still images in BACKGROUND_DIR
      5. Live fetch from waifu.vercel.app (random SFW GIF)
      6. None  →  dark gradient fallback in render_video()
    """
    if override is not None and override.exists():
        return override
    if BACKGROUND_DIR.exists():
        videos = sorted(p for p in BACKGROUND_DIR.iterdir()
                        if p.suffix.lower() in VIDEO_EXTS)
        if videos:
            return random.choice(videos)
        gifs = sorted(p for p in BACKGROUND_DIR.iterdir()
                      if p.suffix.lower() in GIF_EXTS)
        if gifs:
            return random.choice(gifs)
        stills = sorted(p for p in BACKGROUND_DIR.iterdir()
                        if p.suffix.lower() in IMAGE_EXTS)
        if stills:
            return random.choice(stills)
    # Nothing local — reach out to waifu API
    print("  [bg] no local assets found — fetching anime GIF from waifu API...")
    return fetch_waifu_gif()


def render_video(
    audio_path: Path,
    output_path: Path,
    duration_secs: int,
    title: str = "lofi beats",
    background_override: Path | None = None,
) -> Path:
    """Render the final video.

    Supports three background modes:
      1. Animated video  — stream_loop -1  (MP4/MOV/WEBM ...)
      2. Still image     — Ken Burns zoompan  (JPG/PNG/WEBP)
      3. Dark fallback   — lavfi color source  (no asset found)
    """
    bg = pick_background(background_override)
    text_overlay = (
        f"drawtext=text='llooffiisounds':fontcolor=white@0.35:fontsize=28:"
        f"x=40:y=h-60:shadowcolor=black@0.5:shadowx=2:shadowy=2,"
        f"drawtext=text='{title}':fontcolor=white@0.45:fontsize=17:"
        f"x=40:y=h-32:shadowcolor=black@0.4:shadowx=1:shadowy=1"
    )

    if bg and bg.suffix.lower() in VIDEO_EXTS:
        # ── Mode 1: Animated background video ──────────────────────────────
        print(f"  [video] background mode: animated video → {bg.name}")
        vf = (
            f"scale=1920:1080:force_original_aspect_ratio=increase,"
            f"crop=1920:1080,"
            f"gblur=sigma=4,"
            f"fps=30,format=yuv420p,"
            f"{text_overlay}"
        )
        cmd = [
            "ffmpeg", "-y",
            "-stream_loop", "-1", "-i", str(bg),
            "-i", str(audio_path),
            "-map", "0:v", "-map", "1:a",
            "-vf", vf,
            "-c:v", "libx264", "-preset", "slow", "-crf", "23",
            "-c:a", "aac", "-b:a", "192k",
            "-t", str(duration_secs),
            "-movflags", "+faststart",
            str(output_path),
        ]

    elif bg and bg.suffix.lower() in GIF_EXTS:
        # ── Mode 1b: Animated GIF ── loop=-1 filter + gblur(sigma=4) ─────────────────
        # Note: -stream_loop is NOT supported by the GIF demuxer ("Option not found").
        # Use -ignore_loop 0 + the `loop` video filter instead.
        print(f"  [video] background mode: animated GIF + blur → {bg.name}")
        vf = (
            f"loop=-1:size=32767:start=0,"
            f"scale=1920:1080:force_original_aspect_ratio=increase,"
            f"crop=1920:1080,"
            f"gblur=sigma=4,"
            f"fps=30,format=yuv420p,"
            f"{text_overlay}"
        )
        cmd = [
            "ffmpeg", "-y",
            "-ignore_loop", "0", "-i", str(bg),
            "-i", str(audio_path),
            "-map", "0:v", "-map", "1:a",
            "-vf", vf,
            "-c:v", "libx264", "-preset", "slow", "-crf", "23",
            "-c:a", "aac", "-b:a", "192k",
            "-t", str(duration_secs),
            "-movflags", "+faststart",
            str(output_path),
        ]

    elif bg and bg.suffix.lower() in IMAGE_EXTS:
        # ── Mode 2: Still image  →  Ken Burns slow zoom ────────────────────
        print(f"  [video] background mode: still image Ken Burns → {bg.name}")
        zoom_rate = 0.08 / duration_secs
        vf = (
            f"scale=1920:1080:force_original_aspect_ratio=increase,"
            f"crop=1920:1080,"
            f"zoompan=z='min(zoom+{zoom_rate:.8f},1.08)':"
            f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            f"d={duration_secs * 25}:s=1920x1080:fps=25,"
            f"{text_overlay}"
        )
        cmd = [
            "ffmpeg", "-y",
            "-loop", "1", "-framerate", "25", "-i", str(bg),
            "-i", str(audio_path),
            "-vf", vf,
            "-c:v", "libx264", "-preset", "slow", "-crf", "23",
            "-c:a", "aac", "-b:a", "192k",
            "-t", str(duration_secs),
            "-movflags", "+faststart",
            str(output_path),
        ]

    else:
        # ── Mode 3: No asset — dark gradient fallback ──────────────────────
        print("  [video] background mode: dark gradient fallback (no asset found)")
        vf = (
            f"drawtext=text='llooffiisounds':fontcolor=white@0.4:fontsize=40:"
            f"x=(w-text_w)/2:y=(h-text_h)/2:shadowcolor=black@0.5:shadowx=3:shadowy=3,"
            f"drawtext=text='{title}':fontcolor=white@0.3:fontsize=22:"
            f"x=(w-text_w)/2:y=(h+text_h)/2+20:shadowcolor=black@0.4:shadowx=1:shadowy=1"
        )
        cmd = [
            "ffmpeg", "-y",
            "-f", "lavfi", "-i", "color=c=0x0d0d1a:size=1920x1080:rate=25",
            "-i", str(audio_path),
            "-vf", vf,
            "-c:v", "libx264", "-preset", "slow", "-crf", "23",
            "-c:a", "aac", "-b:a", "192k",
            "-t", str(duration_secs),
            str(output_path),
        ]

    print(f"  [video] rendering {duration_secs}s video (this takes a while)...")
    subprocess.run(cmd, check=True, stderr=subprocess.DEVNULL)
    print(f"  [video] done: {output_path}")
    return output_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Generate a lofi video for YouTube")
    parser.add_argument("--duration", type=int, default=DEFAULT_DURATION_SECS,
                        help="Duration in seconds (default 10800 = 3h)")
    parser.add_argument("--output", type=str, default="lofi-output.mp4",
                        help="Output MP4 path")
    parser.add_argument("--server", type=str, default=DEFAULT_SERVER,
                        help="ML server URL")
    parser.add_argument("--title", type=str, default="lofi beats to relax/study to",
                        help="Track title for video overlay")
    parser.add_argument("--background", type=str, default=None,
                        help="Explicit background asset: .mp4/.mov/.webm (animated) "
                             "or .jpg/.png/.webp (still image). Overrides auto-pick.")
    args = parser.parse_args()

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        print("\n[1/6] Fetching track blueprint from ML server...")
        track = fetch_track(args.server)
        print(f"  key={track.get('key')} bpm={track.get('bpm')} chords={len(track.get('chords', []))} chord(s)")

        print("\n[2/6] Building MIDI...")
        midi_path = tmp / "track.mid"
        build_midi(track, midi_path, loop_bars=32)

        print("\n[3/6] Rendering MIDI → WAV via fluidsynth...")
        raw_wav = tmp / "raw.wav"
        midi_to_wav(midi_path, raw_wav)

        print("\n[4/6] Applying lofi FX...")
        lofi_wav = tmp / "lofi.wav"
        apply_lofi_fx(raw_wav, lofi_wav)

        print(f"\n[5/6] Looping audio to {args.duration}s ({args.duration // 3600}h {(args.duration % 3600) // 60}m)...")
        long_wav = tmp / "long.wav"
        loop_audio_to_duration(lofi_wav, long_wav, args.duration)

        print("\n[6/6] Rendering final video...")
        bg_override = Path(args.background) if args.background else None
        render_video(long_wav, output_path, args.duration, args.title,
                     background_override=bg_override)

    print(f"\n✓ Done: {output_path.resolve()}")


if __name__ == "__main__":
    main()
