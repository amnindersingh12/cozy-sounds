<script lang="ts">
  import { onMount } from "svelte";
  import { dir, locale } from "./lib/locales/store";
  import PlayButton from "./lib/PlayButton.svelte";
  import TrackList from "./lib/components/TrackList/index.svelte";
  import Controls from "./lib/components/Controls/index.svelte";
  import TopBar from "./lib/components/TopBar/TopBar.svelte";
  import Info from "./lib/components/InfoBox/Info.svelte";
  import Config from "./lib/Config.svelte";
  import ContextMenu from "./lib/components/ContextMenu/ContextMenu.svelte";
  import Tooltip from "./lib/components/Tooltip.svelte";

  let isExporting = false;

  onMount(() => {
    // Initialize direction
    document.documentElement.dir = $dir;
    document.documentElement.lang = $locale;

    const bgEl = document.getElementById("bg");
    const bgType = localStorage.getItem("bg-type") || "default";

    if (bgEl) {
      if (bgType === "custom") {
        const customBgId = localStorage.getItem("custom-bg-id");
        if (customBgId) {
          import("./lib/localDB").then(async ({ default: localDB }) => {
            const saved = await localDB.getItem("custom-backgrounds");
            if (saved) {
              const customs = JSON.parse(saved) as Array<{ id: string; dataUrl: string }>;
              const match   = customs.find((b) => b.id === customBgId);
              if (match) {
                const img  = new Image();
                img.onload = () => {
                  bgEl.style.backgroundImage = `url('${match.dataUrl}')`;
                };
                img.src = match.dataUrl;
              }
            }
          });
        }
      } else {
        const id  = localStorage.getItem("bg-id") || "10";
        const src = `assets/background/bg${id}.webp`;
        const img = new Image();
        img.onload = () => {
          bgEl.style.backgroundImage = `url('${src}')`;
        };
        img.src = src;
      }
    }
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
  <div class="export-chrome"><Config /></div>
  <div class="export-chrome"><TopBar /></div>
  <section class="content">
    <div class="export-chrome"><TrackList /></div>
    <div class="export-chrome"><Controls /></div>
    <div class="export-chrome"><Info /></div>
  </section>
  <PlayButton />
  <div class="export-chrome"><ContextMenu /></div>
  <div class="export-chrome"><Tooltip /></div>
</main>

<style>
  .container {
    max-width: 100vw;
    max-height: 100vh;
    height: 100vh;
    position: relative;
    overflow: hidden;
    background-color: #0a0a0a;
    background-repeat: no-repeat;
    background-size: cover;
    background-position: center;
    isolation: isolate;
    transition: background-image 0.3s ease;
  }

  .container::before {
    content: "";
    position: absolute;
    inset: 0;
    background:
      linear-gradient(145deg, rgba(18, 11, 9, 0.68), rgba(18, 11, 9, 0.18) 35%, rgba(33, 18, 14, 0.12) 62%, rgba(7, 10, 16, 0.44)),
      radial-gradient(circle at top left, rgba(255, 190, 104, 0.14), transparent 34%),
      radial-gradient(circle at bottom right, rgba(29, 18, 42, 0.2), transparent 38%);
    pointer-events: none;
    z-index: 0;
  }

  .container::after {
    content: "";
    position: absolute;
    inset: 0;
    pointer-events: none;
    z-index: 0;
    opacity: 0.14;
    mix-blend-mode: soft-light;
    background-image:
      radial-gradient(rgba(255, 255, 255, 0.24) 0.6px, transparent 0.6px),
      radial-gradient(rgba(0, 0, 0, 0.18) 0.6px, transparent 0.6px);
    background-position: 0 0, 7px 7px;
    background-size: 14px 14px;
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
