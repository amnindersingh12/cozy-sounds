<script lang="ts">
  import { IconArrowsShuffle } from "@tabler/icons-svelte";
  import TrackListItem from "./TrackListItem.svelte";
  import { onMount } from "svelte";
  import * as Tone from "tone";
  import localDB from "../../localDB";

  const CUSTOM_TRACKS_KEY = "custom-tracks";
  const CUSTOM_TRACK_FX_KEY = "CustomTrackFx";
  const TRACK_VOLUME_KEY = "TrackVolumes";

  const baseTracks = [
    {
      id: 1,
      track: "Wind-Mark_DiAngelo-1940285615.mp3",
      isPlaying: false,
      imageId: 1,
      quoteId: 1,
    },
    {
      id: 2,
      track: "small-waves-onto-the-sand-143040.mp3",
      isPlaying: false,
      imageId: 2,
      quoteId: 2,
    },
    {
      id: 3,
      track: "night-ambience-17064.mp3",
      isPlaying: false,
      imageId: 3,
      quoteId: 3,
    },
    {
      id: 4,
      track: "urban-seagulls-30068.mp3",
      isPlaying: false,
      imageId: 4,
      quoteId: 4,
    },
    {
      id: 5,
      track: "office-ambience-6322.mp3",
      isPlaying: false,
      imageId: 5,
      quoteId: 5,
    },
    {
      id: 6,
      track: "city-ambience-9272.mp3",
      isPlaying: false,
      imageId: 6,
      quoteId: 6,
    },
    {
      id: 7,
      track: "old-server-turning-on-and-off-24540.mp3",
      isPlaying: false,
      imageId: 7,
      quoteId: 7,
    },
    {
      id: 8,
      track: "train-to-munich-germany.mp3",
      isPlaying: false,
      imageId: 8,
      quoteId: 8,
    },
    {
      id: 9,
      track: "underwater-white-noise-46423.mp3",
      isPlaying: false,
      imageId: 9,
      quoteId: 9,
    },
    {
      id: 10,
      track: "wind-drift-loop.mp3",
      title: "Wind Drift",
      isPlaying: false,
      imageId: 1,
      quoteId: 1,
    },
    {
      id: 11,
      track: "midnight-drone-loop.mp3",
      title: "Midnight Drone",
      isPlaying: false,
      imageId: 2,
      quoteId: 2,
    },
    {
      id: 12,
      track: "cassette-hiss-loop.mp3",
      title: "Cassette Hiss",
      isPlaying: false,
      imageId: 3,
      quoteId: 3,
    },
    {
      id: 13,
      track: "distant-rain-loop.mp3",
      title: "Distant Rain",
      isPlaying: false,
      imageId: 4,
      quoteId: 4,
    },
  ];

  let tracks = [...baseTracks];

  let activeAudios = [];
  let isMobileHidden = false; // Used to hide track list on mobile due to tight space
  let trackVolumes = {};
  let isUiHidden = localStorage.getItem("UIControlsHidden") === "true";

  const customTrackFilter = new Tone.Filter(2200, "lowpass");
  const customTrackReverb = new Tone.Reverb({
    decay: 2.4,
    preDelay: 0.015,
    wet: 0.18,
  });
  const customTrackVolume = new Tone.Volume(-3);

  customTrackFilter.chain(customTrackReverb, customTrackVolume, Tone.Master);

  let customTrackFx = {
    lofiAmount: 0.5,
    slowdown: 0.92,
    reverseChance: 0.15,
  };

  let lofiAmount = 0.5;
  let slowdown = 0.92;
  let reverseChance = 0.15;

  function clamp(value: number, min: number, max: number) {
    return Math.max(min, Math.min(max, value));
  }

  function applyCustomTrackFx() {
    const amount = clamp(customTrackFx.lofiAmount, 0, 1);
    customTrackFilter.frequency.value = 4500 - amount * 3200;
    customTrackReverb.wet.value = 0.04 + amount * 0.3;
    customTrackVolume.volume.value = -1 - amount * 5;

    activeAudios.forEach((item) => {
      if (item.player) {
        item.player.playbackRate = clamp(customTrackFx.slowdown, 0.75, 1);
      } else if (item.audio) {
        item.audio.playbackRate = clamp(customTrackFx.slowdown, 0.75, 1);
      }
    });
  }

  function linearToDb(value: number) {
    return value === 0 ? -Infinity : 20 * Math.log10(value);
  }

  function getTrackById(id: number) {
    return tracks.find((track) => track.id === id);
  }

  function emitFxSettings() {
    customTrackFx = {
      lofiAmount,
      slowdown,
      reverseChance,
    };
    localStorage.setItem(CUSTOM_TRACK_FX_KEY, JSON.stringify(customTrackFx));
    applyCustomTrackFx();
    window.dispatchEvent(new CustomEvent("lofi-custom-track-fx-changed", { detail: customTrackFx }));
  }

  function loadTrackVolumes() {
    const raw = localStorage.getItem(TRACK_VOLUME_KEY);
    if (!raw) {
      trackVolumes = {};
      return;
    }
    try {
      const parsed = JSON.parse(raw);
      trackVolumes = parsed && typeof parsed === "object" ? parsed : {};
    } catch {
      trackVolumes = {};
    }
  }

  function getTrackVolume(id: number) {
    const value = trackVolumes[id];
    return Number.isFinite(value) ? clamp(Number(value), 0, 1) : 0.5;
  }

  function setTrackVolume(id: number, value: number) {
    trackVolumes = { ...trackVolumes, [id]: clamp(value, 0, 1) };
    localStorage.setItem(TRACK_VOLUME_KEY, JSON.stringify(trackVolumes));
    activeAudios.forEach((item) => {
      if (item.id !== id) {
        return;
      }
      if (item.player) {
        item.player.volume.value = linearToDb(getTrackVolume(id));
      } else if (item.audio) {
        item.audio.volume = getTrackVolume(id);
      }
    });
  }

  function loadCustomTrackFx() {
    const saved = localStorage.getItem(CUSTOM_TRACK_FX_KEY);
    if (!saved) {
      applyCustomTrackFx();
      return;
    }

    try {
      const parsed = JSON.parse(saved);
      customTrackFx = {
        lofiAmount: Number.isFinite(parsed.lofiAmount) ? parsed.lofiAmount : 0.5,
        slowdown: Number.isFinite(parsed.slowdown) ? parsed.slowdown : 0.92,
        reverseChance: Number.isFinite(parsed.reverseChance) ? parsed.reverseChance : 0.15,
      };
    } catch {
      customTrackFx = {
        lofiAmount: 0.5,
        slowdown: 0.92,
        reverseChance: 0.15,
      };
    }
    applyCustomTrackFx();
  }

  function buildCustomTrackRows(customs, startId) {
    return customs.map((item, idx) => {
      const newId = startId + idx;
      return {
      id: newId,
      track: item.name || `custom-track-${newId}`,
      isPlaying: false,
      imageId: ((idx % 9) + 1),
      quoteId: ((idx % 9) + 1),
      isCustom: true,
      src: item.dataUrl,
      customName: item.name || `Custom ${newId}`,
    }});
  }

  async function persistCustomTracks() {
    const customTracks = tracks
      .filter((track) => track.isCustom)
      .map((track) => ({
        name: track.customName || track.track,
        dataUrl: track.src,
      }));
    await localDB.setItem(CUSTOM_TRACKS_KEY, JSON.stringify(customTracks));
    window.dispatchEvent(new CustomEvent("lofi-custom-tracks-synced"));
  }

  async function loadCustomTracks() {
    try {
      const raw = await localDB.getItem(CUSTOM_TRACKS_KEY);
      if (!raw) {
        return;
      }
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) {
        return;
      }
      const deduped = parsed.filter(
        (item, idx, arr) =>
          arr.findIndex((x) => x.dataUrl === item.dataUrl || (x.name === item.name && x.dataUrl === item.dataUrl)) === idx,
      );
      const baseCount = tracks.length;
      tracks = [...tracks, ...buildCustomTrackRows(deduped, baseCount + 1)];
    } catch {
      // Ignore malformed custom track payload.
    }
  }

  async function addCustomTrack(name: string, dataUrl: string) {
    if (tracks.some((track) => track.isCustom && track.src === dataUrl)) {
      return;
    }
    const nextId = tracks.length + 1;
    tracks = [
      ...tracks,
      {
        id: nextId,
        track: name,
        isPlaying: false,
        imageId: ((nextId - 1) % 9) + 1,
        quoteId: ((nextId - 1) % 9) + 1,
        isCustom: true,
        src: dataUrl,
        customName: name,
      },
    ];
    await persistCustomTracks();
  }

  // Visible tracks animation
  let visibleTrackId = 1;
  $: activeTrack = tracks.find((track) => track.isPlaying) || tracks[visibleTrackId - 1];

  function nextTrack() {
    visibleTrackId < tracks.length ? visibleTrackId++ : (visibleTrackId = 1);
  }
  function prevTrack() {
    visibleTrackId > 1 ? visibleTrackId-- : (visibleTrackId = tracks.length);
  }

  let lastScrollTime = 0;
  const SCROLL_THROTTLE = 100; // ms

  function handleScroll(event: WheelEvent) {
    const currentTime = Date.now();
    if (currentTime - lastScrollTime < SCROLL_THROTTLE) return;

    if (event.deltaY > 0) {
      nextTrack();
      lastScrollTime = currentTime;
    } else if (event.deltaY < 0) {
      prevTrack();
      lastScrollTime = currentTime;
    }
  }

  async function startTrack(id: number) {
    const target = getTrackById(id);
    if (!target) {
      return;
    }

    const source = target.isCustom && target.src
      ? target.src
      : target.source || `assets/engine/tracks/${target.track}`;
    if (!source) {
      return;
    }

    Tone.start();

    try {
      const player = new Tone.Player({
        loop: true,
      });
      player.connect(customTrackFilter);
      player.playbackRate = clamp(customTrackFx.slowdown, 0.75, 1);
      player.reverse = Math.random() < clamp(customTrackFx.reverseChance, 0, 0.3);
      player.volume.value = linearToDb(getTrackVolume(id));
      await player.load(source);
      player.start();
      activeAudios.push({
        id,
        audio: null,
        player,
        mediaSource: null,
        isCustom: !!target.isCustom,
      });
      target.isPlaying = true;
      visibleTrackId = id;
      return;
    } catch {
      // Fallback for sources/codecs the decoder rejects (e.g., some FLAC builds).
    }

    const audio = new Audio(source);
    audio.loop = true;
    audio.volume = getTrackVolume(id);
    audio.playbackRate = clamp(customTrackFx.slowdown, 0.75, 1);
    const mediaSource = new Tone.MediaElementSource(audio);
    mediaSource.connect(customTrackFilter);
    audio.play();
    activeAudios.push({
      id,
      audio,
      player: null,
      mediaSource,
      isCustom: !!target.isCustom,
    });
    target.isPlaying = true;
    visibleTrackId = id;
  }

  function stopTrack(id: number) {
    activeAudios.forEach((item) => {
      if (item.id === id) {
        if (item.player) {
          item.player.stop();
          item.player.dispose();
        } else if (item.audio) {
          item.audio.pause();
          if (item.mediaSource) {
            item.mediaSource.dispose();
          }
        }
      }
    });
    activeAudios = activeAudios.filter((item) => item.id !== id);
    const target = getTrackById(id);
    if (target) {
      target.isPlaying = false;
    }
  }

  function stopAllTracks() {
    activeAudios.forEach((item) => {
      if (item.player) {
        item.player.stop();
        item.player.dispose();
      } else if (item.audio) {
        item.audio.pause();
        if (item.mediaSource) {
          item.mediaSource.dispose();
        }
      }
    });
    activeAudios = [];
    tracks.forEach((track) => {
      track.isPlaying = false;
    });
  }

  function playOnlyTrack(id: number) {
    stopAllTracks();
    startTrack(id);
  }

  function cycleTrack() {
    const active = tracks.find((track) => track.isPlaying);
    const startIndex = active ? active.id : visibleTrackId;
    const nextId = startIndex >= tracks.length ? 1 : startIndex + 1;
    playOnlyTrack(nextId);
  }

  function shuffleTrack() {
    const active = tracks.find((track) => track.isPlaying);
    const activeId = active ? active.id : -1;

    if (tracks.length <= 1) {
      if (tracks.length === 1) {
        playOnlyTrack(1);
      }
      return;
    }

    let nextId = activeId;
    while (nextId === activeId) {
      nextId = Math.floor(Math.random() * tracks.length) + 1;
    }
    playOnlyTrack(nextId);
  }

  function toggleTrack(id: number) {
    const target = getTrackById(id);
    if (!target) {
      return;
    }

    if (target.isPlaying) {
      stopTrack(id);
      tracks = tracks;
      return;
    }

    playOnlyTrack(id);
    tracks = tracks;
  }

  function setSelectedTrackVolume(value: number) {
    const active = tracks.find((track) => track.isPlaying) || getTrackById(visibleTrackId);
    if (!active) {
      return;
    }
    setTrackVolume(active.id, value);
  }

  function playRandomTrack() {
    if (!tracks.length) {
      return;
    }
    const active = tracks.find((track) => track.isPlaying);
    const candidates = tracks.filter((track) => !active || track.id !== active.id);
    const pool = candidates.length ? candidates : tracks;
    const id = pool[Math.floor(Math.random() * pool.length)].id;
    playOnlyTrack(id);
  }

  function shuffleCurrentTrack() {
    window.dispatchEvent(new CustomEvent("lofi-shuffle-track"));
  }

  onMount(() => {
    loadCustomTrackFx();
    lofiAmount = customTrackFx.lofiAmount;
    slowdown = customTrackFx.slowdown;
    reverseChance = customTrackFx.reverseChance;
    loadTrackVolumes();
    loadCustomTracks();

    const handleKeydown = (e: KeyboardEvent) => {
      if (e.key === "k") {
        stopAllTracks();
        return;
      }

      if (e.target instanceof HTMLElement && e.target.closest("input")) {
        return;
      }

      if (e.key === "ArrowUp") {
        prevTrack();
      } else if (e.key === "ArrowDown") {
        nextTrack();
      }

      const keyNum = Number(e.key);
      if (Number.isInteger(keyNum) && keyNum >= 1 && keyNum <= 9) {
        const target = tracks[keyNum - 1];
        if (target) {
          toggleTrack(target.id);
        }
      }
    };

    const handleToggleTrack = (e: CustomEvent) => {
      if (e.detail && e.detail.id) {
        toggleTrack(e.detail.id);
      }
    };
    const handleCycleTrack = () => {
      cycleTrack();
    };
    const handleShuffleTrack = () => {
      shuffleTrack();
    };
    const handleRandomTrack = () => {
      playRandomTrack();
    };
    const handleSettingsOpen = (e: CustomEvent) => {
      if (e.detail && e.detail.isActive !== undefined) {
        isMobileHidden = e.detail.isActive;
      }
    };
    const handleAddCustomTrack = (e: CustomEvent) => {
      if (e.detail && e.detail.dataUrl) {
        addCustomTrack(e.detail.name || "Custom Track", e.detail.dataUrl);
      }
    };
    const handleCustomTrackFxChange = (e: CustomEvent) => {
      if (!e.detail) {
        return;
      }
      customTrackFx = {
        lofiAmount: Number.isFinite(e.detail.lofiAmount) ? e.detail.lofiAmount : customTrackFx.lofiAmount,
        slowdown: Number.isFinite(e.detail.slowdown) ? e.detail.slowdown : customTrackFx.slowdown,
        reverseChance: Number.isFinite(e.detail.reverseChance)
          ? e.detail.reverseChance
          : customTrackFx.reverseChance,
      };
      lofiAmount = customTrackFx.lofiAmount;
      slowdown = customTrackFx.slowdown;
      reverseChance = customTrackFx.reverseChance;
      applyCustomTrackFx();
    };
    const handleUiVisibility = (event: Event) => {
      const customEvent = event as CustomEvent;
      isUiHidden = !!customEvent.detail?.hidden;
    };
    const handleSelectedTrackVolume = (event: Event) => {
      const customEvent = event as CustomEvent;
      const value = Number(customEvent.detail?.volume);
      if (!Number.isFinite(value)) {
        return;
      }
      setSelectedTrackVolume(clamp(value, 0, 1));
    };
    window.addEventListener("keydown", handleKeydown);
    window.addEventListener("lofi-toggle-track", handleToggleTrack);
    window.addEventListener("lofi-cycle-track", handleCycleTrack);
    window.addEventListener("lofi-shuffle-track", handleShuffleTrack);
    window.addEventListener("lofi-random-track", handleRandomTrack);
    window.addEventListener("settings-open-changed", handleSettingsOpen);
    window.addEventListener("lofi-add-custom-track", handleAddCustomTrack);
    window.addEventListener("lofi-custom-track-fx-changed", handleCustomTrackFxChange);
    window.addEventListener("lofi-ui-visibility-changed", handleUiVisibility);
    window.addEventListener("lofi-selected-track-volume", handleSelectedTrackVolume);
    return () => {
      window.removeEventListener("keydown", handleKeydown);
      window.removeEventListener("lofi-toggle-track", handleToggleTrack);
      window.removeEventListener("lofi-cycle-track", handleCycleTrack);
      window.removeEventListener("lofi-shuffle-track", handleShuffleTrack);
      window.removeEventListener("lofi-random-track", handleRandomTrack);
      window.removeEventListener("lofi-add-custom-track", handleAddCustomTrack);
      window.removeEventListener("lofi-custom-track-fx-changed", handleCustomTrackFxChange);
      window.removeEventListener("lofi-ui-visibility-changed", handleUiVisibility);
      window.removeEventListener("lofi-selected-track-volume", handleSelectedTrackVolume);
    };
  });
