#!/usr/bin/env node

import { mkdir, writeFile } from "node:fs/promises";

const prompts = [
  "Late-night study focus, warm piano, soft drums, minimal melody.",
  "Rainy window study beat, mellow chords, stable rhythm.",
  "Deep concentration lo-fi, dusty keys, subtle bass, no sharp transients.",
  "Quiet library ambience, cozy chord loop, restrained percussion.",
  "Calm coding session soundtrack, warm texture, repetitive and smooth.",
  "Exam prep beat, gentle groove, sparse melodic movement.",
  "Long reading session, low-energy lo-fi, warm and non-distracting.",
  "Morning study calm, clean pulse, soft harmonic bed.",
];

function parsePayload(payload) {
  if (typeof payload === "string") {
    return JSON.parse(payload);
  }
  return payload;
}

async function fetchTrack(serverUrl, endpoint, input) {
  const url = new URL(`${serverUrl.replace(/\/+$/, "")}/${endpoint}`);
  if (endpoint !== "generate") {
    url.searchParams.set("input", input);
  }

  const response = await fetch(url, { method: "GET" });
  if (!response.ok) {
    throw new Error(`${endpoint} failed with status ${response.status}`);
  }

  const payload = await response.json();
  return parsePayload(payload);
}

async function main() {
  const serverUrl = process.env.ML_SERVER_URL || "http://localhost:5050";
  const tracks = [];

  for (const prompt of prompts) {
    try {
      const track = await fetchTrack(serverUrl, "predict", prompt);
      tracks.push({ source: "predict", prompt, track });
    } catch {
      const track = await fetchTrack(serverUrl, "generate");
      tracks.push({ source: "generate", prompt, track });
    }
  }

  const output = {
    generatedAt: new Date().toISOString(),
    serverUrl,
    count: tracks.length,
    tracks,
  };

  await mkdir("output", { recursive: true });
  await writeFile("output/ml-study-pack.json", JSON.stringify(output, null, 2), "utf8");
  console.log(`Saved ${tracks.length} study tracks to output/ml-study-pack.json`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
