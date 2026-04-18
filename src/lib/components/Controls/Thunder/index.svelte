<script lang="ts">
  import { IconCloudStorm } from "@tabler/icons-svelte";
  import { onMount, onDestroy } from "svelte";
  import * as Tone from "tone";

  export let volume: number;

  let storm: Tone.Player;
  let panner: Tone.Panner;
  let isStorming = false;
  let thunderButton: HTMLButtonElement | null = null;

  let flickerInterval: number;
  let lightningInterval: number;
  let panInterval: number;

  const linearToDb = (value: number) =>
    value === 0 ? -Infinity : 20 * Math.log10(value);

  async function initAudio() {
    await Tone.start();

    panner = new Tone.Panner(0).toDestination();

    storm = new Tone.Player({
      url: "assets/engine/effects/thunder.mp3",
      loop: true,
      fadeIn: 2,
      fadeOut: 2
    }).connect(panner);
  }

  function updateVolume() {
    if (storm) {
      storm.volume.value = linearToDb(volume);
    }
  }

  function triggerLightning() {
    const intensity = 0.8 + Math.random() * 0.5;
    window.dispatchEvent(
      new CustomEvent("lofi-thunder-flash", { detail: { intensity } }),
    );
  }

  function emitThunderState() {
    document.body.classList.toggle("lofi-thundering", isStorming);
    window.dispatchEvent(
      new CustomEvent("lofi-thunder-state-changed", { detail: { isStorming } }),
    );
  }

  function startLightningLoop() {
    lightningInterval = setInterval(() => {
      if (!isStorming) return;

      // random thunder timing (natural feel)
      const delay = Math.random() * 4000 + 2000;

      setTimeout(() => {
        triggerLightning();
      }, delay);
    }, 5000);
  }

  function startFlicker() {
    flickerInterval = setInterval(() => {
      if (!isStorming) return;

      const btn = thunderButton;
      if (!btn) return;

      const intensity = Math.random() * 0.15 + 0.95;
      btn.style.transform = `scale(${intensity})`;
    }, 120);
  }

  function startSpatialMovement() {
    panInterval = setInterval(() => {
      if (!isStorming) return;

      // slow drift left/right
      const target = Math.random() * 2 - 1;
      panner.pan.rampTo(target, 3);
    }, 4000);
  }

  function stopEffects() {
    clearInterval(flickerInterval);
    clearInterval(lightningInterval);
    clearInterval(panInterval);

    const btn = thunderButton;
    if (btn) btn.style.transform = "scale(1)";
  }

  function toggleThunder() {
    if (!storm) return;

    if (isStorming) {
      storm.stop();
      stopEffects();
      isStorming = false;
    } else {
      updateVolume();
      storm.start();

      startFlicker();
      startLightningLoop();
      startSpatialMovement();
      isStorming = true;
    }

    emitThunderState();
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key.toLowerCase() === "s") {
      toggleThunder();
    }
  }

  onMount(() => {
    initAudio();
    emitThunderState();
    window.addEventListener("keydown", handleKeydown);
    window.addEventListener("lofi-toggle-thunder", toggleThunder);
  });

  onDestroy(() => {
    window.removeEventListener("keydown", handleKeydown);
    window.removeEventListener("lofi-toggle-thunder", toggleThunder);

    isStorming = false;
    emitThunderState();
    stopEffects();
    document.body.classList.remove("lofi-thundering");
    storm?.dispose();
    panner?.dispose();
  });

  $: updateVolume();
</script>

<button
  bind:this={thunderButton}
  class:active={isStorming}
  on:click={toggleThunder}
>
  <span class:icon-active={isStorming}>
    <IconCloudStorm size={25} />
  </span>
</button>

<style>
  button {
    border-radius: 50%;
    aspect-ratio: 1;
    background-color: transparent;
    display: grid;
    place-items: center;
    transition: background-color 0.2s ease;
  }

  button:active {
    transform: scale(0.9);
  }

  button.active {
    background-color: white;
    box-shadow: 0 0 10px rgba(255,255,255,0.6);
  }

  :global(svg) {
    color: white;
    transition: all 0.25s ease;
  }

  .icon-active :global(svg) {
    color: black;
    transform: rotate(-10deg) scale(1.1);
  }
</style>