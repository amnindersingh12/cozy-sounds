<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  interface HistoryEntry {
    id: string;
    preset: string;
    timestamp: number;
    title: string;
    mood?: string;
  }

  const STORAGE_KEY = "song-history";
  const MAX_HISTORY = 20;
  const VISIBLE_ITEMS = 8;

  let history: HistoryEntry[] = [];
  let nowTick = Date.now();
  let activeIndex = 0;
  let clockInterval = 0;
  let rotateInterval = 0;

  $: visibleHistory = history.slice(0, VISIBLE_ITEMS);

  $: if (visibleHistory.length === 0) {
    activeIndex = 0;
  } else if (activeIndex >= visibleHistory.length) {
    activeIndex = 0;
  }

  function loadHistory() {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      try {
        history = JSON.parse(saved);
      } catch {
        history = [];
      }
    }
  }

  function saveHistory() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(history));
  }

  function addEntry(preset: string, title: string = "", mood: string = "") {
    const entry: HistoryEntry = {
      id: `${Date.now()}-${Math.random()}`,
      preset,
      timestamp: Date.now(),
      title,
      mood,
    };

    history = [entry, ...history].slice(0, MAX_HISTORY);
    saveHistory();
  }

  function formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = String(date.getHours()).padStart(2, "0");
    const minutes = String(date.getMinutes()).padStart(2, "0");
    const seconds = String(date.getSeconds()).padStart(2, "0");
    return `${hours}:${minutes}:${seconds}`;
  }

  function formatDuration(timestamp: number): string {
    const diff = nowTick - timestamp;
    const seconds = Math.floor(diff / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);

    if (seconds < 60) return `${seconds}s ago`;
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    return `${Math.floor(hours / 24)}d ago`;
  }

  function handlePresetChange(event: Event) {
    const customEvent = event as CustomEvent<{ preset: string; title?: string; mood?: string }>;
    const { preset, title = "", mood = "" } = customEvent.detail || {};
    if (preset) {
      addEntry(preset, title, mood);
    }
  }

  function handleSongModeChange(event: Event) {
    const customEvent = event as CustomEvent<{ selectedPreset?: string; mlTitle?: string; mood?: string }>;
    const { selectedPreset = "", mlTitle = "", mood = "" } = customEvent.detail || {};
    if (selectedPreset) {
      addEntry(selectedPreset, mlTitle, mood);
    }
  }

  function clearHistory() {
    if (confirm("Clear all song history?")) {
      history = [];
      saveHistory();
    }
  }

  function tickActiveIndex() {
    if (visibleHistory.length <= 1) {
      activeIndex = 0;
      return;
    }

    activeIndex = (activeIndex + 1) % visibleHistory.length;
  }

  onMount(() => {
    loadHistory();
    window.addEventListener("preset-changed", handlePresetChange);
    window.addEventListener("song-mode-changed", handleSongModeChange);

    clockInterval = window.setInterval(() => {
      nowTick = Date.now();
    }, 1000);

    rotateInterval = window.setInterval(() => {
      tickActiveIndex();
    }, 2600);

    return () => {
      window.removeEventListener("preset-changed", handlePresetChange);
      window.removeEventListener("song-mode-changed", handleSongModeChange);
      window.clearInterval(clockInterval);
      window.clearInterval(rotateInterval);
    };
  });


</script>

