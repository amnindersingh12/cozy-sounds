<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import * as Tone from "tone";

  export let isRaining: boolean;

  let canvas: HTMLCanvasElement;
  let ctx: CanvasRenderingContext2D;
  let rainDrops: any[] = [];
  let windowDrops: any[] = [];
  let animationFrame: number;
  let beatEventId: number | null = null;
  let beatBoost = 0;

  const RAIN_DROP_COUNT = 260;
  const WINDOW_DROP_COUNT = 85;

  function createRainDrop() {
    return {
      x: Math.random() * canvas.width,
      y: Math.random() * canvas.height,
      length: 8 + Math.random() * 16,
      speed: 3 + Math.random() * 5,
      drift: -1.5 + Math.random() * 0.8,
      opacity: 0.14 + Math.random() * 0.35,
    };
  }

  function createWindowDrop() {
    return {
      x: Math.random() * canvas.width,
      y: Math.random() * canvas.height,
      radius: 1.5 + Math.random() * 2.8,
      slideSpeed: 0.08 + Math.random() * 0.32,
      wobble: Math.random() * Math.PI * 2,
      opacity: 0.14 + Math.random() * 0.3,
      trail: 8 + Math.random() * 36,
    };
  }

  function initRain() {
    rainDrops = [];
    windowDrops = [];
    for (let i = 0; i < RAIN_DROP_COUNT; i++) {
      rainDrops.push(createRainDrop());
    }
    for (let i = 0; i < WINDOW_DROP_COUNT; i++) {
      windowDrops.push(createWindowDrop());
    }
  }

  function resize() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
  }

  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    beatBoost = Math.max(0, beatBoost - 0.02);
    const transportRunning = Tone.Transport.state === "started";
    const pulse = transportRunning ? 1 + beatBoost * 1.8 : 1;

    for (let drop of rainDrops) {
      ctx.beginPath();
      ctx.strokeStyle = `rgba(198, 212, 255, ${Math.min(0.9, drop.opacity * pulse)})`;
      ctx.lineWidth = 1;
      ctx.moveTo(drop.x, drop.y);
      ctx.lineTo(drop.x - 2, drop.y + drop.length * pulse);
      ctx.stroke();

      drop.y += drop.speed * pulse;
      drop.x += drop.drift;

      if (drop.y > canvas.height) {
        drop.y = -20;
        drop.x = Math.random() * canvas.width;
      }
      if (drop.x < -30) {
        drop.x = canvas.width + Math.random() * 10;
      }
    }

    for (let drop of windowDrops) {
      const wobble = Math.sin(performance.now() * 0.0015 + drop.wobble) * 0.35;
      const slide = drop.slideSpeed * (0.7 + beatBoost);
      drop.y += slide;
      drop.x += wobble * 0.12;

      ctx.beginPath();
      ctx.fillStyle = `rgba(220, 232, 255, ${Math.min(0.55, drop.opacity + beatBoost * 0.08)})`;
      ctx.arc(drop.x, drop.y, drop.radius, 0, Math.PI * 2);
      ctx.fill();

      ctx.beginPath();
      ctx.strokeStyle = `rgba(200, 218, 255, ${Math.min(0.45, drop.opacity)})`;
      ctx.lineWidth = Math.max(0.5, drop.radius * 0.35);
      ctx.moveTo(drop.x, drop.y + drop.radius * 0.2);
      ctx.lineTo(drop.x + wobble, drop.y + drop.trail);
      ctx.stroke();

      if (drop.y > canvas.height + 20) {
        drop.y = -10;
        drop.x = Math.random() * canvas.width;
      }
    }

    animationFrame = requestAnimationFrame(draw);
  }

  function scheduleBeatReactivePulse() {
    if (beatEventId !== null) {
      Tone.Transport.clear(beatEventId);
      beatEventId = null;
    }
    beatEventId = Tone.Transport.scheduleRepeat(() => {
      if (isRaining) {
        beatBoost = 1;
      }
    }, "4n") as unknown as number;
  }

  onMount(() => {
    ctx = canvas.getContext("2d")!;
    resize();
    initRain();
    scheduleBeatReactivePulse();
    window.addEventListener("resize", resize);
    draw();
  });

  onDestroy(() => {
    if (beatEventId !== null) {
      Tone.Transport.clear(beatEventId);
    }
    cancelAnimationFrame(animationFrame);
    window.removeEventListener("resize", resize);
  });

  $: if (!isRaining && ctx) {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
  }
</script>

<canvas bind:this={canvas} class="rain"></canvas>

<style>
  .rain {
    position: fixed;
    inset: 0;
    pointer-events: none;
    z-index: 14;
  }

  /* 🌫️ Fog layer */
  :global(body)::before {
    content: "";
    position: fixed;
    inset: 0;
    pointer-events: none;
    z-index: 13;

    background: radial-gradient(circle at 50% 50%, rgba(255,255,255,0.05), transparent 70%);
    opacity: 0;
    transition: opacity 1s ease;
  }

  :global(body.lightning)::before,
  :global(body.lofi-raining)::before {
    opacity: 1;
  }
</style>