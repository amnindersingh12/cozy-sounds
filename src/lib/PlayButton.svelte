<script lang="ts">
  import {
      IconLoader,
      IconPlayerPauseFilled,
      IconPlayerPlayFilled,
  } from "@tabler/icons-svelte";
  import { onDestroy, onMount } from "svelte";
// @ts-ignore
  import * as Tone from "tone";
  import Chords from "../lib/engine/Chords/Chords";
  import ChordProgression from "../lib/engine/Chords/ChordProgression";
  import intervalWeights from "../lib/engine/Chords/IntervalWeights";
  import Keys from "../lib/engine/Chords/Keys";
  import { fiveToFive } from "../lib/engine/Chords/MajorScale";
  import Hat from "../lib/engine/Drums/Hat";
  import Kick from "../lib/engine/Drums/Kick";
  import Noise from "../lib/engine/Drums/Noise";
  import Snare from "../lib/engine/Drums/Snare";
  import Piano from "../lib/engine/Piano/Piano";

  const STORAGE_KEY = "Volumes";
  const SONG_MODE_STORAGE_KEY = "SongModeConfig";
  const AUTO_START_KEY = "AutoStartSong";
  const DEFFAULT_VOLUMES = {
    rain: 0.35,
    thunder: 1,
    campfire: 1,
    jungle: 1,
    main_track: 1,
  };
  // Load previous vols or defualt
  let volumes =
    JSON.parse(localStorage.getItem(STORAGE_KEY)) || DEFFAULT_VOLUMES;
  // Convert linear volume (0 to 1) to dB
  const linearToDb = (value) =>
    value === 0 ? -Infinity : 20 * Math.log10(value);

  // Setup audio chain
  const cmp = new Tone.Compressor({
    threshold: -6,
    ratio: 3,
    attack: 0.5,
    release: 0.1,
  });
  const lpf = new Tone.Filter(2000, "lowpass");
  const vol = new Tone.Volume(linearToDb(volumes.main_track));
  Tone.Master.chain(cmp, lpf, vol);
  Tone.Transport.bpm.value = 156;
  Tone.Transport.swing = 1;

  // State variables
  let key = "C";
  let progression = [];
  let scale = [];
  let progress = 0;
  let scalePos = 0;

  let pianoLoaded = false;
  let kickLoaded = false;
  let snareLoaded = false;
  let hatLoaded = false;

  let contextStarted = false;
  let genChordsOnce = false;

  let kickOff = false;
  let snareOff = false;
  let hatOff = false;
  let melodyDensity = 0.33;
  let melodyOff = false;

  let isPlaying = false;
  let autoDJMode = "MUSIC";
  let generationCount = 0;
  let autoStartTriggered = false;
  let autoStartSong =
    localStorage.getItem(AUTO_START_KEY) === null
      ? true
      : localStorage.getItem(AUTO_START_KEY) === "true";

  type SongMood = "chill" | "balanced" | "energetic";
  type SongModeConfig = {
    enabled: boolean;
    seed: string;
    key: string;
    mood: SongMood;
    density: number;
    bpmOverride?: number | null;
    progression?: number[];
    melodies?: number[][];
    mlTitle?: string;
    mlSource?: "predict" | "decode" | "";
    mlServerUrl?: string;
    mlInput?: string;
  };

  const defaultSongMode: SongModeConfig = {
    enabled: false,
    seed: "lofi-seed",
    key: "AUTO",
    mood: "balanced",
    density: 0.33,
    bpmOverride: null,
    progression: [],
    melodies: [],
    mlTitle: "",
    mlSource: "",
    mlServerUrl: "",
    mlInput: "",
  };

  let songMode: SongModeConfig = loadSongModeConfig();
  let songRng: null | (() => number) = null;

  let isRecording = false;
  let mediaRecorder: MediaRecorder | null = null;
  let recordDestination: MediaStreamAudioDestinationNode | null = null;
  let recordingChunks: BlobPart[] = [];
  let canRecord = false;
  let isExporting = false;
  let exportStopTimer: number | null = null;
  let isAudioExporting = false;
  let audioExportStopTimer: number | null = null;
  let audioExportMinutes = 3;
  let isWavExporting = false;
  let wavExportMinutes = 3;
  let isUiHidden = localStorage.getItem("UIControlsHidden") === "true";

  // Initialize instruments
  const pn = new Piano(() => (pianoLoaded = true)).sampler;
  const kick = new Kick(() => (kickLoaded = true)).sampler;
  const snare = new Snare(() => (snareLoaded = true)).sampler;
  const hat = new Hat(() => (hatLoaded = true)).sampler;
  const noise = Noise;

  // Sequences
  let chords, melody, kickLoop, snareLoop, hatLoop;

  function loadSongModeConfig(): SongModeConfig {
    const saved = localStorage.getItem(SONG_MODE_STORAGE_KEY);
    if (!saved) {
      return { ...defaultSongMode };
    }

    try {
      const parsed = JSON.parse(saved);
      return {
        enabled: !!parsed.enabled,
        seed: parsed.seed || "lofi-seed",
        key: parsed.key || "AUTO",
        mood: parsed.mood || "balanced",
        density: clamp(Number(parsed.density ?? 0.33), 0.1, 0.95),
        bpmOverride: Number.isFinite(parsed.bpmOverride) ? Number(parsed.bpmOverride) : null,
        progression: Array.isArray(parsed.progression)
          ? parsed.progression.map((value) => Number(value)).filter((value) => Number.isInteger(value))
          : [],
        melodies: Array.isArray(parsed.melodies) ? parsed.melodies : [],
        mlTitle: parsed.mlTitle || "",
        mlSource: parsed.mlSource === "decode" ? "decode" : parsed.mlSource === "predict" ? "predict" : "",
        mlServerUrl: parsed.mlServerUrl || "",
        mlInput: parsed.mlInput || "",
      };
    } catch {
      return { ...defaultSongMode };
    }
  }

  function clamp(value: number, min: number, max: number) {
    return Math.max(min, Math.min(max, value));
  }

  function normalizeOptionalNumber(value: unknown) {
    return typeof value === "number" && Number.isFinite(value) ? value : null;
  }

  function normalizeMelodies(input?: number[][]) {
    return (Array.isArray(input) ? input : [])
      .map((row) =>
        (Array.isArray(row) ? row : [])
          .map((value) => Number(value))
          .filter((value) => Number.isInteger(value) && value >= 0 && value <= 15)
          .slice(0, 8),
      )
      .filter((row) => row.length > 0)
      .slice(0, 16);
  }

  function hashSeed(value: string): number {
    let hash = 1779033703 ^ value.length;
    for (let i = 0; i < value.length; i++) {
      hash = Math.imul(hash ^ value.charCodeAt(i), 3432918353);
      hash = (hash << 13) | (hash >>> 19);
    }
    return hash >>> 0;
  }

  function createRng(seed: number) {
    let state = seed >>> 0;
    return () => {
      state += 0x6d2b79f5;
      let t = state;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function random() {
    return songRng ? songRng() : Math.random();
  }

  function getMoodProfile(mood: SongMood) {
    if (mood === "chill") {
      return {
        bpm: 126,
        swing: 0.7,
        kickDropChance: 0.24,
        snareDropChance: 0.27,
        hatDropChance: 0.33,
        melodyDropChance: 0.4,
      };
    }
    if (mood === "energetic") {
      return {
        bpm: 170,
        swing: 0.95,
        kickDropChance: 0.08,
        snareDropChance: 0.11,
        hatDropChance: 0.16,
        melodyDropChance: 0.12,
      };
    }
    return {
      bpm: 156,
      swing: 1,
      kickDropChance: 0.13,
      snareDropChance: 0.17,
      hatDropChance: 0.22,
      melodyDropChance: 0.25,
    };
  }

  function applySongModeConfig(incoming: Partial<SongModeConfig>) {
    const incomingProgression = Array.isArray(incoming.progression)
      ? incoming.progression.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value >= 1 && value <= 7)
      : songMode.progression || [];
    const incomingMelodies = normalizeMelodies(incoming.melodies ?? songMode.melodies);
    const incomingBpmOverride = normalizeOptionalNumber(incoming.bpmOverride ?? songMode.bpmOverride);

    songMode = {
      ...songMode,
      ...incoming,
      seed: (incoming.seed ?? songMode.seed ?? "lofi-seed").trim() || "lofi-seed",
      density: clamp(Number(incoming.density ?? songMode.density), 0.1, 0.95),
      bpmOverride: incomingBpmOverride,
      progression: incomingProgression,
      melodies: incomingMelodies,
    };

    const moodProfile = getMoodProfile(songMode.mood);
    const targetBpm = songMode.enabled ? (songMode.bpmOverride ?? moodProfile.bpm) : 156;
    Tone.Transport.bpm.rampTo(targetBpm, 0.2);
    Tone.Transport.swing = songMode.enabled ? moodProfile.swing : 1;

    if (songMode.enabled) {
      melodyDensity = clamp(songMode.density, 0.1, 0.95);
    }

    localStorage.setItem(SONG_MODE_STORAGE_KEY, JSON.stringify(songMode));
  }

  function setupRecorder() {
    try {
      // @ts-ignore createMediaStreamDestination exists in WebAudio contexts used by Tone.
      recordDestination = Tone.context.rawContext.createMediaStreamDestination();
      // @ts-ignore Tone.Master is the current destination node alias used in this project.
      Tone.Master.connect(recordDestination);
      canRecord = typeof MediaRecorder !== "undefined";
    } catch {
      canRecord = false;
    }
  }

  function saveRecording(blob: Blob, filePrefix = "lofi-scene") {
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `${filePrefix}-${timestamp}.webm`;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    URL.revokeObjectURL(url);
  }

  function writeString(view: DataView, offset: number, value: string) {
    for (let i = 0; i < value.length; i++) {
      view.setUint8(offset + i, value.charCodeAt(i));
    }
  }

  function audioBufferToWavBuffer(audioBuffer: AudioBuffer) {
    const numChannels = audioBuffer.numberOfChannels;
    const sampleRate = audioBuffer.sampleRate;
    const bytesPerSample = 2;
    const dataLength = audioBuffer.length * numChannels * bytesPerSample;
    const buffer = new ArrayBuffer(44 + dataLength);
    const view = new DataView(buffer);

    const channelData = Array.from({ length: numChannels }, (_, index) =>
      audioBuffer.getChannelData(index),
    );

    writeString(view, 0, "RIFF");
    view.setUint32(4, 36 + dataLength, true);
    writeString(view, 8, "WAVE");
    writeString(view, 12, "fmt ");
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, sampleRate * numChannels * bytesPerSample, true);
    view.setUint16(32, numChannels * bytesPerSample, true);
    view.setUint16(34, 16, true);
    writeString(view, 36, "data");
    view.setUint32(40, dataLength, true);

    let offset = 44;
    for (let sampleIndex = 0; sampleIndex < audioBuffer.length; sampleIndex++) {
      for (let channelIndex = 0; channelIndex < numChannels; channelIndex++) {
        const channelSample = Math.max(-1, Math.min(1, channelData[channelIndex][sampleIndex]));
        view.setInt16(
          offset,
          channelSample < 0 ? channelSample * 0x8000 : channelSample * 0x7fff,
          true,
        );
        offset += 2;
      }
    }

    return buffer;
  }

  async function convertAudioBlobToWav(blob: Blob) {
    const arrayBuffer = await blob.arrayBuffer();
    const decodedBuffer = await Tone.context.rawContext.decodeAudioData(arrayBuffer.slice(0));
    const wavBuffer = audioBufferToWavBuffer(decodedBuffer);
    return new Blob([wavBuffer], { type: "audio/wav" });
  }

  function startRecording(onStop: (blob: Blob) => void | Promise<void>, mimeType = "audio/webm;codecs=opus") {
    if (!canRecord || !recordDestination || isRecording) {
      return;
    }

    recordingChunks = [];

    try {
      mediaRecorder = new MediaRecorder(recordDestination.stream, {
        mimeType,
      });
    } catch {
      mediaRecorder = new MediaRecorder(recordDestination.stream);
    }

    mediaRecorder.ondataavailable = (event) => {
      if (event.data.size > 0) {
        recordingChunks.push(event.data);
      }
    };

    mediaRecorder.onstop = () => {
      const blob = new Blob(recordingChunks, { type: mediaRecorder?.mimeType || mimeType });
      void onStop(blob);
    };

    mediaRecorder.start();
    isRecording = true;
  }

  function parseDurationMinutes(value: unknown) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
      return null;
    }
    const clamped = clamp(parsed, 1, 30);
    return Math.round(clamped * 10) / 10;
  }

  function startAudioExportByMinutes(minutes: number) {
    if (!canRecord || !recordDestination || isRecording || isExporting) {
      return;
    }

    audioExportMinutes = minutes;
    isAudioExporting = true;

    if (!genChordsOnce) {
      generateProgression();
    }
    if (!isPlaying) {
      toggle();
    }

    startRecording(async (blob) => {
      if (blob.size > 0) {
        saveRecording(blob, "lofi-audio");
      }
      if (audioExportStopTimer !== null) {
        clearTimeout(audioExportStopTimer);
        audioExportStopTimer = null;
      }
      isAudioExporting = false;
    });
    if (!isRecording) {
      isAudioExporting = false;
      return;
    }

    if (audioExportStopTimer !== null) {
      clearTimeout(audioExportStopTimer);
    }
    audioExportStopTimer = window.setTimeout(() => {
      stopRecording();
    }, Math.round(minutes * 60000));
  }

  function startWavExportByMinutes(minutes: number) {
    if (!canRecord || !recordDestination || isRecording || isExporting) {
      return;
    }

    wavExportMinutes = minutes;
    isWavExporting = true;

    if (!genChordsOnce) {
      generateProgression();
    }
    if (!isPlaying) {
      toggle();
    }

    startRecording(async (blob) => {
      try {
        if (blob.size > 0) {
          const wavBlob = await convertAudioBlobToWav(blob);
          saveRecording(wavBlob, "lofi-audio");
        }
      } finally {
        if (audioExportStopTimer !== null) {
          clearTimeout(audioExportStopTimer);
          audioExportStopTimer = null;
        }
        isWavExporting = false;
      }
    });

    if (!isRecording) {
      isWavExporting = false;
      return;
    }

    if (audioExportStopTimer !== null) {
      clearTimeout(audioExportStopTimer);
    }
    audioExportStopTimer = window.setTimeout(() => {
      stopRecording();
    }, Math.round(minutes * 60000));
  }

  function startAutoAudioExport() {
    if (!canRecord || isRecording || isExporting) {
      return;
    }
    const entered = window.prompt(
      "Export audio duration in minutes (1 to 30):",
      String(audioExportMinutes),
    );
    if (entered === null) {
      return;
    }

    const minutes = parseDurationMinutes(entered);
    if (minutes === null) {
      return;
    }

    startAudioExportByMinutes(minutes);
  }

  function startQuickWavExport() {
    startWavExportByMinutes(wavExportMinutes);
  }

  function stopRecording() {
    if (mediaRecorder && isRecording) {
      mediaRecorder.stop();
      isRecording = false;
    }
  }

  async function startSceneExport() {
    if (!canRecord || isExporting || !recordDestination) {
      return;
    }

    isExporting = true;
    if (!genChordsOnce) {
      generateProgression();
    }
    if (!isPlaying) {
      toggle();
    }
    window.dispatchEvent(
      new CustomEvent("lofi-scene-export-state", { detail: { isExporting: true } }),
    );

    await new Promise((resolve) => setTimeout(resolve, 250));

    let displayStream: MediaStream;
    try {
      displayStream = await navigator.mediaDevices.getDisplayMedia({
        video: true,
        audio: false,
      });
    } catch {
      isExporting = false;
      window.dispatchEvent(
        new CustomEvent("lofi-scene-export-state", { detail: { isExporting: false } }),
      );
      return;
    }

    const videoTrack = displayStream.getVideoTracks()[0];
    if (!videoTrack) {
      isExporting = false;
      window.dispatchEvent(
        new CustomEvent("lofi-scene-export-state", { detail: { isExporting: false } }),
      );
      return;
    }

    const combinedStream = new MediaStream([
      videoTrack,
      ...recordDestination.stream.getAudioTracks(),
    ]);

    recordingChunks = [];
    try {
      mediaRecorder = new MediaRecorder(combinedStream, {
        mimeType: "video/webm;codecs=vp9,opus",
      });
    } catch {
      mediaRecorder = new MediaRecorder(combinedStream);
    }

    mediaRecorder.ondataavailable = (event) => {
      if (event.data.size > 0) {
        recordingChunks.push(event.data);
      }
    };

    mediaRecorder.onstop = () => {
      const blob = new Blob(recordingChunks, { type: mediaRecorder?.mimeType || "video/webm" });
      if (blob.size > 0) {
        saveRecording(blob);
      }
      displayStream.getTracks().forEach((track) => track.stop());
      isExporting = false;
      window.dispatchEvent(
        new CustomEvent("lofi-scene-export-state", { detail: { isExporting: false } }),
      );
    };

    mediaRecorder.start();
    isRecording = true;
    exportStopTimer = window.setTimeout(() => {
      if (mediaRecorder && isRecording) {
        mediaRecorder.stop();
        isRecording = false;
      }
    }, 120000);
  }

  onMount(() => {
    setupRecorder();
    applySongModeConfig(songMode);

    // Setup sequences
    chords = new Tone.Sequence(
      (time, note) => {
        playChord();
      },
      [""],
      "1n",
    );

    melody = new Tone.Sequence(
      (time, note) => {
        playMelody();
      },
      [""],
      "8n",
    );

    kickLoop = new Tone.Sequence(
      (time, note) => {
        if (!kickOff) {
          if (note === "C4" && Math.random() < 0.9) {
            // @ts-ignore
            kick.triggerAttack(note);
          } else if (note === "." && Math.random() < 0.1) {
            // @ts-ignore
            kick.triggerAttack("C4");
          }
        }
      },
      ["C4", "", "", "", "", "", "", "C4", "C4", "", ".", "", "", "", "", ""],
      "8n",
    );

    snareLoop = new Tone.Sequence(
      (time, note) => {
        if (!snareOff) {
          if (note !== "" && Math.random() < 0.8) {
            // @ts-ignore
            snare.triggerAttack(note);
          }
        }
      },
      ["", "C4"],
      "2n",
    );

    hatLoop = new Tone.Sequence(
      (time, note) => {
        if (!hatOff) {
          // @ts-ignore
          if (note !== "" && Math.random() < 0.8) {
            // @ts-ignore
            hat.triggerAttack(note);
          }
        }
      },
      ["C4", "C4", "C4", "C4", "C4", "C4", "C4", "C4"],
      "4n",
    );

    chords.humanize = true;
    melody.humanize = true;
    kickLoop.humanize = true;
    snareLoop.humanize = true;
    hatLoop.humanize = true;

    // Listen for spacebar press
    const handleKeydown = (e) => {
      if (e.code === "Space") {
        e.preventDefault();
        toggle();
      }
    };

    const handleCustomToggle = () => {
      handleButtonAction();
    };

    const handleAutoDJModeChange = (e) => {
      autoDJMode = e.detail.mode;
    };

    const handleSongModeChange = (e) => {
      const detail = e.detail || {};
      applySongModeConfig(detail);
      if (detail.regenerate) {
        generateProgression();
      }
    };

    const handleAudioExport = (e) => {
      const detail = e?.detail || {};
      const minutes = parseDurationMinutes(detail.minutes);
      if (minutes === null) {
        startAutoAudioExport();
        return;
      }
      startAudioExportByMinutes(minutes);
    };

    const handleUiVisibility = (event: Event) => {
      const customEvent = event as CustomEvent;
      isUiHidden = !!customEvent.detail?.hidden;
    };

    window.addEventListener("keydown", handleKeydown);
    window.addEventListener("lofi-toggle-play", handleCustomToggle);
    window.addEventListener("auto-dj-mode-changed", handleAutoDJModeChange);
    window.addEventListener("song-mode-changed", handleSongModeChange);
    window.addEventListener("lofi-export-audio", handleAudioExport);
    window.addEventListener("lofi-ui-visibility-changed", handleUiVisibility);

    // Initialize mode
    autoDJMode = localStorage.getItem("AutoDJMode") || "MUSIC";

    return () => {
      window.removeEventListener("keydown", handleKeydown);
      window.removeEventListener("lofi-toggle-play", handleCustomToggle);
      window.removeEventListener("auto-dj-mode-changed", handleAutoDJModeChange);
      window.removeEventListener("song-mode-changed", handleSongModeChange);
      window.removeEventListener("lofi-export-audio", handleAudioExport);
      window.removeEventListener("lofi-ui-visibility-changed", handleUiVisibility);
    };
  });

  onDestroy(() => {
    if (exportStopTimer !== null) {
      clearTimeout(exportStopTimer);
    }
    if (audioExportStopTimer !== null) {
      clearTimeout(audioExportStopTimer);
    }
    if (isRecording && mediaRecorder) {
      mediaRecorder.stop();
      isRecording = false;
    }
    if (Tone.Transport.state === "started") {
      noise.stop();
      Tone.Transport.stop();
    }
  });

  let barCount = 0;
  let sectionBarLength = 32; // change section every 32 bars
  let isTransitioning = false;
  let melodyStep = 0;

  function buildProgressionFromDegrees(degrees: number[]) {
    return degrees
      .map((degree) => Chords[degree - 1])
      .filter((chord) => !!chord);
  }

  function buildMelodyNotes(stepIndex: number) {
    const melodyRows = normalizeMelodies(songMode.melodies || []);
    if (!melodyRows.length || !scale.length) {
      return null;
    }

    const chordIndex = Math.min(Math.floor(stepIndex / 8), melodyRows.length - 1);
    const chordMelody = melodyRows[chordIndex] || [];
    if (!chordMelody.length) {
      return null;
    }

    const noteIndex = stepIndex % chordMelody.length;
    const noteDegree = chordMelody[noteIndex];
    if (!Number.isInteger(noteDegree) || noteDegree < 0 || noteDegree >= scale.length) {
      return null;
    }

    return scale[noteDegree];
  }

  function nextChord() {
    const nextProgress = progress === progression.length - 1 ? 0 : progress + 1;
    const moodProfile = getMoodProfile(songMode.mood);
    const nextKickOff = random() < moodProfile.kickDropChance;
    const nextSnareOff = random() < moodProfile.snareDropChance;
    const nextHatOff = random() < moodProfile.hatDropChance;
    const nextMelodyDensity = songMode.enabled
      ? clamp(songMode.density + (random() - 0.5) * 0.14, 0.1, 0.95)
      : random() * 0.3 + 0.2;
    const nextMelodyOff = random() < moodProfile.melodyDropChance;

    if (progress === 4) {
      progress = nextProgress;
      kickOff = nextKickOff;
      snareOff = nextSnareOff;
      hatOff = nextHatOff;
    } else if (progress === 0) {
      progress = nextProgress;
      kickOff = nextKickOff;
      snareOff = nextSnareOff;
      hatOff = nextHatOff;
      melodyDensity = nextMelodyDensity;
      melodyOff = nextMelodyOff;
    } else {
      progress = nextProgress;
    }
    barCount++;
    if(barCount >= sectionBarLength) {
      barCount = 0;
      autoDJTransition();
      // New next transition length
      const barLengthOptions = [16, 20, 24, 28, 32, 48];
        sectionBarLength = barLengthOptions[Math.floor(random() * barLengthOptions.length)];
    }
  }

  function autoDJTransition() {
    if(isTransitioning) return; // Prevent overlaps
    if(autoDJMode === "MANUAL") return;

    isTransitioning = true;
    const currentGain = linearToDb(volumes.main_track);

    // Change keys/chords
    generateProgression()
    
    // Original Instrument Logic (Applied in ALL active modes: MUSIC, ATMOSPHERE, WORLD)
    // This was the "current main lofi track generation"
    const moodProfile = getMoodProfile(songMode.mood);
    melodyDensity = songMode.enabled
      ? clamp(songMode.density + (random() - 0.5) * 0.2, 0.1, 0.95)
      : 0.2 + random() * 0.5;
    kickOff = random() < moodProfile.kickDropChance;
    snareOff = random() < moodProfile.snareDropChance;
    hatOff = random() < moodProfile.hatDropChance;
    melodyOff = random() < moodProfile.melodyDropChance;

    // Smart Effects: Toggle environmental effects randomly
    // Applied in ATMOSPHERE and WORLD
    if (autoDJMode === "ATMOSPHERE" || autoDJMode === "WORLD") {
      const effects = ["rain", "thunder", "jungle", "campfire"];
      // 30% chance to toggle an effect
      if (random() < 0.3) {
        const effect = effects[Math.floor(random() * effects.length)];
        window.dispatchEvent(new CustomEvent(`lofi-toggle-${effect}`));
      }
    }

    // Smart Tracks: Rotate the active music source so it does not stay stuck.
    if (autoDJMode === "MUSIC" || autoDJMode === "ATMOSPHERE") {
      window.dispatchEvent(new CustomEvent("lofi-cycle-track"));
    } else if (autoDJMode === "WORLD") {
      window.dispatchEvent(new CustomEvent("lofi-random-track"));
    }

    // Crossfade FX (Always apply for smoother transitions if not OFF)
    vol.volume.rampTo(currentGain - 4, 1.2);
    lpf.frequency.linearRampTo(300, 3) // longer muffle for smoother blend
    setTimeout(() => {
      lpf.frequency.linearRampTo(1200, 3) // longer open-up for smoother blend
      vol.volume.rampTo(currentGain, 1.4);
      setTimeout(() => {
        isTransitioning = false;
      }, 3000);
    }, 3000);
  }

  function playChord() {
    const chord = progression[progress];
    const root = Tone.Frequency(key + "3").transpose(chord.semitoneDist);
    const size = 4;
    const voicing = chord.generateVoicing(size, random);
    const notes = Tone.Frequency(root)
      .harmonize(voicing)
      .map((f) => Tone.Frequency(f).toNote());
    // @ts-ignore
    pn.triggerAttackRelease(notes, "1n");
    nextChord();
  }

  function playMelody() {
    if (melodyOff || !(random() < melodyDensity)) {
      return;
    }

    const modelMelody = songMode.enabled ? buildMelodyNotes(melodyStep) : null;
    melodyStep = (melodyStep + 1) % 64;

    if (modelMelody) {
      // @ts-ignore
      pn.triggerAttackRelease(modelMelody, "8n");
      return;
    }

    const descendRange = Math.min(scalePos, 7) + 1;
    const ascendRange = Math.min(scale.length - scalePos, 7);

    let descend = descendRange > 1;
    let ascend = ascendRange > 1;

    if (descend && ascend) {
      if (random() > 0.5) {
        ascend = !descend;
      } else {
        descend = !ascend;
      }
    }

    let weights = descend
      ? intervalWeights.slice(0, descendRange)
      : intervalWeights.slice(0, ascendRange);

    const sum = weights.reduce((prev, curr) => prev + curr, 0);
    weights = weights.map((w) => w / sum);
    for (let i = 1; i < weights.length; i++) {
      weights[i] += weights[i - 1];
    }

    const randomWeight = random();
    let scaleDist = 0;
    let found = false;
    while (!found) {
      if (randomWeight <= weights[scaleDist]) {
        found = true;
      } else {
        scaleDist++;
      }
    }

    const scalePosChange = descend ? -scaleDist : scaleDist;
    const newScalePos = scalePos + scalePosChange;

    scalePos = newScalePos;
    // @ts-ignore
    pn.triggerAttackRelease(scale[newScalePos], "2n");
  }

  function generateProgression() {
    const _scale = fiveToFive;
    generationCount += 1;
    if (songMode.enabled) {
      songRng = createRng(hashSeed(`${songMode.seed}-${generationCount}`));
    } else {
      songRng = null;
    }

    const newKey =
      songMode.enabled && songMode.key !== "AUTO"
        ? songMode.key
        : Keys[Math.floor(random() * Keys.length)];
    const newScale = Tone.Frequency(newKey + "5")
      .harmonize(_scale)
      .map((f) => Tone.Frequency(f).toNote());
    const mlProgression = buildProgressionFromDegrees(songMode.progression || []);
    const newProgression = mlProgression.length >= 2 ? mlProgression : ChordProgression.generate(8, random);
    const newScalePos = Math.floor(random() * _scale.length);

    key = newKey;
    progress = 0;
    progression = newProgression;
    scale = newScale;
    genChordsOnce = true;
    scalePos = newScalePos;
    melodyStep = 0;
  }

  function toggle() {
    progress = 0;
    if (Tone.Transport.state === "started") {
      noise.stop();
      Tone.Transport.stop();
      isPlaying = false;
    } else {
      Tone.start();
      Tone.Transport.start();
      noise.start(0);
      chords.start(0);
      melody.start(0);
      kickLoop.start(0);
      snareLoop.start(0);
      hatLoop.start(0);
      isPlaying = true;
    }
    window.dispatchEvent(new CustomEvent("lofi-play-state-changed", { detail: { isPlaying } }));
  }

  function startAudioContext() {
    Tone.start();
    contextStarted = true;
  }

  $: allSamplesLoaded = pianoLoaded && kickLoaded && snareLoaded && hatLoaded;
  $: activeProgressionIndex = (progress + 7) % 8;
  // Update volume
  onMount(() => {
    setInterval(() => {
      let updatedVol =
        JSON.parse(localStorage.getItem(STORAGE_KEY)) || DEFFAULT_VOLUMES;
      vol.volume.value = linearToDb(updatedVol.main_track);
    }, 100);
  });
  // automically start audio context after samples are loaded
  $: if (allSamplesLoaded && !contextStarted) {
    startAudioContext();
    generateProgression();
  }

  // Automatically start song generation/playback once everything is prepared.
  $: if (
    allSamplesLoaded &&
    contextStarted &&
    genChordsOnce &&
    autoStartSong &&
    !autoStartTriggered &&
    !isPlaying
  ) {
    autoStartTriggered = true;
    toggle();
  }

  function handleButtonAction() {
    if (!allSamplesLoaded) {
      // Do nothing, button is disabled
      return;
    } else if (!contextStarted) {
      // Initialize audio context
      startAudioContext();
    } else if (!genChordsOnce) {
      // Chords not generated yet, can't play
      return;
    } else {
      // Normal play/pause functionality
      toggle();
    }
  }

