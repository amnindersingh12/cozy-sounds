#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const KEY_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const ROOT = process.cwd();
const TARGET_DIR = path.join(ROOT, "integrations/jacbz-lofi/model/dataset/processed-spotify-all");
const STUDY_PACK_PATH = path.join(ROOT, "output/ml-study-pack.json");

function toInt(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function toFloat(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function parseTrackPayload(rawTrack) {
  if (typeof rawTrack === "string") {
    return JSON.parse(rawTrack);
  }
  return rawTrack;
}

function tokenToScaleDegreeAndOctave(token) {
  const normalized = toInt(token, 0);
  if (normalized <= 0) {
    return { isRest: true, scaleDegree: "1", octave: "4" };
  }
  const base = normalized - 1;
  const scale = (base % 7) + 1;
  const octave = 4 + Math.floor(base / 7);
  return { isRest: false, scaleDegree: String(scale), octave: String(octave) };
}

function buildSample(track, idx) {
  const parsed = parseTrackPayload(track);
  const keyIndex = Math.max(1, Math.min(12, toInt(parsed.key, 1))) - 1;
  const key = KEY_NAMES[keyIndex] || "C";
  const mode = String(Math.max(1, Math.min(7, toInt(parsed.mode, 1))));
  const bpm = Math.max(70, Math.min(100, toInt(parsed.bpm, 80)));
  const energy = Math.max(0, Math.min(1, toFloat(parsed.energy, 0.45)));
  const valence = Math.max(0, Math.min(1, toFloat(parsed.valence, 0.4)));

  const chords = Array.isArray(parsed.chords) && parsed.chords.length
    ? parsed.chords.map((value) => Math.max(1, Math.min(7, toInt(value, 1))))
    : [1, 5, 6, 4];

  const melodies = Array.isArray(parsed.melodies) && parsed.melodies.length
    ? parsed.melodies
    : [[1, 1, 3, 3, 5, 5, 3, 0], [4, 4, 3, 3, 2, 2, 1, 0]];

  const chordEvents = chords.map((sd, i) => ({
    isRest: false,
    sd: String(sd),
    event_on: i * 4,
    event_off: (i + 1) * 4,
  }));

  const melodyEvents = [];
  const noteBeat = 0.5;
  for (let chordIdx = 0; chordIdx < chords.length; chordIdx += 1) {
    const notes = Array.isArray(melodies[chordIdx]) ? melodies[chordIdx] : [];
    for (let noteIdx = 0; noteIdx < 8; noteIdx += 1) {
      const token = noteIdx < notes.length ? notes[noteIdx] : 0;
      const converted = tokenToScaleDegreeAndOctave(token);
      melodyEvents.push({
        isRest: converted.isRest,
        scale_degree: converted.scaleDegree,
        octave: converted.octave,
        event_on: chordIdx * 4 + noteIdx * noteBeat,
        event_off: chordIdx * 4 + (noteIdx + 1) * noteBeat,
      });
    }
  }

  return {
    metadata: {
      title: typeof parsed.title === "string" && parsed.title.trim() ? parsed.title.trim() : `bootstrap-track-${idx}`,
      key,
      mode,
      beats_in_measure: "4",
    },
    audio_features: {
      tempo: bpm,
      energy,
      valence,
    },
    tracks: {
      chord: chordEvents,
      melody: melodyEvents,
    },
  };
}

async function loadTracks() {
  try {
    const text = await readFile(STUDY_PACK_PATH, "utf8");
    const parsed = JSON.parse(text);
    if (Array.isArray(parsed?.tracks) && parsed.tracks.length > 0) {
      return parsed.tracks.map((item) => item.track);
    }
  } catch {
    // Ignore and fallback to local generation below.
  }

  const serverUrl = (process.env.ML_SERVER_URL || "http://localhost:5050").replace(/\/+$/, "");
  const tracks = [];
  for (let i = 0; i < 32; i += 1) {
    const response = await fetch(`${serverUrl}/generate`);
    if (!response.ok) {
      throw new Error(`Cannot fetch generated tracks from ${serverUrl}/generate (status ${response.status})`);
    }
    tracks.push(await response.json());
  }
  return tracks;
}

async function main() {
  const tracks = await loadTracks();
  await mkdir(TARGET_DIR, { recursive: true });

  const total = Math.max(64, tracks.length * 8);
  for (let i = 0; i < total; i += 1) {
    const sample = buildSample(tracks[i % tracks.length], i);
    const filePath = path.join(TARGET_DIR, `bootstrap-${String(i).padStart(4, "0")}.json`);
    await writeFile(filePath, JSON.stringify(sample), "utf8");
  }

  console.log(`Wrote ${total} bootstrap training samples to ${TARGET_DIR}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
