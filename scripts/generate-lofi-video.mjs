#!/usr/bin/env node

import { existsSync, mkdirSync } from "node:fs";
import { dirname, extname, resolve } from "node:path";
import { spawnSync } from "node:child_process";

function printUsage() {
  console.log(`\nGenerate a full-length lo-fi video by looping a short visual and audio source.\n\nUsage:\n  pnpm lofi:video -- --visual <path> --audio <path> [options]\n\nRequired:\n  --visual <path>     4-5 second video loop (or image)\n  --audio <path>      Audio file to use (looped if shorter than output duration)\n\nOptions:\n  --output <path>     Output video path (default: ./output/lofi-full.mp4)\n  --duration <sec>    Output duration in seconds (default: 240)\n  --width <px>        Width in pixels (default: 1920)\n  --height <px>       Height in pixels (default: 1080)\n  --fps <n>           Output frame rate (default: 30)\n  --help              Show this help\n`);
}

function parseArgs(argv) {
  const options = {
    output: "output/lofi-full.mp4",
    duration: 240,
    width: 1920,
    height: 1080,
    fps: 30,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--") {
      continue;
    }

    if (arg === "--help" || arg === "-h") {
      options.help = true;
      continue;
    }

    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      throw new Error(`Missing value for argument: ${arg}`);
    }

    if (arg === "--visual") {
      options.visual = next;
      i++;
      continue;
    }

    if (arg === "--audio") {
      options.audio = next;
      i++;
      continue;
    }

    if (arg === "--output") {
      options.output = next;
      i++;
      continue;
    }

    if (arg === "--duration") {
      options.duration = Number(next);
      i++;
      continue;
    }

    if (arg === "--width") {
      options.width = Number(next);
      i++;
      continue;
    }

    if (arg === "--height") {
      options.height = Number(next);
      i++;
      continue;
    }

    if (arg === "--fps") {
      options.fps = Number(next);
      i++;
      continue;
    }

    throw new Error(`Unknown argument: ${arg}`);
  }

  return options;
}

function assertPositiveInt(name, value) {
  if (!Number.isFinite(value) || value <= 0 || !Number.isInteger(value)) {
    throw new Error(`${name} must be a positive integer.`);
  }
}

function checkCommandExists(command) {
  const result = spawnSync(command, ["-version"], { stdio: "ignore" });
  return result.status === 0;
}

function runFfmpeg(args) {
  const result = spawnSync("ffmpeg", args, { stdio: "inherit" });
  if (result.status !== 0) {
    throw new Error("FFmpeg failed to generate the output video.");
  }
}

function isImageFile(filePath) {
  const imageExts = new Set([".png", ".jpg", ".jpeg", ".webp", ".gif"]);
  return imageExts.has(extname(filePath).toLowerCase());
}

function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    printUsage();
    process.exit(0);
  }

  if (!options.visual || !options.audio) {
    printUsage();
    throw new Error("--visual and --audio are required.");
  }

  assertPositiveInt("duration", options.duration);
  assertPositiveInt("width", options.width);
  assertPositiveInt("height", options.height);
  assertPositiveInt("fps", options.fps);

  const visualPath = resolve(options.visual);
  const audioPath = resolve(options.audio);
  const outputPath = resolve(options.output);

  if (!existsSync(visualPath)) {
    throw new Error(`Visual file not found: ${visualPath}`);
  }

  if (!existsSync(audioPath)) {
    throw new Error(`Audio file not found: ${audioPath}`);
  }

  if (!checkCommandExists("ffmpeg")) {
    throw new Error("ffmpeg is required. Install it and retry (e.g. brew install ffmpeg).");
  }

  mkdirSync(dirname(outputPath), { recursive: true });

  const scaleAndCrop = `scale=${options.width}:${options.height}:force_original_aspect_ratio=increase,crop=${options.width}:${options.height},fps=${options.fps},format=yuv420p`;

  const ffmpegArgs = ["-y"];

  if (isImageFile(visualPath)) {
    ffmpegArgs.push("-loop", "1", "-i", visualPath);
  } else {
    ffmpegArgs.push("-stream_loop", "-1", "-i", visualPath);
  }

  ffmpegArgs.push(
    "-stream_loop",
    "-1",
    "-i",
    audioPath,
    "-t",
    String(options.duration),
    "-vf",
    scaleAndCrop,
    "-c:v",
    "libx264",
    "-preset",
    "medium",
    "-crf",
    "20",
    "-c:a",
    "aac",
    "-b:a",
    "192k",
    "-shortest",
    outputPath,
  );

  console.log(`\nGenerating lo-fi video:\n- visual: ${visualPath}\n- audio: ${audioPath}\n- duration: ${options.duration}s\n- output: ${outputPath}\n`);

  runFfmpeg(ffmpegArgs);

  console.log(`\nDone: ${outputPath}`);
}

try {
  main();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Error: ${message}`);
  process.exit(1);
}
