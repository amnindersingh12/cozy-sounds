<script lang="ts">
  import { onDestroy, onMount } from "svelte";
  import Keys from "../../../engine/Chords/Keys";
  import { fetchMlTrack } from "../../../ml/lofiApi";

  const STORAGE_KEY = "SongModeConfig";
  const DEFAULT_ML_SERVER = "http://localhost:5050";
  const LEGACY_ML_SERVER = "http://127.0.0.1:5000";
  const HOSTED_ML_SERVER = "https://lofiserver.jacobzhang.de";

  function normalizedServerCandidates(value: string) {
    const raw = value.trim() || DEFAULT_ML_SERVER;
    const migrated = raw === LEGACY_ML_SERVER ? DEFAULT_ML_SERVER : raw;

    const candidates: string[] = [migrated];

    if (migrated.includes("localhost")) {
      candidates.push(migrated.replace("localhost", "127.0.0.1"));
    } else if (migrated.includes("127.0.0.1")) {
      candidates.push(migrated.replace("127.0.0.1", "localhost"));
    }

    // Always include local loopback candidates as recovery paths.
    candidates.push("http://localhost:5050");
    candidates.push("http://127.0.0.1:5050");

    // Always include hosted as final fallback.
    candidates.push(HOSTED_ML_SERVER);

    return [...new Set(candidates)];
  }

  const keyOptions = [
    "AUTO",
    "C",
    "C#",
    "D",
    "D#",
    "E",
    "F",
    "F#",
    "G",
    "G#",
    "A",
    "A#",
    "B",
  ];

  const moodOptions = ["chill", "balanced", "energetic"];
  const samplePrompts = [
    "Late-night study session with warm Rhodes chords and distant rain.",
    "Lo-fi loop for focus, soft drums, dusty piano, and mellow bass.",
  ];
  const studyPrompts = [
    "Deep focus study session, gentle vinyl crackle, soft piano, no harsh highs, steady rhythm.",
    "Library at midnight, warm jazz chords, subtle bass pulse, calm and repetitive for concentration.",
    "Rainy cafe study beat, mellow keys, low-pass drums, cozy and minimal.",
    "Exam prep ambient lo-fi, sparse melody, soothing chords, stable groove for long sessions.",
    "Coding study soundtrack, warm tape texture, smooth bass, restrained percussion.",
  ];
  const presetOrder = ["study", "rainy", "night_drive", "warm_piano", "dusty_boom_bap"] as const;
  const LATENT_DIM = 100;
  const sampleLatent = Array.from({ length: LATENT_DIM }, (_, i) =>
    Number((Math.sin(i * 1.37) * 0.35).toFixed(5)),
  );

  let enabled = false;
  let seed = "lofi-seed";
  let key = "AUTO";
  let mood = "balanced";
  let density = 0.33;
  let bpmOverride: number | null = null;
  let progression: number[] = [];
  let melodies: number[][] = [];
  let mlTitle = "";
  let mlSource: "predict" | "decode" | "generate" | "" = "predict";
  let mlServerUrl = DEFAULT_ML_SERVER;
  let mlInput = "late-night study session in a cozy apartment";
  let isApplyingMl = false;
  let mlError = "";
  let selectedPreset = "study";
  let loopEnabled = false;
  let loopMinutes = 4;
  let autoCycleStyles = true;
  let styleShiftEvery = 3;
  let loopCycles = 0;
  let loopTimer: number | null = null;
  let loopInFlight = false;

  function emitConfig(regenerate = false) {
    const config = {
      enabled,
      seed: seed.trim() || "lofi-seed",
      key,
      mood,
      density,
      bpmOverride,
      progression,
      melodies,
      mlTitle,
      mlSource,
      mlServerUrl,
      mlInput,
      selectedPreset,
      loopEnabled,
      loopMinutes,
      autoCycleStyles,
      styleShiftEvery,
      regenerate,
    };

    localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
    window.dispatchEvent(new CustomEvent("song-mode-changed", { detail: config }));
  }

  function clamp(value: number, min: number, max: number) {
    return Math.max(min, Math.min(max, value));
  }

  function normalizeKey(keyNumber?: number) {
    if (!Number.isFinite(keyNumber)) {
      return "AUTO";
    }

    const keyIndex = ((Math.round(Number(keyNumber)) - 1) % Keys.length + Keys.length) % Keys.length;
    return Keys[keyIndex] || "AUTO";
  }

  function deriveMood(energy?: number, valence?: number) {
    const normalizedEnergy = Number(energy);
    const normalizedValence = Number(valence);

    if (Number.isFinite(normalizedEnergy) && normalizedEnergy >= 0.68) {
      return "energetic";
    }

    if (Number.isFinite(normalizedValence) && normalizedValence >= 0.56) {
      return "balanced";
    }

    return "chill";
  }

  function deriveDensity(energy?: number, valence?: number) {
    const normalizedEnergy = Number.isFinite(energy) ? Number(energy) : 0.35;
    const normalizedValence = Number.isFinite(valence) ? Number(valence) : 0.35;
    return clamp(0.18 + normalizedEnergy * 0.45 + normalizedValence * 0.2, 0.1, 0.95);
  }

  function normalizeProgression(chords?: number[]) {
    return (Array.isArray(chords) ? chords : [])
      .map((value) => Number(value))
      .filter((value) => Number.isInteger(value) && value >= 1 && value <= 7)
      .slice(0, 16);
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

  function normalizePresetId(value: unknown) {
    const candidate = String(value || "study");
    return presetOrder.includes(candidate as (typeof presetOrder)[number])
      ? candidate
      : "study";
  }

  function getPresetProfile(presetId: string) {
    const profiles = {
      study: {
        source: "predict" as const,
        mood: "chill" as SongMood,
        density: 0.25,
        prompt: studyPrompts[0],
      },
      rainy: {
        source: "predict" as const,
        mood: "balanced" as SongMood,
        density: 0.3,
        prompt: "Rainy evening lo-fi, soft keys, distant thunder, calm repeating groove.",
      },
      night_drive: {
        source: "predict" as const,
        mood: "chill" as SongMood,
        density: 0.2,
        prompt: "Night drive lo-fi, muted bass, soft pads, neon reflections, slow pulse.",
      },
      warm_piano: {
        source: "predict" as const,
        mood: "balanced" as SongMood,
        density: 0.28,
        prompt: "Warm piano loop, cozy chords, soft swing, inviting and intimate atmosphere.",
      },
      dusty_boom_bap: {
        source: "predict" as const,
        mood: "energetic" as SongMood,
        density: 0.36,
        prompt: "Dusty boom bap lo-fi, mellow chops, crisp drums, vinyl texture, head-nod groove.",
      },
    };

    return profiles[(presetId as keyof typeof profiles)] || profiles.study;
  }

  function nextPreset(current: string) {
    const index = presetOrder.indexOf(normalizePresetId(current) as (typeof presetOrder)[number]);
    return presetOrder[(index + 1) % presetOrder.length];
  }

  function clearLoopTimer() {
    if (loopTimer !== null) {
      clearInterval(loopTimer);
      loopTimer = null;
    }
  }

  function syncLoopTimer() {
    clearLoopTimer();
    if (!enabled || !loopEnabled) {
      return;
    }

    const intervalMs = Math.max(1, loopMinutes) * 60000;
    loopTimer = window.setInterval(() => {
      void runLoopRefresh();
    }, intervalMs);
  }

  async function applyPresetById(presetId: string) {
    const profile = getPresetProfile(presetId);
    selectedPreset = normalizePresetId(presetId);
    mlSource = profile.source;
    mlInput = profile.prompt;
    mood = profile.mood;
    density = profile.density;
    await applyMlPreset();
  }

  async function runLoopRefresh() {
    if (loopInFlight || isApplyingMl || !enabled || !loopEnabled) {
      return;
    }

    loopInFlight = true;
    try {
      loopCycles += 1;
      if (autoCycleStyles && styleShiftEvery > 0 && loopCycles % styleShiftEvery === 0) {
        selectedPreset = nextPreset(selectedPreset);
      }

      await applyPresetById(selectedPreset);
    } finally {
      loopInFlight = false;
      syncLoopTimer();
    }
  }

  function useSamplePrompt() {
    mlSource = "predict";
    mlInput = samplePrompts[Math.floor(Math.random() * samplePrompts.length)];
    emitConfig(false);
  }

  function useSampleLatent() {
    mlSource = "decode";
    mlInput = JSON.stringify(sampleLatent, null, 2);
    emitConfig(false);
  }

  async function applyStudyPreset() {
    const pick = studyPrompts[Math.floor(Math.random() * studyPrompts.length)];
    mlSource = "predict";
    mlInput = pick;
    mlError = "";
    mood = "chill";
    density = 0.26;
    emitConfig(false);
    await applyMlPreset();
    if (!mlError) {
      return;
    }

    // If text predict is unavailable, fallback to latent generation so users still get a usable preset.
    mlSource = "generate";
    mlError = "";
    emitConfig(false);
    await applyMlPreset();
  }

  $: mlSummary = [
    mlTitle
      ? `Loaded ${mlTitle}`
      : progression.length || melodies.length || bpmOverride
        ? "ML preset loaded"
        : "No ML preset loaded yet",
    `${selectedPreset.replace(/_/g, " ")} preset`,
    loopEnabled ? `Loop ${loopMinutes}m on` : `Loop off`,
    bpmOverride ? `${Math.round(bpmOverride)} BPM` : "Procedural BPM",
    progression.length ? `${progression.length} chords` : "No ML chords",
  ].join(" · ");

  async function applyMlPreset() {
    mlError = "";

    const serverCandidates = normalizedServerCandidates(mlServerUrl);
    let serverUrl = serverCandidates[0];
    const endpoint = mlSource === "decode" ? "decode" : mlSource === "generate" ? "generate" : "predict";

    let input: string | number[] | undefined;
    try {
      if (endpoint === "generate") {
        input = undefined;
      } else if (endpoint === "decode") {
        const parsed = JSON.parse(mlInput);
        if (!Array.isArray(parsed) || !parsed.every((value) => Number.isFinite(Number(value)))) {
          throw new Error("Latent input must be a JSON array of numbers.");
        }
        if (parsed.length !== LATENT_DIM) {
          throw new Error(`Latent vector must contain exactly ${LATENT_DIM} numbers.`);
        }
        input = parsed.map((value) => Number(value));
      } else {
        const text = mlInput.trim();
        if (!text) {
          throw new Error("Enter lyrics or a seed prompt first.");
        }
        input = text;
      }
    } catch (error) {
      mlError = error instanceof Error ? error.message : "Invalid ML input.";
      return;
    }

    isApplyingMl = true;
    try {
      let output: Awaited<ReturnType<typeof fetchMlTrack>> | null = null;
      let lastError: unknown = null;
      for (const candidate of serverCandidates) {
        try {
          output = await fetchMlTrack({ serverUrl: candidate, endpoint, input });
          serverUrl = candidate;
          break;
        } catch (error) {
          lastError = error;
        }
      }

      if (!output) {
        throw lastError instanceof Error ? lastError : new Error("Failed to load ML preset.");
      }

      const nextProgression = normalizeProgression(output.chords);
      const nextMelodies = normalizeMelodies(output.melodies);
      const normalizedTitle = typeof output.title === "string" ? output.title.trim() : "";
      const parsedBpm = Number(output.bpm);
      bpmOverride = Number.isFinite(parsedBpm) ? parsedBpm : null;
      progression = nextProgression;
      melodies = nextMelodies;
      mlTitle = normalizedTitle;
      mlSource = endpoint;
      mlServerUrl = serverUrl;
      key = normalizeKey(output.key);
      mood = deriveMood(output.energy, output.valence);
      density = deriveDensity(output.energy, output.valence);
      seed = (normalizedTitle || mlInput || "ml-track").trim() || "ml-track";
      enabled = true;
      emitConfig(true);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to load ML preset.";
      if (message.toLowerCase().includes("load failed") || message.toLowerCase().includes("failed to fetch")) {
        const attempted = serverCandidates.join(" -> ");
        mlError = `Cannot reach ML server. Tried: ${attempted}. Start local server with: npm run ml:server:dev`;
      } else {
        mlError = message;
      }
    } finally {
      isApplyingMl = false;
    }
  }

  function resetMlPreset() {
    bpmOverride = null;
    progression = [];
    melodies = [];
    mlTitle = "";
    mlSource = "predict";
    mlError = "";
    loopEnabled = false;
    loopCycles = 0;
    clearLoopTimer();
    emitConfig(true);
  }

  onMount(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      try {
        const parsed = JSON.parse(saved);
        enabled = !!parsed.enabled;
        seed = parsed.seed || "lofi-seed";
        key = parsed.key || "AUTO";
        mood = parsed.mood || "balanced";
        density = Number.isFinite(parsed.density) ? parsed.density : 0.33;
        bpmOverride = Number.isFinite(Number(parsed.bpmOverride)) ? Number(parsed.bpmOverride) : null;
        progression = Array.isArray(parsed.progression) ? parsed.progression : [];
        melodies = Array.isArray(parsed.melodies) ? parsed.melodies : [];
        mlTitle = parsed.mlTitle || "";
        mlSource =
          parsed.mlSource === "decode"
            ? "decode"
            : parsed.mlSource === "generate"
              ? "generate"
              : parsed.mlSource === "predict"
                ? "predict"
                : "predict";
        const restoredUrl = parsed.mlServerUrl || DEFAULT_ML_SERVER;
        mlServerUrl = normalizedServerCandidates(restoredUrl)[0];
        mlInput = parsed.mlInput || mlInput;
        selectedPreset = normalizePresetId(parsed.selectedPreset);
        loopEnabled = !!parsed.loopEnabled;
        loopMinutes = clamp(Number(parsed.loopMinutes ?? 4), 1, 30);
        autoCycleStyles = parsed.autoCycleStyles === undefined ? true : !!parsed.autoCycleStyles;
        styleShiftEvery = clamp(Number(parsed.styleShiftEvery ?? 3), 1, 24);
      } catch {
        // Ignore malformed local storage payload.
      }
    }

    emitConfig(false);
    syncLoopTimer();

    return () => {
      clearLoopTimer();
    };
  });

  onDestroy(() => {
    clearLoopTimer();
  });
