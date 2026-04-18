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
SOUNDFONT_PATHS = [
    Path("/usr/share/sounds/sf2/FluidR3_GM.sf2"),
    Path("/usr/share/soundfonts/FluidR3_GM.sf2"),
    Path(os.path.expanduser("~/soundfonts/FluidR3_GM.sf2")),
    REPO_ROOT / "scripts" / "pipeline" / "FluidR3_GM.sf2",
]
DEFAULT_DURATION_SECS = 10800  # 3 hours
DEFAULT_SERVER = "http://localhost:5050"

# Lofi chord-to-semitone map (Roman numeral → semitone offset from root)
CHORD_SEMITONES = [0, 2, 4, 5, 7, 9, 11]  # diatonic scale degrees

# Key name → MIDI root note (octave 3)
KEY_TO_MIDI = {
    "C": 48, "C#": 49, "D": 50, "D#": 51, "E": 52, "F": 53,
    "F#": 54, "G": 55, "G#": 56, "A": 57, "A#": 58, "B": 59,
}


# ---------------------------------------------------------------------------
# ML Server fetch
# ---------------------------------------------------------------------------
def fetch_track(server_url: str, retries: int = 3) -> dict:
    url = f"{server_url.rstrip('/')}/generate"
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=15) as resp:
                return json.loads(resp.read())
        except Exception as e:
            print(f"  [fetch] attempt {attempt + 1} failed: {e}")
            if attempt < retries - 1:
                time.sleep(2)
    # Fallback: random procedural track
    print("  [fetch] ML server unreachable — using procedural fallback")
    return _procedural_fallback()


def _procedural_fallback() -> dict:
    keys = list(KEY_TO_MIDI.keys())
    return {
        "key": random.randint(1, 12),
        "mode": 1,
        "bpm": random.randint(75, 95),
        "energy": round(random.uniform(0.2, 0.5), 3),
        "valence": round(random.uniform(0.3, 0.6), 3),
        "chords": [random.randint(1, 7) for _ in range(8)],
        "melodies": [[random.randint(0, 11) for _ in range(4)] for _ in range(8)],
    }


