<script lang="ts">
  import { onMount } from "svelte";
  import localDB from "../../../localDB";

  const CUSTOM_TRACKS_KEY = "custom-tracks";
  const CUSTOM_TRACK_FX_KEY = "CustomTrackFx";

  let customTrackCount = 0;
  let isImporting = false;
  let lofiAmount = 0.5;
  let slowdown = 0.92;
  let reverseChance = 0.15;

  function emitFxSettings() {
    const payload = {
      lofiAmount,
      slowdown,
      reverseChance,
    };
    localStorage.setItem(CUSTOM_TRACK_FX_KEY, JSON.stringify(payload));
    window.dispatchEvent(new CustomEvent("lofi-custom-track-fx-changed", { detail: payload }));
  }

  async function refreshCount() {
    try {
      const raw = await localDB.getItem(CUSTOM_TRACKS_KEY);
      if (!raw) {
        customTrackCount = 0;
        return;
      }
      const parsed = JSON.parse(raw);
      customTrackCount = Array.isArray(parsed) ? parsed.length : 0;
    } catch {
      customTrackCount = 0;
    }
  }

  function fileToDataUrl(file: File): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
  }

  async function handleImport(event: Event) {
    const input = event.target as HTMLInputElement;
    const files = Array.from(input.files || []).filter((file) => file.type.startsWith("audio/"));
    if (!files.length) {
      return;
    }

    isImporting = true;
    try {
      for (const file of files) {
        const dataUrl = await fileToDataUrl(file);
        window.dispatchEvent(
          new CustomEvent("lofi-add-custom-track", {
            detail: { name: file.name, dataUrl },
          }),
        );
      }
      await refreshCount();
    } finally {
      isImporting = false;
      input.value = "";
    }
  }

  onMount(() => {
    const savedFx = localStorage.getItem(CUSTOM_TRACK_FX_KEY);
    if (savedFx) {
      try {
        const parsed = JSON.parse(savedFx);
        lofiAmount = Number.isFinite(parsed.lofiAmount) ? parsed.lofiAmount : 0.5;
        slowdown = Number.isFinite(parsed.slowdown) ? parsed.slowdown : 0.92;
        reverseChance = Number.isFinite(parsed.reverseChance) ? parsed.reverseChance : 0.15;
      } catch {
        // Ignore malformed settings and use defaults.
      }
    }

    emitFxSettings();
    refreshCount();
    const handleSynced = () => {
      refreshCount();
    };
    window.addEventListener("lofi-custom-tracks-synced", handleSynced);
    return () => {
      window.removeEventListener("lofi-custom-tracks-synced", handleSynced);
    };
  });
</script>

<div class="custom-tracks-container">
  <h4>Custom Tracks</h4>
  <p class="meta">Imported tracks: {customTrackCount}</p>
  <label class="import-btn" for="custom-track-input">
    {#if isImporting}
      Importing...
    {:else}
      Add Audio Files
    {/if}
  </label>
  <p class="meta">Supports mp3, wav, m4a, ogg, flac</p>
  <input
    id="custom-track-input"
    type="file"
    accept="audio/*,.flac,audio/flac,audio/x-flac"
    multiple
    on:change={handleImport}
  />

  <div class="fx-controls">
    <div class="control-row">
      <label for="lofi-amount">LoFi Amount: {Math.round(lofiAmount * 100)}%</label>
      <input
        id="lofi-amount"
        type="range"
        min="0"
        max="1"
        step="0.01"
        bind:value={lofiAmount}
        on:input={emitFxSettings}
      />
    </div>

    <div class="control-row">
      <label for="slowdown">Slowdown: {slowdown.toFixed(2)}x</label>
      <input
        id="slowdown"
        type="range"
        min="0.75"
        max="1"
        step="0.01"
        bind:value={slowdown}
        on:input={emitFxSettings}
      />
    </div>

    <div class="control-row">
      <label for="reverse-chance">Reverse Chance: {Math.round(reverseChance * 100)}%</label>
      <input
        id="reverse-chance"
        type="range"
        min="0"
        max="0.3"
        step="0.01"
        bind:value={reverseChance}
        on:input={emitFxSettings}
      />
    </div>
  </div>
</div>

<style>
  .custom-tracks-container {
    margin-top: 20px;
    padding: 0 10px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  h4 {
    margin: 0;
  }

  .meta {
    margin: 0;
    font-size: 12px;
    opacity: 0.75;
  }

  .import-btn {
    display: inline-flex;
    width: fit-content;
    padding: 8px 12px;
    border-radius: 20px;
    background: rgba(255, 255, 255, 0.14);
    border: 1px solid rgba(255, 255, 255, 0.2);
    cursor: pointer;
    font-size: 13px;
    user-select: none;
  }

  #custom-track-input {
    display: none;
  }

  .fx-controls {
    margin-top: 8px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .control-row {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .control-row label {
    font-size: 12px;
    opacity: 0.85;
  }

  .control-row input[type="range"] {
    width: 100%;
  }
</style>