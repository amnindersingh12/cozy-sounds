<script lang="ts">
  import { onMount } from "svelte";
  import { dir, locale } from "./lib/locales/store";
  import PlayButton from "./lib/PlayButton.svelte";
  import GlobalRain from "./lib/components/GlobalRain.svelte";
  import { startMlLofiAutoUpdate } from "./lib/ml/jacbzLofiStore";

  let isExporting = false;

  const ENDPOINTS = [
    "waifu", "neko", "shinobu", "bully", "cry", "hug", "kiss", "smug",
    "highfive", "nom", "bite", "slap", "wink", "poke", "dance", "cringe",
    "blush", "happy"
  ];
  const REMOTE_BASE = "https://waifu.vercel.app/sfw/";

  const preloadAndApply = (target: HTMLElement, url: string) => {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => {
        target.style.setProperty("--app-background-image", `url('${url}')`);
        resolve(true);
      };
      img.onerror = () => resolve(false);
      img.src = url;
    });
  };

  onMount(() => {
    startMlLofiAutoUpdate();
    let disposed = false;
    const bgEl = document.getElementById("bg");

    const refreshBackground = async () => {
      if (!bgEl || disposed) return;
      
      const ep = ENDPOINTS[Math.floor(Math.random() * ENDPOINTS.length)];
      const url = `${REMOTE_BASE}${ep}?ts=${Date.now()}`;
      
      const success = await preloadAndApply(bgEl, url);
      
      // Fallback to local if remote fails
      if (!success) {
        const localId = Math.floor(Math.random() * 10) + 1;
        bgEl.style.setProperty("--app-background-image", `url('assets/background/bg${localId}.webp')`);
      }
    };

    // Initial load
    refreshBackground();

    // Rotate on every transition
    window.addEventListener("lofi-transition-fired", refreshBackground);

    // #8 — Periodic rotation every 60 seconds
    const interval = setInterval(refreshBackground, 60_000);

    // Also handle manual overrides from settings if needed
    const handleBgChanged = (e: CustomEvent) => {
      const id = e.detail?.id;
      if (id && bgEl && !disposed) {
        bgEl.style.setProperty("--app-background-image", `url('assets/background/bg${id}.webp')`);
      }
    };
    window.addEventListener("lofi-bg-changed", handleBgChanged as EventListener);

    return () => {
      disposed = true;
      clearInterval(interval);
      window.removeEventListener("lofi-transition-fired", refreshBackground);
      window.removeEventListener("lofi-bg-changed", handleBgChanged as EventListener);
    };
  });


  onMount(() => {
    const handleExportState = (event: CustomEvent) => {
      isExporting = !!event.detail?.isExporting;
    };

    window.addEventListener("lofi-scene-export-state", handleExportState);
    return () => {
      window.removeEventListener("lofi-scene-export-state", handleExportState);
    };
  });

  $: {
    if (typeof document !== "undefined") {
      document.documentElement.dir = $dir;
      document.documentElement.lang = $locale;
    }
  }

</script>

<main id="bg" class:exporting={isExporting} class="container">
  <div class="overlay-vignette"></div>
  <GlobalRain />

  <PlayButton />
</main>

<style>
  .container {
    width: 100vw;
    height: 100vh;
    position: relative;
    overflow: hidden;
    background-color: #050505;
    --app-background-image: url("assets/background/bg10.webp");
    isolation: isolate;
  }

  /* Immersive blurred background fill */
  .container::before {
    content: "";
    position: absolute;
    inset: -20px;
    background-image: var(--app-background-image);
    background-repeat: no-repeat;
    background-size: cover;
    background-position: center;
    filter: blur(4.5px) brightness(0.65);
    transform: scale(1.08); /* slight scale to hide edges */
    z-index: 0;
    pointer-events: none;
    transition: background-image 1.2s ease-in-out;
  }

  /* Remove sharp foreground to keep it immersive */
  .container::after {
    display: none;
  }

  /* Premium vignette overlay */
  .overlay-vignette {
    position: absolute;
    inset: 0;
    background: radial-gradient(circle at center, transparent 20%, rgba(0,0,0,0.5) 100%);
    z-index: 2;
    pointer-events: none;
  }

  .container > * {
    position: relative;
    z-index: 1;
  }



  .content {
    padding: 24px;
    padding-top: 30px;
    height: 100vh;
    z-index: 5;
    display: flex;
    flex-direction: row;
    justify-content: space-between;
  }

  .exporting .export-chrome {
    display: none !important;
  }
</style>