</script>

<div class="song-mode-container">
  <h4>Song Mode</h4>
  <label class="song-toggle">
    <input type="checkbox" bind:checked={enabled} on:change={() => emitConfig(true)} />
    <span>Enable Custom Song Mode</span>
  </label>

  <div class="field-row">
    <label for="song-seed">Seed</label>
    <input
      id="song-seed"
      type="text"
      bind:value={seed}
      on:change={() => emitConfig(true)}
      placeholder="lofi-seed"
    />
  </div>

  <div class="field-row">
    <label for="song-key">Key</label>
    <select id="song-key" bind:value={key} on:change={() => emitConfig(true)}>
      {#each keyOptions as item}
        <option value={item}>{item}</option>
      {/each}
    </select>
  </div>

  <div class="field-row">
    <label for="song-mood">Mood</label>
    <select id="song-mood" bind:value={mood} on:change={() => emitConfig(true)}>
      {#each moodOptions as item}
        <option value={item}>{item}</option>
      {/each}
    </select>
  </div>

  <div class="field-row">
    <label for="song-density">Density: {Math.round(density * 100)}%</label>
    <input
      id="song-density"
      type="range"
      min="0.1"
      max="0.95"
      step="0.01"
      bind:value={density}
      on:change={() => emitConfig(true)}
    />
  </div>

  <div class="ml-panel">
    <div class="ml-header">
      <h5>ML Preset</h5>
      <p class="ml-meta">{mlSummary}</p>
    </div>

    <div class="preset-grid">
      {#each presetOrder as presetId}
        <button
          type="button"
          class:preset-active={selectedPreset === presetId}
          class="preset-chip"
          on:click={() => applyPresetById(presetId)}
        >
          {presetId.split("_").map((part) => part[0].toUpperCase() + part.slice(1)).join(" ")}
        </button>
      {/each}
    </div>

    <div class="field-row">
      <label for="ml-server-url">Server URL</label>
      <input
        id="ml-server-url"
        type="text"
        bind:value={mlServerUrl}
        placeholder={DEFAULT_ML_SERVER}
        on:change={() => emitConfig(false)}
      />
    </div>

    <div class="field-row">
      <label for="ml-source">Source</label>
      <select id="ml-source" bind:value={mlSource} on:change={() => emitConfig(false)}>
        <option value="generate">Generate random latent</option>
        <option value="predict">Predict from text</option>
        <option value="decode">Decode latent vector</option>
      </select>
    </div>

    {#if mlSource !== "generate"}
      <div class="field-row">
        <label for="ml-input">Input</label>
        {#if mlSource === "decode"}
          <textarea
            id="ml-input"
            rows="4"
            bind:value={mlInput}
            placeholder="[0.12, -0.44, 0.07, ...]"
            on:change={() => emitConfig(false)}
          />
        {:else}
          <textarea
            id="ml-input"
            rows="4"
            bind:value={mlInput}
            placeholder="A rainy night study session with warm chords"
            on:change={() => emitConfig(false)}
          />
        {/if}
      </div>
    {/if}

    <div class="ml-preset-row">
      <button class="mini-btn" type="button" on:click={useSamplePrompt}>Use sample prompt</button>
      <button class="mini-btn" type="button" on:click={useSampleLatent}>Use sample latent</button>
      <button class="mini-btn study-btn" type="button" on:click={applyStudyPreset} disabled={isApplyingMl}
        >Generate Study Sound</button
      >
    </div>

    <div class="loop-panel">
      <label class="song-toggle compact-toggle">
        <input type="checkbox" bind:checked={loopEnabled} on:change={() => { emitConfig(false); syncLoopTimer(); }} />
        <span>Auto-generate a new variation every {loopMinutes} minute{loopMinutes === 1 ? "" : "s"}</span>
      </label>

      <div class="field-row compact-row">
        <label for="loop-minutes">Refresh interval: {loopMinutes} min</label>
        <input
          id="loop-minutes"
          type="range"
          min="3"
          max="8"
          step="1"
          bind:value={loopMinutes}
          on:change={() => { emitConfig(false); syncLoopTimer(); }}
        />
      </div>

      <div class="field-row compact-row">
        <label for="style-shift-every">Shift style every {styleShiftEvery} cycle{styleShiftEvery === 1 ? "" : "s"}</label>
        <input
          id="style-shift-every"
          type="range"
          min="1"
          max="8"
          step="1"
          bind:value={styleShiftEvery}
          on:change={() => emitConfig(false)}
        />
      </div>

      <label class="song-toggle compact-toggle">
        <input type="checkbox" bind:checked={autoCycleStyles} on:change={() => emitConfig(false)} />
        <span>Rotate between study, rainy, night drive, warm piano, and dusty boom bap</span>
      </label>
    </div>

    <button class="apply ml-apply" on:click={applyMlPreset} disabled={isApplyingMl}>
      {#if isApplyingMl}
        Loading ML preset...
      {:else}
        Apply ML Preset
      {/if}
    </button>

    <button class="apply ml-reset" on:click={resetMlPreset}>Clear ML Preset</button>

    {#if mlError}
      <p class="ml-error">{mlError}</p>
    {/if}
  </div>

  <button class="apply" on:click={() => emitConfig(true)}>Apply + Regenerate</button>
</div>

<style>
  .song-mode-container {
    margin-top: 20px;
    margin-bottom: 20px;
    padding: 0 10px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  h4 {
    margin: 0;
  }

  .song-toggle {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.9em;
  }

  .field-row {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .field-row label {
    font-size: 0.85em;
    opacity: 0.85;
  }

  .field-row input,
  .field-row select {
    width: 100%;
    border-radius: 8px;
    border: 1px solid rgba(255, 255, 255, 0.2);
    background: rgba(255, 255, 255, 0.08);
    color: white;
    padding: 8px;
    box-sizing: border-box;
  }

  .field-row textarea {
    width: 100%;
    border-radius: 8px;
    border: 1px solid rgba(255, 255, 255, 0.2);
    background: rgba(255, 255, 255, 0.08);
    color: white;
    padding: 8px;
    box-sizing: border-box;
    resize: vertical;
  }

  .ml-panel {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 12px;
    border-radius: 16px;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid rgba(255, 255, 255, 0.08);
  }

  .ml-header {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .ml-panel h5 {
    margin: 0;
    font-size: 0.9em;
    opacity: 0.9;
  }

  .ml-preset-row {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  .preset-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
  }

  .preset-chip {
    width: 100%;
    border-radius: 999px;
    padding: 7px 10px;
    background: rgba(255, 255, 255, 0.08);
    color: rgba(255, 255, 255, 0.78);
    border: 1px solid rgba(255, 255, 255, 0.1);
    cursor: pointer;
    font-size: 0.8em;
  }

  .preset-chip.preset-active {
    background: white;
    color: black;
    border-color: white;
    font-weight: 700;
  }

  .loop-panel {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 10px;
    border-radius: 14px;
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.06);
  }

  .compact-toggle {
    font-size: 0.8em;
  }

  .compact-row label {
    font-size: 0.8em;
  }

  .mini-btn {
    background: rgba(255, 255, 255, 0.09);
    color: white;
    border-radius: 999px;
    border: 1px solid rgba(255, 255, 255, 0.12);
    padding: 7px 10px;
    cursor: pointer;
    font-size: 0.8em;
  }

  .mini-btn:hover {
    background: rgba(255, 255, 255, 0.14);
  }

  .study-btn {
    background: rgba(203, 255, 208, 0.15);
    border-color: rgba(203, 255, 208, 0.35);
  }

  .ml-apply {
    width: fit-content;
  }

  .ml-reset {
    width: fit-content;
    background: rgba(255, 255, 255, 0.1);
    color: white;
  }

  .ml-meta {
    margin: 0;
    font-size: 0.8em;
    opacity: 0.8;
  }

  .ml-error {
    margin: 0;
    font-size: 0.8em;
    color: #ffb5b5;
  }

  .apply {
    background: white;
    color: black;
    border-radius: 20px;
    border: 0;
    padding: 8px 12px;
    cursor: pointer;
    font-weight: 600;
  }
</style>