# ---------------------------------------------------------------------------
# MIDI generation
# ---------------------------------------------------------------------------
def build_midi(track: dict, output_path: Path, loop_bars: int = 16) -> Path:
    try:
        import pretty_midi
    except ImportError:
        print("  [midi] pretty_midi not installed — pip install pretty_midi")
        sys.exit(1)

    bpm = max(60, min(120, track.get("bpm", 80)))
    key_idx = (track.get("key", 1) - 1) % 12
    key_names = list(KEY_TO_MIDI.keys())
    root_midi = KEY_TO_MIDI.get(key_names[key_idx], 48)
    chords = track.get("chords", [1, 4, 5, 1])
    melodies = track.get("melodies", [])

    pm = pretty_midi.PrettyMIDI(initial_tempo=bpm)
    beats_per_bar = 4
    secs_per_beat = 60.0 / bpm
    bar_dur = beats_per_bar * secs_per_beat

    # Piano (program 0 = Grand Piano, use 4 = Electric Piano for lofi feel)
    piano = pretty_midi.Instrument(program=4, name="Piano")
    # Bass (program 33 = Finger Bass)
    bass = pretty_midi.Instrument(program=33, name="Bass")
    # Pad (program 89 = Warm Pad)
    pad = pretty_midi.Instrument(program=89, name="Pad")

    total_bars = loop_bars
    chord_seq = (chords * (total_bars // len(chords) + 1))[:total_bars]

    for bar_idx, chord_degree in enumerate(chord_seq):
        t_start = bar_idx * bar_dur
        # Root note of chord (diatonic)
        degree = max(1, min(7, chord_degree))
        semitone = CHORD_SEMITONES[degree - 1]
        chord_root = root_midi + semitone

        # Pad chord: root + 3rd + 5th + 7th
        for interval in [0, 4, 7, 11]:
            note = pretty_midi.Note(
                velocity=random.randint(55, 70),
                pitch=chord_root + interval,
                start=t_start + random.uniform(0, 0.03),  # humanize
                end=t_start + bar_dur - 0.05,
            )
            pad.notes.append(note)

        # Bass: root on beat 1 and 3
        for beat in [0, 2]:
            bass_note = pretty_midi.Note(
                velocity=random.randint(65, 80),
                pitch=chord_root - 12,
                start=t_start + beat * secs_per_beat + random.uniform(0, 0.015),
                end=t_start + beat * secs_per_beat + secs_per_beat * 0.85,
            )
            bass.notes.append(bass_note)

        # Melody: sparse eighth-note hits from the melodies array
        if melodies:
            mel = melodies[bar_idx % len(melodies)]
            for i, note_idx in enumerate(mel):
                if random.random() < 0.55:  # sparse density
                    mel_pitch = chord_root + (note_idx % 12) + 12
                    mel_pitch = max(60, min(84, mel_pitch))
                    note_t = t_start + i * (bar_dur / max(len(mel), 1))
                    piano.notes.append(pretty_midi.Note(
                        velocity=random.randint(50, 72),
                        pitch=mel_pitch,
                        start=note_t + random.uniform(0, 0.02),
                        end=note_t + secs_per_beat * random.uniform(0.4, 0.9),
                    ))

    pm.instruments.extend([pad, bass, piano])
    pm.write(str(output_path))
    print(f"  [midi] written: {output_path} | BPM={bpm} | bars={total_bars}")
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
    """Apply lofi filter chain: tape warmth + lowpass + vinyl crackle + slight pitch wobble."""
    # Crackle noise source (generated inline via FFmpeg's anoisesrc)
    fx_chain = (
        "[0:a]"
        "aformat=sample_rates=44100,"
        "lowpass=f=3500,"           # cut harsh highs
        "highpass=f=60,"            # remove sub-rumble
        "aecho=0.8:0.9:60:0.3,"    # subtle room echo
        "atempo=0.97,"              # slight tape slowdown (lofi feel)
        "volume=0.82"               # tame volume after chain
        "[lofi];"
        "anoisesrc=r=44100:color=pink:a=0.008:d=9999"
        "[noise];"
        "[lofi][noise]amix=inputs=2:weights=1 0.045[out]"
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
# Video rendering
# ---------------------------------------------------------------------------
def pick_background() -> Path | None:
    if not BACKGROUND_DIR.exists():
        return None
    bgs = sorted(BACKGROUND_DIR.glob("*.webp")) + sorted(BACKGROUND_DIR.glob("*.jpg")) + sorted(BACKGROUND_DIR.glob("*.png"))
    return random.choice(bgs) if bgs else None


def render_video(audio_path: Path, output_path: Path, duration_secs: int, title: str = "lofi beats") -> Path:
    bg = pick_background()

    # Build filter: bg image → zoom-pan Ken Burns → overlay text
    if bg:
        # Ken Burns: slow zoom from 1.0 to 1.08 over full duration
        zoom_rate = 0.08 / duration_secs  # spread zoom over full video
        vf = (
            f"loop=loop=-1:size=1:start=0,"
            f"scale=1920:1080:force_original_aspect_ratio=increase,"
            f"crop=1920:1080,"
            f"zoompan=z='min(zoom+{zoom_rate:.8f},1.08)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={duration_secs * 25}:s=1920x1080:fps=25,"
            f"drawtext=text='llooffiisounds':fontcolor=white@0.35:fontsize=28:x=40:y=h-60:shadowcolor=black@0.5:shadowx=2:shadowy=2,"
            f"drawtext=text='{title}':fontcolor=white@0.5:fontsize=18:x=40:y=h-32:shadowcolor=black@0.4:shadowx=1:shadowy=1"
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
        # No background: dark gradient fallback
        cmd = [
            "ffmpeg", "-y",
            "-f", "lavfi", "-i", f"color=c=0x0d0d0d:size=1920x1080:rate=25",
            "-i", str(audio_path),
            "-vf", f"drawtext=text='llooffiisounds':fontcolor=white@0.4:fontsize=32:x=40:y=h-70",
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
    parser.add_argument("--duration", type=int, default=DEFAULT_DURATION_SECS, help="Duration in seconds (default 10800 = 3h)")
    parser.add_argument("--output", type=str, default="lofi-output.mp4", help="Output MP4 path")
    parser.add_argument("--server", type=str, default=DEFAULT_SERVER, help="ML server URL")
    parser.add_argument("--title", type=str, default="lofi beats to relax/study to", help="Track title for video overlay")
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
        render_video(long_wav, output_path, args.duration, args.title)

    print(f"\n✓ Done: {output_path.resolve()}")


if __name__ == "__main__":
    main()