</script>

<div
  class={"track-list" + (isMobileHidden ? " mobile-hidden" : "")}
  on:wheel={handleScroll}
>
  <div class="now-playing glass">
    <div class="now-playing-copy">
      <span class="now-playing-label">Now Playing</span>
      <span class="now-playing-title">{activeTrack?.title || activeTrack?.customName || `Track ${activeTrack?.id || visibleTrackId}`}</span>
    </div>
    <button
      class="now-playing-shuffle"
      type="button"
      title="Shuffle current playing track"
      aria-label="Shuffle current playing track"
      on:click={shuffleCurrentTrack}
      disabled={!tracks.length}
    >
      <IconArrowsShuffle size={14} />
    </button>
  </div>

  {#if !isUiHidden}
    <div class="tracklist-fx glass">
      <div class="fx-row">
        <label for="tracklist-lofi">LoFi Amount {Math.round(lofiAmount * 100)}%</label>
        <input id="tracklist-lofi" type="range" min="0" max="1" step="0.01" bind:value={lofiAmount} on:input={emitFxSettings} />
      </div>
      <div class="fx-row">
        <label for="tracklist-slow">Slowdown {slowdown.toFixed(2)}x</label>
        <input id="tracklist-slow" type="range" min="0.75" max="1" step="0.01" bind:value={slowdown} on:input={emitFxSettings} />
      </div>
      <div class="fx-row">
        <label for="tracklist-rev">Reverse {Math.round(reverseChance * 100)}%</label>
        <input id="tracklist-rev" type="range" min="0" max="0.3" step="0.01" bind:value={reverseChance} on:input={emitFxSettings} />
      </div>
    </div>
  {/if}

  <div class="wrapper">
    <div class="carousel">
      {#each tracks as track}
        <TrackListItem
          {track}
          totalTracks={tracks.length}
          {visibleTrackId}
          currentVolume={getTrackVolume(track.id)}
          onToggleTrack={toggleTrack}
          onSetTrackVolume={setTrackVolume}
          setMeVisible={(id) => (visibleTrackId = id)}
        />
      {/each}
    </div>
  </div>
</div>

<style>
  .track-list {
    width: min(450px, 90vw);
    height: min(52vh, 460px);
    max-height: calc(100vh - 230px);
    padding: 10px 8px;
    border-radius: 20px;
    z-index: 18;
    position: fixed;
    left: 50%;
    top: 80px;
    transform: translateX(-50%);
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .now-playing {
    width: fit-content;
    margin-bottom: 6px;
    border-radius: 999px;
    padding: 6px 8px 6px 10px;
    display: flex;
    gap: 8px;
    align-items: center;
    color: white;
  }

  .now-playing-copy {
    display: grid;
    gap: 2px;
  }

  .now-playing-label {
    opacity: 0.75;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  .now-playing-title {
    font-size: 12px;
    font-weight: 700;
  }

  .now-playing-shuffle {
    width: 24px;
    height: 24px;
    border: none;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.08);
    color: inherit;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: transform 0.15s ease, background-color 0.15s ease, opacity 0.15s ease;
  }

  .now-playing-shuffle:hover:not(:disabled) {
    background: rgba(255, 255, 255, 0.16);
    transform: translateY(-1px);
  }

  .now-playing-shuffle:disabled {
    opacity: 0.45;
    cursor: not-allowed;
  }

  .wrapper {
    height: 100%;
    width: 100%;
    display: flex;
    justify-content: center;
    overflow: hidden;
  }

  .carousel {
    position: relative;
    width: 100%;
    max-width: 410px;
    display: flex;
    justify-content: center;
    flex-direction: column;
  }

  .tracklist-fx {
    width: 96%;
    margin-bottom: 8px;
    border-radius: 12px;
    padding: 8px;
    display: grid;
    gap: 6px;
  }

  .fx-row {
    display: grid;
    gap: 4px;
  }

  .fx-row label {
    font-size: 11px;
    opacity: 0.85;
  }

  .fx-row input {
    width: 100%;
  }

  @media only screen and (max-width: 600px) {
    .track-list {
      width: 96vw;
      top: 64px;
      height: calc(100vh - 290px);
      min-height: 250px;
      max-height: none;
      padding: 8px 6px;
      border-radius: 14px;
    }

    .now-playing {
      padding: 5px 7px 5px 8px;
      margin-bottom: 4px;
    }

    .now-playing-shuffle {
      width: 22px;
      height: 22px;
    }

    .tracklist-fx {
      padding: 6px;
      gap: 4px;
      margin-bottom: 6px;
    }

    .fx-row label {
      font-size: 10px;
    }
    .mobile-hidden {
      display: none;
    }
  }
</style>
