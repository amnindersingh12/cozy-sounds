<script lang="ts">
  import { IconCloudRain } from "@tabler/icons-svelte";
  import { onMount, onDestroy } from "svelte";

  export let volume: number = 0.5;

  let rain = new Audio("/assets/engine/effects/rain.mp3");
  let thunder = new Audio("/assets/engine/effects/thunder.mp3");

  let isRaining = false;
  let rainFadeTimer: number | null = null;
  let thunderFadeTimer: number | null = null;

  const RAIN_VOLUME_MULTIPLIER = 0.55;
  const THUNDER_VOLUME_MULTIPLIER = 0.3;

  function clearFadeTimer(timer: number | null) {
    if (timer !== null) {
      window.clearInterval(timer);
    }
  }

  function fadeAudio(audio: HTMLAudioElement, targetVolume: number, duration = 700) {
    clearFadeTimer(audio === rain ? rainFadeTimer : thunderFadeTimer);

    const startVolume = audio.volume;
    const startTime = performance.now();

    const timer = window.setInterval(() => {
      const elapsed = performance.now() - startTime;
      const progress = Math.min(1, elapsed / duration);
      audio.volume = startVolume + (targetVolume - startVolume) * progress;

      if (progress >= 1) {
        clearFadeTimer(timer);
        if (audio === rain) {
          rainFadeTimer = null;
        } else {
          thunderFadeTimer = null;
        }
      }
    }, 16);

    if (audio === rain) {
      rainFadeTimer = timer;
    } else {
      thunderFadeTimer = timer;
    }
  }

  function toggleRain() {
    isRaining = !isRaining;
    document.body.classList.toggle("lofi-raining", isRaining);
    window.dispatchEvent(
      new CustomEvent("lofi-rain-state-changed", { detail: { isRaining } }),
    );

    if (isRaining) {
      rain.loop = true;
      rain.volume = 0;
      rain.play().catch(() => {});
      startThunderLoop();
      fadeAudio(rain, clamp(volume * RAIN_VOLUME_MULTIPLIER, 0, 1));
    } else {
      fadeAudio(rain, 0, 350);
      fadeAudio(thunder, 0, 250);
      window.setTimeout(() => {
        rain.pause();
      }, 360);
    }
  }

  function handleKey(e: KeyboardEvent) {
    if (e.key.toLowerCase() === "a") toggleRain();
  }

  // ⚡ Thunder system
  let thunderInterval: any;

  function startThunderLoop() {
    clearInterval(thunderInterval);

    thunderInterval = setInterval(() => {
      if (!isRaining) return;

      triggerThunder();
    }, 8000 + Math.random() * 7000); // random timing
  }

  function triggerThunder() {
    // flash effect
    document.body.classList.add("lightning");

    setTimeout(() => {
      document.body.classList.remove("lightning");
    }, 150);

    thunder.currentTime = 0;
    thunder.volume = clamp(volume * THUNDER_VOLUME_MULTIPLIER, 0, 1);
    thunder.play().catch(() => {});
  }

  function clamp(value: number, min: number, max: number) {
    return Math.max(min, Math.min(max, value));
  }

  onMount(() => {
    window.addEventListener("keydown", handleKey);
    window.addEventListener("lofi-toggle-rain", toggleRain);
  });

  onDestroy(() => {
    window.removeEventListener("keydown", handleKey);
    window.removeEventListener("lofi-toggle-rain", toggleRain);
    document.body.classList.remove("lofi-raining");
    rain.pause();
    clearInterval(thunderInterval);
  });

  $: if (!isRaining) {
    rain.volume = clamp(volume * RAIN_VOLUME_MULTIPLIER, 0, 1);
  }
</script>

<div>
  <button
    class:raining={isRaining}
    on:click={toggleRain}
  >
    <IconCloudRain size={25} color={isRaining ? "black" : "white"} />
  </button>
</div>

<style>
  button {
    border-radius: 50%;
    aspect-ratio: 1;
    border: none;
    cursor: pointer;
    background: transparent;
  }

  button.raining {
    background: white;
  }

  /* ⚡ Lightning flash */
  :global(body.lightning)::after {
    content: "";
    position: fixed;
    inset: 0;
    background: white;
    opacity: 0.8;
    pointer-events: none;
    z-index: 2000;
    animation: flash 0.15s ease;
  }

  @keyframes flash {
    from { opacity: 0.9; }
    to { opacity: 0; }
  }
</style>