<aside class="history-container" aria-live="polite" aria-label="Track history">
  <div class="history-content">
    <div class="history-header">
      <h3>Track History</h3>
      <div class="header-actions">
        <span class="live-pill">LIVE</span>
        <button class="clear-btn" on:click={clearHistory} title="Clear history" aria-label="Clear history">Clear</button>
      </div>
    </div>

    {#if visibleHistory.length === 0}
      <div class="empty-state">No tracks yet. Start switching presets to build history.</div>
    {:else}
      <div class="history-list">
        {#each visibleHistory as entry, index (entry.id)}
          <article class="history-item" class:active={index === activeIndex} style={`--item-index:${index};`}>
            <div class="item-header">
              <span class="preset-name">{entry.preset.replace(/_/g, " ")}</span>
              <span class="time-ago">{formatDuration(entry.timestamp)}</span>
            </div>
            {#if entry.title}
              <div class="item-title">{entry.title}</div>
            {/if}
            {#if entry.mood}
              <div class="item-mood">Mood: {entry.mood}</div>
            {/if}
            <div class="item-time">{formatTime(entry.timestamp)}</div>
          </article>
        {/each}
      </div>
    {/if}
  </div>
</div>

<style>
  .history-container {
    position: fixed;
    top: 84px;
    right: 20px;
    z-index: 30;
    font-family: inherit;
    width: min(320px, calc(100vw - 40px));
  }

  .history-content {
    position: relative;
    background: linear-gradient(160deg, rgba(14, 18, 28, 0.86), rgba(22, 15, 20, 0.78));
    border: 1px solid rgba(255, 255, 255, 0.18);
    border-radius: 18px;
    padding: 14px;
    max-height: min(66vh, 520px);
    overflow-y: auto;
    backdrop-filter: blur(14px);
    box-shadow: 0 18px 48px rgba(0, 0, 0, 0.4);
    animation: panelFloat 10s ease-in-out infinite;
  }

  .history-content::before {
    content: "";
    position: absolute;
    inset: -24%;
    border-radius: 40%;
    pointer-events: none;
    background: conic-gradient(from 0deg, rgba(255, 198, 125, 0.16), rgba(112, 166, 255, 0.16), rgba(255, 198, 125, 0.16));
    animation: haloRotate 24s linear infinite;
    filter: blur(28px);
    opacity: 0.55;
    z-index: -1;
  }

  .history-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 12px;
  }

  .history-header h3 {
    margin: 0;
    font-size: 13px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: white;
  }

  .header-actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .live-pill {
    font-size: 10px;
    letter-spacing: 0.08em;
    font-weight: 700;
    padding: 4px 8px;
    border-radius: 999px;
    color: rgba(255, 255, 255, 0.92);
    background: rgba(217, 79, 96, 0.7);
    box-shadow: 0 0 14px rgba(217, 79, 96, 0.45);
    animation: livePulse 1.8s ease-in-out infinite;
  }

  .clear-btn {
    background: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 999px;
    color: rgba(255, 255, 255, 0.82);
    cursor: pointer;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    padding: 5px 10px;
    transition: all 0.2s ease;
  }

  .clear-btn:hover {
    background: rgba(255, 255, 255, 0.2);
    color: white;
  }

  .empty-state {
    text-align: center;
    color: rgba(255, 255, 255, 0.7);
    padding: 22px 12px;
    font-size: 12px;
    line-height: 1.4;
  }

  .history-list {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .history-item {
    background: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 12px;
    padding: 10px;
    font-size: 12px;
    color: rgba(255, 255, 255, 0.92);
    transform-origin: center;
    animation: itemDrift 7.2s ease-in-out infinite;
    animation-delay: calc(var(--item-index) * 220ms);
    transition: transform 0.35s ease, border-color 0.35s ease, background-color 0.35s ease;
  }

  .history-item.active {
    border-color: rgba(255, 223, 174, 0.7);
    background: linear-gradient(135deg, rgba(255, 193, 127, 0.2), rgba(112, 166, 255, 0.15));
    transform: translateX(-6px) rotate(-0.4deg) scale(1.02);
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.28);
  }

  .item-header {
    display: flex;
    justify-content: space-between;
    margin-bottom: 5px;
    gap: 10px;
  }

  .preset-name {
    font-weight: 600;
    color: #f8d6ac;
    text-transform: capitalize;
  }

  .time-ago {
    color: rgba(255, 255, 255, 0.62);
    font-size: 11px;
    white-space: nowrap;
  }

  .item-title {
    color: rgba(255, 255, 255, 0.78);
    margin: 4px 0;
    word-break: break-word;
  }

  .item-mood {
    color: rgba(173, 204, 255, 0.84);
    font-size: 11px;
    margin-top: 3px;
    text-transform: capitalize;
  }

  .item-time {
    color: rgba(255, 255, 255, 0.52);
    font-size: 10px;
    margin-top: 3px;
  }

  .history-content::-webkit-scrollbar {
    width: 6px;
  }

  .history-content::-webkit-scrollbar-track {
    background: rgba(255, 255, 255, 0.05);
    border-radius: 10px;
  }

  .history-content::-webkit-scrollbar-thumb {
    background: rgba(255, 255, 255, 0.2);
    border-radius: 10px;
  }

  .history-content::-webkit-scrollbar-thumb:hover {
    background: rgba(255, 255, 255, 0.3);
  }

  @keyframes panelFloat {
    0%,
    100% {
      transform: translateY(0);
    }

    50% {
      transform: translateY(-5px);
    }
  }

  @keyframes haloRotate {
    0% {
      transform: rotate(0deg);
    }

    100% {
      transform: rotate(360deg);
    }
  }

  @keyframes livePulse {
    0%,
    100% {
      opacity: 0.72;
      transform: scale(1);
    }

    50% {
      opacity: 1;
      transform: scale(1.06);
    }
  }

  @keyframes itemDrift {
    0%,
    100% {
      transform: translateX(0) rotate(0deg);
    }

    50% {
      transform: translateX(-3px) rotate(-0.2deg);
    }
  }

  @media screen and (max-width: 900px) {
    .history-container {
      top: auto;
      right: 12px;
      bottom: 16px;
      width: min(92vw, 360px);
    }

    .history-content {
      max-height: min(38vh, 320px);
    }
  }
</style>
