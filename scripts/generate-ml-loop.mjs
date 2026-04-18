#!/usr/bin/env node

import { existsSync } from "node:fs";
import { copyFile, mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";

const DEFAULT_SERVER_URL = "http://localhost:5050";
const DEFAULT_INTERVAL_SECONDS = 240;
const DEFAULT_OUTPUT_DIR = "output/generated-lofi";
const DEFAULT_SOURCE = "mixed";
const DEFAULT_DEDUPE_THRESHOLD = 0.2;
const DEFAULT_DEDUPE_ATTEMPTS = 8;
const DEFAULT_MEMORY_SIZE = 300;
const MEMORY_FILE_NAME = "fingerprint-memory.json";
const DEFAULT_VIDEO_DIR = "output/generated-lofi/videos";
const DEFAULT_VIDEO_DURATION_SECONDS = DEFAULT_INTERVAL_SECONDS;
const DEFAULT_AUDIO_DIR = "";
const DEFAULT_PRESET = "study";
const DEFAULT_STYLE_SHIFT_EVERY = 3;
const BACKGROUND_DIR = path.join(process.cwd(), "public/assets/background");
const VIDEO_EXPORT_SCRIPT = path.join(process.cwd(), "scripts/generate-lofi-video.mjs");
const VISUAL_BACKUP_LIMIT = 10;

const seedPrompts = [
  "Dusty cassette texture, sleepy piano voicings, lazy snare, cozy midnight atmosphere.",
  "Rain-on-window ambience, warm Rhodes chords, low-pass bass, study-friendly groove.",
  "Jazz-hop inspired lo-fi, soft vinyl crackle, sparse lead, calming focus energy.",
  "Minimal neo-soul loop, mellow kick, brushed hats, nostalgic apartment vibe.",
  "Sunrise cafe lo-fi, bright electric piano, gentle percussion, positive but restrained mood.",
  "Moody tape-warp beat, deep sub warmth, distant pad, introspective late-night tone.",
  "Library core beat, low dynamics, repetitive hypnotic motif, no harsh transients.",
  "Cloudy day chillhop, simple chord progression, soft sidechain pulse, calm and steady.",
  "Lo-fi boom bap with soft drums, muted guitar plucks, ambient room tail.",
  "Dreamy analog synth bed, warm keys, soft swing groove, contemplative cinematic feel.",
];

const backgroundBuckets = {
  bright: [1, 2, 3],
  balanced: [4, 5, 6],
  moody: [7, 8],
  deep: [9, 10],
};

const presetProfiles = {
  study: {
    prompts: [
      "Deep focus study session, gentle vinyl crackle, soft piano, no harsh highs, steady rhythm.",
      "Library at midnight, warm jazz chords, subtle bass pulse, calm and repetitive for concentration.",
      "Exam prep ambient lo-fi, sparse melody, soothing chords, stable groove for long sessions.",
    ],
    preferredBuckets: ["balanced", "deep"],
  },
  rainy: {
    prompts: [
      "Rainy evening lo-fi, soft keys, distant thunder, calm repeating groove.",
      "Window rain study beat, muted Rhodes, low-pass drums, cozy and slow-moving.",
      "Grey sky chillhop, soft percussion, reflective chords, wet atmosphere.",
    ],
    preferredBuckets: ["deep", "moody"],
  },
  night_drive: {
    prompts: [
      "Night drive lo-fi, muted bass, soft pads, neon reflections, slow pulse.",
      "Late-night highway lofi, cinematic haze, chilled drums, distant synth glow.",
      "Midnight cruise beat, deep sub warmth, sparse melody, drifting motion.",
    ],
    preferredBuckets: ["moody", "deep"],
  },
  warm_piano: {
    prompts: [
      "Warm piano loop, cozy chords, soft swing, inviting and intimate atmosphere.",
      "Sunlit piano lofi, mellow keys, gentle percussion, soft harmonic glow.",
      "Cafe piano chill, tender voicings, light drums, relaxed and affectionate tone.",
    ],
    preferredBuckets: ["bright", "balanced"],
  },
  dusty_boom_bap: {
    prompts: [
      "Dusty boom bap lo-fi, mellow chops, crisp drums, vinyl texture, head-nod groove.",
      "Tape-smeared boom bap, warm chops, shuffled hats, smoky basement feel.",
      "Crate-digger beat, chopped soul sample, punchy drums, laid-back swing.",
    ],
    preferredBuckets: ["balanced", "moody"],
  },
};

const presetNames = Object.keys(presetProfiles);

function printUsage() {
  console.log(`\nGenerate new jacbz-lofi tracks in a loop.\n\nUsage:\n  pnpm ml:generate:loop -- [options]\n\nOptions:\n  --server <url>           ML server base URL (default: ${DEFAULT_SERVER_URL})\n  --interval <seconds>     Seconds between generations (default: ${DEFAULT_INTERVAL_SECONDS})\n  --count <n>              Number of tracks to generate (default: infinite loop)\n  --source <mode>          generate | predict | mixed (default: ${DEFAULT_SOURCE})\n  --output <dir>           Output folder for JSON tracks (default: ${DEFAULT_OUTPUT_DIR})\n  --preset <name>          study | rainy | night_drive | warm_piano | dusty_boom_bap (default: ${DEFAULT_PRESET})\n  --style-shift-every <n>  Rotate preset family every N tracks (default: ${DEFAULT_STYLE_SHIFT_EVERY})\n  --dedupe-threshold <n>   Reject tracks with distance below this (default: ${DEFAULT_DEDUPE_THRESHOLD})\n  --dedupe-attempts <n>    Retry attempts before failing (default: ${DEFAULT_DEDUPE_ATTEMPTS})\n  --memory-size <n>        Keep last N fingerprints in memory file (default: ${DEFAULT_MEMORY_SIZE})\n  --export-video           Render a 4-minute MP4 for each accepted track\n  --audio-dir <dir>        Audio files named track-0001.* to pair with rendered videos\n  --video-dir <dir>        Output folder for MP4 files (default: ${DEFAULT_VIDEO_DIR})\n  --video-duration <sec>   Video duration in seconds (default: ${DEFAULT_VIDEO_DURATION_SECONDS})\n  --help                   Show this help\n\nExamples:\n  pnpm ml:generate:loop\n  pnpm ml:generate:loop -- --interval 240 --count 10 --source mixed\n  pnpm ml:generate:loop -- --preset rainy --style-shift-every 4\n  pnpm ml:generate:loop -- --export-video --audio-dir ./output/rendered-audio\n`);
}

function parseArgs(argv) {
  const options = {
    server: process.env.ML_SERVER_URL || DEFAULT_SERVER_URL,
    interval: DEFAULT_INTERVAL_SECONDS,
    count: undefined,
    source: DEFAULT_SOURCE,
    output: DEFAULT_OUTPUT_DIR,
    preset: DEFAULT_PRESET,
    styleShiftEvery: DEFAULT_STYLE_SHIFT_EVERY,
    dedupeThreshold: DEFAULT_DEDUPE_THRESHOLD,
    dedupeAttempts: DEFAULT_DEDUPE_ATTEMPTS,
    memorySize: DEFAULT_MEMORY_SIZE,
    exportVideo: false,
    audioDir: DEFAULT_AUDIO_DIR,
    videoDir: DEFAULT_VIDEO_DIR,
    videoDuration: DEFAULT_VIDEO_DURATION_SECONDS,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];

    // pnpm run <script> -- <args> forwards a literal "--" token to argv.
    if (arg === "--") {
      continue;
    }

    if (arg === "--help" || arg === "-h") {
      options.help = true;
      continue;
    }

    if (arg === "--export-video") {
      options.exportVideo = true;
      continue;
    }

    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      throw new Error(`Missing value for argument: ${arg}`);
    }

    if (arg === "--server") {
      options.server = next;
      i += 1;
      continue;
    }

    if (arg === "--interval") {
      options.interval = Number(next);
      i += 1;
      continue;
    }

    if (arg === "--count") {
      options.count = Number(next);
      i += 1;
      continue;
    }

    if (arg === "--source") {
      options.source = next;
      i += 1;
      continue;
    }

    if (arg === "--output") {
      options.output = next;
      i += 1;
      continue;
    }

    if (arg === "--preset") {
      options.preset = next;
      i += 1;
      continue;
    }

    if (arg === "--style-shift-every") {
      options.styleShiftEvery = Number(next);
      i += 1;
      continue;
    }

    if (arg === "--audio-dir") {
      options.audioDir = next;
      i += 1;
      continue;
    }

    if (arg === "--video-dir") {
      options.videoDir = next;
      i += 1;
      continue;
    }

    if (arg === "--video-duration") {
      options.videoDuration = Number(next);
      i += 1;
      continue;
    }

    if (arg === "--dedupe-threshold") {
      options.dedupeThreshold = Number(next);
      i += 1;
      continue;
    }

    if (arg === "--dedupe-attempts") {
      options.dedupeAttempts = Number(next);
      i += 1;
      continue;
    }

    if (arg === "--memory-size") {
      options.memorySize = Number(next);
      i += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  return options;
}

function assertPositiveNumber(name, value) {
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${name} must be a positive number.`);
  }
}

function assertValidSource(source) {
  const allowed = new Set(["generate", "predict", "mixed"]);
  if (!allowed.has(source)) {
    throw new Error(`source must be one of: ${Array.from(allowed).join(", ")}`);
  }
}

function assertPositiveInteger(name, value) {
  if (!Number.isFinite(value) || value <= 0 || !Number.isInteger(value)) {
    throw new Error(`${name} must be a positive integer.`);
  }
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function toNumber(value, fallback) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
}

function toInteger(value, fallback) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? Math.trunc(numeric) : fallback;
}

function normalizeServerUrl(serverUrl) {
  return serverUrl.trim().replace(/\/+$/, "");
}

function parsePayload(payload) {
  if (typeof payload === "string") {
    return JSON.parse(payload);
  }
  return payload;
}

function normalizeIntArray(input, min, max, limit = 64) {
  if (!Array.isArray(input)) {
    return [];
  }

  return input
    .slice(0, limit)
    .map((value) => clamp(Math.trunc(toNumber(value, min)), min, max));
}

function hashString(value) {
  let hash = 5381;
  for (let index = 0; index < value.length; index += 1) {
    hash = ((hash << 5) + hash) ^ value.charCodeAt(index);
  }
  return hash >>> 0;
}

function normalizePresetName(value) {
  const candidate = String(value || DEFAULT_PRESET);
  return presetProfiles[candidate] ? candidate : DEFAULT_PRESET;
}

function getPresetForTrack(basePreset, trackIndex, styleShiftEvery) {
  const normalizedPreset = normalizePresetName(basePreset);
  const shiftEvery = Math.max(1, Math.trunc(toNumber(styleShiftEvery, DEFAULT_STYLE_SHIFT_EVERY)));
  const shiftIndex = shiftEvery > 0 ? Math.floor((trackIndex - 1) / shiftEvery) : 0;
  const presetIndex = (presetNames.indexOf(normalizedPreset) + shiftIndex) % presetNames.length;
  return presetNames[presetIndex] || normalizedPreset;
}

function pickPromptForPreset(presetName, trackIndex) {
  const preset = presetProfiles[presetName] || presetProfiles[DEFAULT_PRESET];
  return preset.prompts[(trackIndex - 1) % preset.prompts.length];
}

function pickRandomElement(values, seedValue) {
  if (!Array.isArray(values) || values.length === 0) {
    return null;
  }

  const index = hashString(seedValue) % values.length;
  return values[index];
}

function pickBackgroundForTrack(fingerprint, trackIndex, prompt, source, presetName) {
  const preset = presetProfiles[normalizePresetName(presetName)] || presetProfiles[DEFAULT_PRESET];
  const bucketName = pickRandomElement(
    preset.preferredBuckets,
    JSON.stringify({
      trackIndex,
      prompt,
      source,
      key: fingerprint.key,
      bpm: Math.round(fingerprint.bpm),
    }),
  ) || (fingerprint.valence >= 0.58 && fingerprint.energy >= 0.52
    ? "bright"
    : fingerprint.valence >= 0.42
      ? "balanced"
      : fingerprint.energy >= 0.58
        ? "moody"
        : "deep");

  const bucket = backgroundBuckets[bucketName] || backgroundBuckets.balanced;
  const seed = JSON.stringify({
    key: fingerprint.key,
    mode: fingerprint.mode,
    bpm: Math.round(fingerprint.bpm),
    energy: Number(fingerprint.energy.toFixed(3)),
    valence: Number(fingerprint.valence.toFixed(3)),
    chords: fingerprint.chords,
    melody: fingerprint.melody.slice(0, 24),
    prompt: prompt || "",
    source,
    trackIndex,
    presetName,
  });
  const candidateId = bucket[hashString(seed) % bucket.length];

  return {
    id: candidateId,
    bucket: bucketName,
    name: `Background ${candidateId}`,
    path: path.join(BACKGROUND_DIR, `bg${candidateId}.webp`),
  };
}

function resolveAudioFile(audioDir, index) {
  const baseName = `track-${String(index).padStart(4, "0")}`;
  const extensions = ["wav", "mp3", "m4a", "ogg", "webm", "flac"];

  for (const extension of extensions) {
    const candidate = path.join(audioDir, `${baseName}.${extension}`);
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  return null;
}

function renderVideoLoop({ visualPath, audioPath, outputPath, duration }) {
  if (!existsSync(VIDEO_EXPORT_SCRIPT)) {
    throw new Error(`Video export script not found: ${VIDEO_EXPORT_SCRIPT}`);
  }

  const result = spawnSync(
    process.execPath,
    [
      VIDEO_EXPORT_SCRIPT,
      "--visual",
      visualPath,
      "--audio",
      audioPath,
      "--duration",
      String(duration),
      "--output",
      outputPath,
    ],
    { stdio: "inherit" },
  );

  if (result.status !== 0) {
    throw new Error(`Video export failed for ${outputPath}.`);
  }
}

function flattenMelodies(input, maxNotes = 64) {
  if (!Array.isArray(input)) {
    return [];
  }

  const notes = [];
  for (const seq of input) {
    if (!Array.isArray(seq)) {
      continue;
    }
    for (const token of seq) {
      notes.push(clamp(Math.trunc(toNumber(token, 0)), 0, 28));
      if (notes.length >= maxNotes) {
        return notes;
      }
    }
  }
  return notes;
}

function createTrackFingerprint(track) {
  const key = clamp(Math.trunc(toNumber(track?.key, 1)), 1, 12);
  const mode = clamp(Math.trunc(toNumber(track?.mode, 1)), 1, 7);
  const bpm = clamp(toNumber(track?.bpm, 80), 40, 220);
  const energy = clamp(toNumber(track?.energy, 0.45), 0, 1);
  const valence = clamp(toNumber(track?.valence, 0.45), 0, 1);
  const chords = normalizeIntArray(track?.chords, 1, 7, 16);
  const melody = flattenMelodies(track?.melodies, 64);

  return { key, mode, bpm, energy, valence, chords, melody };
}

function sequenceDistance(a, b, maxValue) {
  const maxLength = Math.max(a.length, b.length);
  if (maxLength === 0) {
    return 0;
  }

  let distance = 0;
  for (let i = 0; i < maxLength; i += 1) {
    const left = a[i];
    const right = b[i];

    if (typeof left === "undefined" || typeof right === "undefined") {
      distance += 1;
      continue;
    }

    distance += clamp(Math.abs(left - right) / maxValue, 0, 1);
  }

  return distance / maxLength;
}

function fingerprintDistance(left, right) {
  const keyDiff = Math.abs(left.key - right.key);
  const keyDistance = Math.min(keyDiff, 12 - keyDiff) / 6;
  const modeDistance = clamp(Math.abs(left.mode - right.mode) / 6, 0, 1);
  const bpmDistance = clamp(Math.abs(left.bpm - right.bpm) / 40, 0, 1);
  const energyDistance = clamp(Math.abs(left.energy - right.energy), 0, 1);
  const valenceDistance = clamp(Math.abs(left.valence - right.valence), 0, 1);
  const chordDistance = sequenceDistance(left.chords, right.chords, 6);
  const melodyDistance = sequenceDistance(left.melody, right.melody, 28);

  return (
    keyDistance * 0.1
    + modeDistance * 0.1
    + bpmDistance * 0.2
    + energyDistance * 0.2
    + valenceDistance * 0.2
    + chordDistance * 0.1
    + melodyDistance * 0.1
  );
}

function findNearestFingerprint(current, history) {
  let nearest = null;
  for (const item of history) {
    const distance = fingerprintDistance(current, item.fingerprint);
    if (!nearest || distance < nearest.distance) {
      nearest = { distance, item };
    }
  }
  return nearest;
}

async function loadFingerprintMemory(memoryPath) {
  try {
    const text = await readFile(memoryPath, "utf8");
    const payload = JSON.parse(text);
    if (!Array.isArray(payload?.items)) {
      return [];
    }

    return payload.items.filter((item) => item && typeof item === "object" && item.fingerprint);
  } catch {
    return [];
  }
}

async function saveFingerprintMemory(memoryPath, items) {
  await writeFile(
    memoryPath,
    JSON.stringify(
      {
        updatedAt: new Date().toISOString(),
        count: items.length,
        items,
      },
      null,
      2,
    ),
    "utf8",
  );
}

async function loadVisualBackupManifest(manifestPath) {
  try {
    const text = await readFile(manifestPath, "utf8");
    const payload = JSON.parse(text);
    if (!Array.isArray(payload?.items)) {
      return [];
    }
    return payload.items.filter((item) => item && typeof item === "object" && typeof item.backupPath === "string");
  } catch {
    return [];
  }
}

async function saveVisualBackupManifest(manifestPath, items) {
  await writeFile(
    manifestPath,
    JSON.stringify(
      {
        updatedAt: new Date().toISOString(),
        count: items.length,
        items,
      },
      null,
      2,
    ),
    "utf8",
  );
}

async function backupVisualAsset({ sourcePath, outputDir, manifestPath, record }) {
  await mkdir(outputDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const fileName = `visual-${String(record.index).padStart(4, "0")}-bg${record.visual.id}-${stamp}${path.extname(sourcePath)}`;
  const backupPath = path.join(outputDir, fileName);
  await copyFile(sourcePath, backupPath);

  const manifest = await loadVisualBackupManifest(manifestPath);
  manifest.push({
    index: record.index,
    generatedAt: record.generatedAt,
    preset: record.preset,
    fileName,
    backupPath,
    sourcePath,
    visual: record.visual,
  });

  while (manifest.length > VISUAL_BACKUP_LIMIT) {
    const removed = manifest.shift();
    if (removed?.backupPath) {
      try {
        await unlink(removed.backupPath);
      } catch {
        // Ignore stale backup cleanup failures.
      }
    }
  }

  await saveVisualBackupManifest(manifestPath, manifest);
}

async function fetchTrack(serverUrl, endpoint, input) {
  const url = new URL(`${normalizeServerUrl(serverUrl)}/${endpoint}`);

  if (endpoint !== "generate") {
    if (!input) {
      throw new Error("Predict endpoint requires input text.");
    }
    url.searchParams.set("input", input);
  }

  const response = await fetch(url, { method: "GET" });
  if (!response.ok) {
    throw new Error(`${endpoint} failed with status ${response.status}`);
  }

  const payload = await response.json();
  return parsePayload(payload);
}

function chooseSource(mode, index) {
  if (mode === "generate") {
    return "generate";
  }
  if (mode === "predict") {
    return "predict";
  }
  return index % 2 === 0 ? "predict" : "generate";
}

function choosePrompt(index, presetName = DEFAULT_PRESET) {
  const preset = presetProfiles[normalizePresetName(presetName)] || presetProfiles[DEFAULT_PRESET];
  return preset.prompts[(index - 1) % preset.prompts.length] || seedPrompts[(index - 1) % seedPrompts.length];
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function buildFileName(index, source) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  return `track-${String(index).padStart(4, "0")}-${source}-${stamp}.json`;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    printUsage();
    process.exit(0);
  }

  assertPositiveNumber("interval", options.interval);
  if (typeof options.count !== "undefined") {
    assertPositiveNumber("count", options.count);
  }
  assertPositiveNumber("dedupe-threshold", options.dedupeThreshold);
  assertPositiveNumber("dedupe-attempts", options.dedupeAttempts);
  assertPositiveNumber("memory-size", options.memorySize);
  assertPositiveInteger("video-duration", toInteger(options.videoDuration, DEFAULT_VIDEO_DURATION_SECONDS));
  assertPositiveInteger("style-shift-every", Math.max(1, Math.trunc(options.styleShiftEvery)));
  assertValidSource(options.source);
  options.preset = normalizePresetName(options.preset);

  if (options.exportVideo) {
    if (!options.audioDir) {
      throw new Error("--audio-dir is required when --export-video is enabled.");
    }

    if (!existsSync(path.resolve(options.audioDir))) {
      throw new Error(`Audio directory not found: ${path.resolve(options.audioDir)}`);
    }
  }

  const outputDir = path.resolve(options.output);
  await mkdir(outputDir, { recursive: true });
  const visualBackupDir = path.join(outputDir, "visual-backups");
  const visualBackupManifest = path.join(visualBackupDir, "manifest.json");

  const videoDir = path.resolve(options.videoDir);
  if (options.exportVideo) {
    await mkdir(videoDir, { recursive: true });
  }

  const results = [];
  const memoryPath = path.join(outputDir, MEMORY_FILE_NAME);
  const fingerprints = await loadFingerprintMemory(memoryPath);
  const maxCount = typeof options.count === "undefined" ? Number.POSITIVE_INFINITY : Math.floor(options.count);

  console.log(`Starting ML generation loop`);
  console.log(`- server: ${normalizeServerUrl(options.server)}`);
  console.log(`- source: ${options.source}`);
  console.log(`- preset: ${options.preset}`);
  console.log(`- style shift every: ${Math.max(1, Math.trunc(options.styleShiftEvery))}`);
  console.log(`- interval: ${options.interval}s`);
  console.log(`- count: ${Number.isFinite(maxCount) ? maxCount : "infinite"}`);
  console.log(`- output: ${outputDir}`);
  console.log(`- dedupe threshold: ${options.dedupeThreshold}`);
  console.log(`- dedupe attempts: ${Math.floor(options.dedupeAttempts)}`);
  console.log(`- memory size: ${Math.floor(options.memorySize)}`);
  console.log(`- memory loaded: ${fingerprints.length}`);
  if (options.exportVideo) {
    console.log(`- video export: enabled`);
    console.log(`- audio dir: ${path.resolve(options.audioDir)}`);
    console.log(`- video dir: ${videoDir}`);
    console.log(`- video duration: ${toInteger(options.videoDuration, DEFAULT_VIDEO_DURATION_SECONDS)}s`);
  }

  for (let i = 1; i <= maxCount; i += 1) {
    const activePreset = getPresetForTrack(options.preset, i, options.styleShiftEvery);
    let endpoint = "generate";
    let track = null;
    let prompt = undefined;
    let fingerprint = null;
    let nearest = null;
    const dedupeAttempts = Math.max(1, Math.floor(options.dedupeAttempts));

    for (let attempt = 1; attempt <= dedupeAttempts; attempt += 1) {
      const source = chooseSource(options.source, i + attempt - 1);
      const selectedPrompt = choosePrompt(i + attempt - 1, activePreset);

      let currentEndpoint = source;
      let currentTrack;

      try {
        if (source === "predict") {
          currentTrack = await fetchTrack(options.server, "predict", selectedPrompt);
        } else {
          currentTrack = await fetchTrack(options.server, "generate");
        }
      } catch (error) {
        if (source === "predict") {
          currentEndpoint = "generate";
          currentTrack = await fetchTrack(options.server, "generate");
        } else {
          throw error;
        }
      }

      const currentFingerprint = createTrackFingerprint(currentTrack);
      const currentNearest = findNearestFingerprint(currentFingerprint, fingerprints);
      const isNearDuplicate =
        currentNearest !== null
        && currentNearest.distance < options.dedupeThreshold;

      if (isNearDuplicate) {
        const distText = currentNearest.distance.toFixed(4);
        console.log(`[${i}] duplicate rejected (attempt ${attempt}/${dedupeAttempts}, distance=${distText})`);
        if (attempt < dedupeAttempts) {
          continue;
        }
        throw new Error(
          `Unable to find a fresh track for item ${i} after ${dedupeAttempts} attempts. `
          + `Try lowering --dedupe-threshold or increasing --dedupe-attempts.`,
        );
      }

      endpoint = currentEndpoint;
      track = currentTrack;
      prompt = currentEndpoint === "predict" ? selectedPrompt : undefined;
      fingerprint = currentFingerprint;
      nearest = currentNearest;
      break;
    }

    if (!track || !fingerprint) {
      throw new Error(`Track ${i} generation failed unexpectedly.`);
    }

    const record = {
      index: i,
      generatedAt: new Date().toISOString(),
      serverUrl: normalizeServerUrl(options.server),
      requestedSource: options.source,
      preset: activePreset,
      actualSource: endpoint,
      prompt,
      fingerprint,
      visual: null,
      track,
    };

    const visual = pickBackgroundForTrack(fingerprint, i, prompt, endpoint, activePreset);
    record.visual = visual;

    const fileName = buildFileName(i, endpoint);
    const filePath = path.join(outputDir, fileName);
    await writeFile(filePath, JSON.stringify(record, null, 2), "utf8");
    await backupVisualAsset({
      sourcePath: visual.path,
      outputDir: visualBackupDir,
      manifestPath: visualBackupManifest,
      record,
    });

    if (options.exportVideo) {
      if (!existsSync(visual.path)) {
        throw new Error(`Visual asset not found: ${visual.path}`);
      }

      const audioPath = resolveAudioFile(path.resolve(options.audioDir), i);
      if (!audioPath) {
        throw new Error(
          `Missing audio file for track ${i}. Expected one of track-${String(i).padStart(4, "0")}.{wav,mp3,m4a,ogg,webm,flac} in ${path.resolve(options.audioDir)}`,
        );
      }

      const videoName = fileName.replace(/\.json$/, ".mp4");
      const videoPath = path.join(videoDir, videoName);
      renderVideoLoop({
        visualPath: visual.path,
        audioPath,
        outputPath: videoPath,
        duration: toInteger(options.videoDuration, DEFAULT_VIDEO_DURATION_SECONDS),
      });

      record.video = {
        path: videoPath,
        audioPath,
      };
      await writeFile(filePath, JSON.stringify(record, null, 2), "utf8");
    }

    fingerprints.push({
      acceptedAt: record.generatedAt,
      fileName,
      source: endpoint,
      prompt,
      fingerprint,
      preset: activePreset,
      visual,
    });
    const maxMemorySize = Math.max(1, Math.floor(options.memorySize));
    if (fingerprints.length > maxMemorySize) {
      fingerprints.splice(0, fingerprints.length - maxMemorySize);
    }
    await saveFingerprintMemory(memoryPath, fingerprints);

    results.push({ fileName, source: endpoint, prompt: record.prompt });
    const nearestInfo = nearest ? ` nearest-distance=${nearest.distance.toFixed(4)}` : "";
    const visualInfo = ` visual=bg${visual.id}.webp bucket=${visual.bucket} preset=${activePreset}`;
    const videoInfo = options.exportVideo ? ` video=${path.basename(fileName, ".json")}.mp4` : "";
    console.log(`[${i}] saved ${fileName} (${endpoint})${nearestInfo}${visualInfo}${videoInfo}`);

    if (i < maxCount) {
      await wait(options.interval * 1000);
    }
  }

  const latestPath = path.join(outputDir, "latest.json");
  await writeFile(
    latestPath,
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        count: results.length,
        items: results,
      },
      null,
      2,
    ),
    "utf8",
  );

  console.log(`Finished. Manifest saved to ${latestPath}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
