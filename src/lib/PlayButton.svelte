<script lang="ts">
  import {
      IconLoader,
      IconPlayerPauseFilled,
      IconPlayerPlayFilled,
  } from "@tabler/icons-svelte";
  import { onDestroy, onMount } from "svelte";
  import { scale as scaleTransition, fade } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
// @ts-ignore
  import * as Tone from "tone";
  import ChordProgression from "../lib/engine/Chords/ChordProgression";
  import intervalWeights from "../lib/engine/Chords/IntervalWeights";
  import Keys from "../lib/engine/Chords/Keys";
  import { fiveToFive } from "../lib/engine/Chords/MajorScale";
  import Hat from "../lib/engine/Drums/Hat";
  import Kick from "../lib/engine/Drums/Kick";
  import Noise from "../lib/engine/Drums/Noise";
  import Snare from "../lib/engine/Drums/Snare";
  import Piano from "../lib/engine/Piano/Piano";

  const STORAGE_KEY = "volumes"; // matches Controls/index.svelte
  const SONG_MODE_STORAGE_KEY = "SongModeConfig";
  const AUTO_START_KEY = "AutoStartSong";
  const DEFFAULT_VOLUMES = {
    rain: 1,
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
  };

  const defaultSongMode: SongModeConfig = {
    enabled: false,
    seed: "lofi-seed",
    key: "AUTO",
    mood: "balanced",
    density: 0.33,
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
  let countdownProgress = 0;        
  let countdownStart = Date.now();  
  let countdownFrame: number;       
  let transitionFlash = false;      

  // Initialize instruments
  const pn = new Piano(() => (pianoLoaded = true)).sampler;
  const kick = new Kick(() => (kickLoaded = true)).sampler;
  const snare = new Snare(() => (snareLoaded = true)).sampler;
  const hat = new Hat(() => (hatLoaded = true)).sampler;
  const noise = Noise;

  // Drum pattern banks
  const KICK_PATTERNS = [
    ["C4", "", "", "", "", "", "", "C4", "C4", "", ".", "", "", "", "", ""],  // classic two-step
    ["C4", "", "", "", "C4", "", "", "", "C4", "", "", "", "C4", "", "", ""],  // four-on-the-floor
    ["C4", "", "C4", "", "", "", "C4", "", "", "C4", "", "", "C4", "", "", ""],  // syncopated
    ["C4", "", "", "", "", "", "C4", "", "", "", "C4", "", "", "C4", "", ""],  // half-time feel
    ["C4", ".", "", "", "C4", "", "C4", "", "", "", "C4", "", "", "", "C4", ""],  // busy
    ["C4", "", "", "", "", "", "", "", "C4", "", "", "", "", "", "", ""],  // sparse
  ];
  const SNARE_PATTERNS = [
    ["", "C4"],                          // classic backbeat (2n)
    ["", "C4", "", "C4"],                // every-beat (4n)
    ["", "C4", "C4", ""],               // shifted
    ["", "", "C4", ""],                  // delayed
    ["C4", "", "", "C4"],               // reverse
  ];
  let currentKickPattern = 0;
  let currentSnarePattern = 0;

  function rotatePatterns() {
    const nextKick = (currentKickPattern + 1 + Math.floor(Math.random() * (KICK_PATTERNS.length - 1))) % KICK_PATTERNS.length;
    const nextSnare = (currentSnarePattern + 1 + Math.floor(Math.random() * (SNARE_PATTERNS.length - 1))) % SNARE_PATTERNS.length;
    currentKickPattern = nextKick;
    currentSnarePattern = nextSnare;
    if (kickLoop) kickLoop.events = KICK_PATTERNS[nextKick];
    if (snareLoop) snareLoop.events = SNARE_PATTERNS[nextSnare];
  }

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
      };
    } catch {
      return { ...defaultSongMode };
    }
  }

  function clamp(value: number, min: number, max: number) {
    return Math.max(min, Math.min(max, value));
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
    songMode = {
      ...songMode,
      ...incoming,
      seed: (incoming.seed ?? songMode.seed ?? "lofi-seed").trim() || "lofi-seed",
      density: clamp(Number(incoming.density ?? songMode.density), 0.1, 0.95),
    };

    const moodProfile = getMoodProfile(songMode.mood);
    Tone.Transport.bpm.rampTo(songMode.enabled ? moodProfile.bpm : 156, 0.2);
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

  // Removed dead code: writeString, audioBufferToWavBuffer, convertAudioBlobToWav (not referenced)

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
      KICK_PATTERNS[currentKickPattern],
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
      SNARE_PATTERNS[currentSnarePattern],
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

    // Listen for spacebar + T key
    const handleKeydown = (e) => {
      if (e.code === "Space") {
        e.preventDefault();
        toggle();
      } else if (e.key.toLowerCase() === "t" && isPlaying && !isExporting) {
        // #6 — manual transition
        e.preventDefault();
        autoDJTransition();
        showTransitionFlash();
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

    // Auto-change the lofi every 60 seconds — skip if SongMode loop is active (it has its own timer)
    autoChangeTimer = setInterval(() => {
      const songModeCfg = (() => { try { return JSON.parse(localStorage.getItem("SongModeConfig") || "{}"); } catch { return {}; } })();
      if (isPlaying && autoDJMode !== "MANUAL" && !songModeCfg.loopEnabled) {
        autoDJTransition();
      }
    }, 60000);

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
    cancelAnimationFrame(countdownFrame);
    if (autoChangeTimer !== null) clearInterval(autoChangeTimer);
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
  let sectionBarLength = 64; // keep bar-based transitions infrequent; clock timer handles the 1-min change
  let isTransitioning = false;
  let autoChangeTimer: ReturnType<typeof setInterval> | null = null;

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

  function showTransitionFlash() {
    transitionFlash = true;
    setTimeout(() => { transitionFlash = false; }, 1600);
  }

  function tickCountdown() {
    countdownProgress = Math.min(1, (Date.now() - countdownStart) / 60000);
    countdownFrame = requestAnimationFrame(tickCountdown);
  }

  function autoDJTransition() {
    if(isTransitioning) return; // Prevent overlaps
    if(autoDJMode === "MANUAL") return;

    isTransitioning = true;

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

    // Smart Tracks: Toggle tracks randomly
    // Applied ONLY in WORLD
    if (autoDJMode === "WORLD") {
      // 20% chance to toggle a track
      if (random() < 0.2) {
        window.dispatchEvent(new CustomEvent("lofi-random-track"));
      }
    }

    // Rotate drum patterns
    rotatePatterns();

    // Crossfade FX
    lpf.frequency.linearRampTo(300, 2);
    setTimeout(() => {
      lpf.frequency.linearRampTo(1200, 2);
      setTimeout(() => {
        isTransitioning = false;
      }, 2000);
    }, 2000);

    // #7 — notify App to rotate background; #1 — reset countdown ring
    countdownStart = Date.now();
    window.dispatchEvent(new CustomEvent("lofi-transition-fired"));
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
    const newProgression = ChordProgression.generate(8, random);
    const newScalePos = Math.floor(random() * _scale.length);

    key = newKey;
    progress = 0;
    progression = newProgression;
    scale = newScale;
    genChordsOnce = true;
    scalePos = newScalePos;
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
    countdownFrame = requestAnimationFrame(tickCountdown);
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
  <!-- #3 Now-playing chip -->
  {#if genChordsOnce && !isExporting && isPlaying}
    <div class="now-playing-chip">
      <span class="chip-key">{key}</span>
      <span class="chip-sep">·</span>
      <span class="chip-bpm">{Math.round(Tone.Transport.bpm.value)} BPM</span>
    </div>
  {/if}

  <!-- #1 countdown ring -->
  {#if genChordsOnce && isPlaying && !isExporting}
    <svg class="countdown-ring" viewBox="0 0 90 90" aria-hidden="true">
      <circle cx="45" cy="45" r="40" class="ring-track" />
      <circle cx="45" cy="45" r="40" class="ring-progress"
        style="stroke-dashoffset: {251.3 - 251.3 * countdownProgress}"
      />
    </svg>
  {/if}

  <div class:exporting={isExporting} class="controls">
    <button
      class="play-button"
      class:pulsing={isPlaying}
      on:click={handleButtonAction}
      disabled={!allSamplesLoaded}
    >
      {#if !allSamplesLoaded}
          <IconLoader size={34} class="spinning" />
      {:else if !contextStarted}
        <span in:fade={{ duration: 200 }} class="context-text">Initialize Audio</span>
      {:else}
        {#key isPlaying}
          <span
            class="icon-container"
            in:scaleTransition={{ duration: 400, delay: 50, easing: cubicOut }}
            out:scaleTransition={{ duration: 200, easing: cubicOut }}
          >
            {#if !genChordsOnce}
              <IconPlayerPlayFilled size={34} class="disabled" />
            {:else if isPlaying}
              <IconPlayerPauseFilled size={34} />
            {:else}
              <IconPlayerPlayFilled size={34} />
            {/if}
          </span>
        {/key}
      {/if}
    </button>
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

  <!-- #2 FFT Visualizer -->
  {#if genChordsOnce && contextStarted && !isExporting}
    <div class="visualizer-container">
      <Visualizer />
    </div>
  {/if}

  <!-- #6 Transition flash badge -->
  {#if transitionFlash}
    <div class="transition-flash" aria-live="assertive">↻ New vibe</div>
  {/if}

  <!-- T-key hint (top-left, only while playing) -->
  {#if isPlaying && !isExporting}
    <div class="t-key-hint">T  transition</div>
  {/if}

</div>

<style>
  /* ── Controls wrapper ── */
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
  .controls.exporting { opacity: 0; pointer-events: none; }

  /* ── Play button ── */
  .play-button :global(svg) { color: black !important; stroke: black !important; fill: black !important; }
  .play-button {
    width: 70px; height: 70px; border-radius: 50%;
    background-color: white; color: black;
    display: flex; justify-content: center; align-items: center;
    z-index: 10; border: none; cursor: pointer;
    box-shadow: 0 4px 24px rgba(0,0,0,0.35);
    transition: box-shadow 0.2s;
    position: relative; /* relative for absolute children icons */
  }
  .icon-container {
    position: absolute;
    display: flex;
    justify-content: center;
    align-items: center;
    inset: 0;
  }
  .play-button.pulsing {
    animation: buttonPulse 2s infinite ease-in-out;
    box-shadow: 0 0 25px 8px rgba(245,166,35,0.22);
  }
  @keyframes buttonPulse {
    0%   { transform: scale(1); }
    50%  { transform: scale(1.05); }
    100% { transform: scale(1); }
  }

  /* ── Countdown ring ── */
  .countdown-ring {
    position: fixed;
    bottom: 53px;
    left: 50%;
    transform: translateX(-50%);
    width: 90px; height: 90px;
    pointer-events: none;
    z-index: 39;
    filter: drop-shadow(0 0 8px rgba(245,166,35,0.4));
  }
  .ring-track {
    fill: none;
    stroke: rgba(255,255,255,0.08);
    stroke-width: 3.5;
  }
  .ring-progress {
    fill: none;
    stroke: #f5a623;
    stroke-width: 3.5;
    stroke-linecap: round;
    stroke-dasharray: 251.3;
    stroke-dashoffset: 251.3;
    transform: rotate(-90deg);
    transform-origin: 45px 45px;
    transition: stroke-dashoffset 0.8s linear;
  }

  /* ── #2 Visualizer container ── */
  .visualizer-container {
    position: fixed;
    left: 50%; bottom: 220px;
    transform: translateX(-50%);
    width: min(420px, 74vw); height: 56px;
    overflow: hidden; z-index: 15;
    pointer-events: none;
  }
  :global(.exporting) .visualizer-container { opacity: 0.5; }

  /* ── Now-playing chip ── */
  .now-playing-chip {
    position: fixed;
    bottom: 152px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 8px;
    background: rgba(10,10,14,0.62);
    backdrop-filter: blur(12px);
    border: 1px solid rgba(245,166,35,0.25);
    border-radius: 999px;
    padding: 5px 14px;
    z-index: 41;
    animation: chipIn 0.3s ease;
  }
  .chip-key, .chip-bpm {
    font-size: 11px;
    font-weight: 600;
    color: #f5a623;
    letter-spacing: 0.04em;
  }
  .chip-sep { color: rgba(255,255,255,0.3); font-size: 11px; }
  @keyframes chipIn {
    from { opacity: 0; transform: translateX(-50%) translateY(4px); }
    to   { opacity: 1; transform: translateX(-50%) translateY(0); }
  }

  /* ── Transition flash badge ── */
  .transition-flash {
    position: fixed;
    bottom: 160px;
    left: 50%;
    transform: translateX(-50%);
    background: rgba(245,166,35,0.18);
    border: 1px solid rgba(245,166,35,0.5);
    color: #f5a623;
    font-size: 12px;
    font-weight: 600;
    padding: 5px 16px;
    border-radius: 999px;
    z-index: 50;
    animation: flashIn 0.2s ease, flashOut 0.4s ease 1.2s forwards;
    pointer-events: none;
  }
  @keyframes flashIn  { from { opacity: 0; } to { opacity: 1; } }
  @keyframes flashOut { from { opacity: 1; } to { opacity: 0; } }

  /* ── T-key hint badge ── */
  .t-key-hint {
    position: fixed;
    top: 16px;
    left: 16px;
    background: rgba(0,0,0,0.45);
    backdrop-filter: blur(8px);
    border: 1px solid rgba(255,255,255,0.12);
    color: rgba(255,255,255,0.45);
    font-size: 11px;
    padding: 4px 10px;
    border-radius: 6px;
    z-index: 50;
    pointer-events: none;
    letter-spacing: 0.05em;
  }

  /* ── Progression list ── */
  .progressionList {
    position: fixed;
    bottom: 6px; left: 50%;
    transform: translateX(-50%);
    display: flex; gap: 20px;
    list-style: none; padding: 0;
    justify-content: center; flex-wrap: wrap;
    z-index: 12;
  }
  .progressionList li {
    padding: 5px 10px; border-radius: 4px;
    color: white; border: 2px solid transparent;
  }
  .progressionList li.live { border-color: #ffffff66; }

  @media only screen and (max-width: 600px) {
    .progressionList { bottom: 0; left: 0; width: 100vw; transform: scale(0.8); z-index: 11; }
    .visualizer-container { bottom: 114px; display: none; }
    .t-key-hint { display: none; }
    .now-playing-chip { bottom: 136px; }
  }
</style>