</script>

<div>
  <div class:exporting={isExporting} class="controls">
    <button
      class="play-button"
      on:click={handleButtonAction}
      disabled={!allSamplesLoaded}
    >
      {#if !allSamplesLoaded}
        <IconLoader size={30} class="spinning" />
      {:else if !contextStarted}
        <span class="context-text">Initialize Audio</span>
      {:else if !genChordsOnce}
        <IconPlayerPlayFilled size={30} class="disabled" />
      {:else if isPlaying}
        <IconPlayerPauseFilled size={30} />
      {:else}
        <IconPlayerPlayFilled size={30} />
      {/if}
    </button>
    {#if !isUiHidden}
      <button
        class="recordBtn glass"
        on:click={startAutoAudioExport}
        disabled={!canRecord || isExporting || isRecording || isAudioExporting || isWavExporting}
      >
        {#if isAudioExporting}
          Audio {audioExportMinutes}m...
        {:else}
          Audio {audioExportMinutes}m
        {/if}
      </button>
      <button
        class="recordBtn glass"
        on:click={startSceneExport}
        disabled={!canRecord || isExporting || isAudioExporting || isRecording}
      >
        Export 2m
      </button>
      <button
        class="recordBtn glass"
        on:click={startQuickWavExport}
        disabled={!canRecord || isExporting || isRecording || isAudioExporting || isWavExporting}
      >
        {#if isWavExporting}
          WAV {wavExportMinutes}m...
        {:else}
          WAV {wavExportMinutes}m
        {/if}
      </button>
    {/if}
  </div>

  {#if allSamplesLoaded && contextStarted}
    {#if genChordsOnce && !isExporting}
      <ol class="progressionList">
        <li class="key" id="glass">{key}</li>
        {#each progression as chord, idx}
          <li id="glass" class={idx === activeProgressionIndex ? "live" : ""}>
            {chord.degree}
          </li>
        {/each}
      </ol>
    {/if}
  {/if}
  <!-- Visualizer intentionally hidden to prevent overlay conflicts and keep layout clean. -->
</div>

<style>
  .controls {
    position: fixed;
    bottom: 70px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    flex-direction: column-reverse;
    justify-content: center;
    align-items: center;
    gap: 5px;
    z-index: 40;
  }

  .controls.exporting {
    opacity: 0;
    pointer-events: none;
  }

  .play-button {
    width: 70px;
    height: 70px;
    border-radius: 50%;
    background-color: white;
    color: black;
    display: flex;
    justify-content: center;
    align-items: center;
    z-index: 10;
    border: none;
    cursor: pointer;
    box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2);
  }

  .play-button:hover {
    box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.5);
  }

  .recordBtn {
    color: white;
    border: none;
    border-radius: 999px;
    min-width: 98px;
    height: 34px;
    padding: 0 10px;
    margin-top: 2px;
    font-size: 12px;
    outline: none;
  }

  .recordBtn:disabled {
    opacity: 0.55;
    cursor: not-allowed;
  }

  .progressionList {
    position: fixed;
    bottom: 6px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    gap: 10px;
    list-style: none;
    padding: 0;
    justify-content: center;
    flex-wrap: wrap;
    gap: 20px;
    z-index: 12;
  }

  .progressionList li {
    padding: 5px 10px;
    border-radius: 4px;
    color: white;
    border: 2px solid transparent;
  }

  .progressionList li.live {
    border-color:#ffffff66;
  }

  .visualizer-container {
    position: fixed;
    left: 50%;
    bottom: 230px;
    transform: translateX(-50%);
    width: min(420px, 74vw);
    height: 86px;
    overflow: hidden;
    margin-top: 0;
    z-index: 15;
    pointer-events: none;
  }

  :global(.exporting) .visualizer-container {
    opacity: 0.5;
  }

  @media only screen and (max-width: 600px) {
    .play-button {
      margin-bottom: 40px;
    }
    .progressionList {
      bottom: 0;
      left: 0;
      width: 100vw;
      transform: scale(0.8);
      z-index: 11;
    }
    .visualizer-container {
      bottom: 114px;
      display: none;
    }
  }
</style>
