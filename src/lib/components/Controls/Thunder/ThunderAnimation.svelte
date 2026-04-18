<script lang="ts">
  import { onDestroy, onMount } from "svelte";

  export let isStorming: boolean;

  let isFlashing = false;
  let flashStrength = 1;
  let flashTimeout: number | null = null;

  function clearFlashTimeout() {
    if (flashTimeout !== null) {
      window.clearTimeout(flashTimeout);
      flashTimeout = null;
    }
  }

  function clamp(value: number, min: number, max: number) {
    return Math.max(min, Math.min(max, value));
  }

  function handleThunderFlash(event: Event) {
    const detail = (event as CustomEvent<{ intensity?: number }>).detail;
    if (!isStorming) {
      return;
    }

    flashStrength = clamp(Number(detail?.intensity ?? 1), 0.65, 1.5);
    isFlashing = true;
    clearFlashTimeout();
    flashTimeout = window.setTimeout(() => {
      isFlashing = false;
    }, 180);
  }

  onMount(() => {
    window.addEventListener("lofi-thunder-flash", handleThunderFlash);
  });

  onDestroy(() => {
    window.removeEventListener("lofi-thunder-flash", handleThunderFlash);
    clearFlashTimeout();
  });

  $: if (!isStorming && isFlashing) {
    clearFlashTimeout();
    isFlashing = false;
  }
</script>

<div class="storm-layer" class:active={isStorming} aria-hidden="true"></div>
<div class="flash-layer" class:active={isFlashing} style={`--flash-strength:${flashStrength};`} aria-hidden="true"></div>

<style>
  .storm-layer,
  .flash-layer {
    position: fixed;
    inset: 0;
    pointer-events: none;
  }

  .storm-layer {
    z-index: 15;
    opacity: 0;
    transition: opacity 700ms ease;
    background:
      radial-gradient(circle at 22% 16%, rgba(188, 214, 255, 0.14), transparent 44%),
      radial-gradient(circle at 82% 78%, rgba(205, 226, 255, 0.1), transparent 42%),
      linear-gradient(180deg, rgba(34, 44, 62, 0.08), rgba(10, 12, 22, 0.14));
    mix-blend-mode: screen;
  }

  .storm-layer.active {
    opacity: 1;
  }

  .flash-layer {
    z-index: 26;
    opacity: 0;
    background:
      linear-gradient(120deg, rgba(255, 255, 255, 0.78), rgba(224, 238, 255, 0.42) 40%, rgba(255, 255, 255, 0));
  }

  .flash-layer.active {
    animation: thunderFlash 180ms ease-out;
  }

  @keyframes thunderFlash {
    0% {
      opacity: calc(0.8 * var(--flash-strength));
    }

    35% {
      opacity: calc(0.95 * var(--flash-strength));
    }

    100% {
      opacity: 0;
    }
  }
</style>
