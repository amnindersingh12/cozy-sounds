<script lang="ts">
  import { IconSettings } from "@tabler/icons-svelte";
  import { onMount } from "svelte";
  import Background from "./Background.svelte";
  import Volume from "./Volume.svelte";


  import { t, locale, setLocale } from "../../../locales/store";

  let isActive = false;

  const onSettingsKeydown = (e: KeyboardEvent) => {
    if (e.key.toLowerCase() === "j") {
      toggle();
    }
  };

  function toggle() {
    isActive = !isActive;
    window.dispatchEvent(new CustomEvent("settings-open-changed", { detail: { isActive } }));
  }

  // when mounted toggle settings
  // to excute settings of children (old saved)
  onMount(() => {
    window.addEventListener("keydown", onSettingsKeydown);
    toggle();
    setTimeout(() => {
      toggle();
    }, 10);

    return () => {
      window.removeEventListener("keydown", onSettingsKeydown);
    };
  });

  const handleClickOutside = (event: MouseEvent) => {
    if (
      isActive &&
      event.target instanceof HTMLElement &&
      !event.target.closest("#settings-box")
    ) {
      isActive = false;
    }
  };
  document.addEventListener("click", handleClickOutside);

  const languages = [
    { code: "en", label: "English" },
    { code: "zh", label: "中文" },
    { code: "hi", label: "हिन्दी" },
    { code: "fr", label: "Français" },
    { code: "nl", label: "Nederlands" },
    { code: "ja", label: "日本語" },
    { code: "ru", label: "Русский" },
  ];
</script>

<div id="settings-box">
  <button
    style={`
          background-color: ${isActive ? "white" : "transparent"};
          `}
    on:click={toggle}
  >
    <IconSettings size={25} color={isActive ? "black" : "white"} />
  </button>
  {#if isActive}
    <div class="settings-container glass">
      <div class="settings-header">
        <h3>{$t.settings.title}</h3>
      </div>
      <div class="settings-content">
        <Background />
        <Volume />

        <div class="section language-section">
          <h4>{$t.settings.language.title}</h4>
          <div class="lang-switcher">
            {#each languages as lang}
              <button
                class:active={$locale === lang.code}
                on:click={() => setLocale(lang.code)}
              >
                {lang.label}
              </button>
            {/each}
          </div>
        </div>
      </div>
    </div>
  {/if}
</div>

<style>
  button {
    color: white;
    border-radius: 50%;
    aspect-ratio: 4/4;
    border: 1px solid rgba(255, 255, 255, 0.24);
    background: rgba(255, 255, 255, 0.08);
    backdrop-filter: blur(8px);
    transition: transform 0.18s ease, background-color 0.18s ease;
  }

  button:hover {
    transform: translateY(-1px);
    background: rgba(255, 255, 255, 0.16);
  }

  #settings-box {
    position: relative;
    z-index: 45;
  }

  .settings-container {
    position: absolute;
    right: 0;
    top: 62px;
    z-index: 100;
    max-height: min(72vh, 700px);
    padding: 16px;
    width: 360px;
    color: white;
    border-radius: 18px;
    border: 1px solid rgba(255, 255, 255, 0.16);
    background: rgba(10, 12, 16, 0.72);
    overflow-y: auto;
    animation: show 0.4s ease-in-out;
    display: flex;
    flex-direction: column;
    box-shadow: 0 16px 42px rgba(0, 0, 0, 0.35);
  }

  .settings-header {
    margin-bottom: 20px;
    padding-bottom: 10px;
  }

  .settings-header h3 {
    margin: 0;
    font-size: 1.5em;
    font-weight: 600;
  }

  .settings-content {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .section {
    padding-bottom: 10px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  }

  .section:last-child {
    border-bottom: none;
    padding-bottom: 2px;
  }

  .section h4 {
    margin: 0 0 10px 0;
    font-size: 1em;
    opacity: 0.9;
  }

  @keyframes show {
    from {
      transform: translateY(-10%);
      opacity: 0;
    }
    to {
      transform: translateY(0);
      opacity: 1;
    }
  }

  .lang-switcher {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }

  .lang-switcher button {
    width: auto;
    height: auto;
    padding: 6px 12px;
    font-size: 0.85em;
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.1);
    color: rgba(255, 255, 255, 0.7);
    border: 1px solid transparent;
    cursor: pointer;
    transition: all 0.2s;
    aspect-ratio: auto;
    border-radius: 20px;
  }

  .lang-switcher button:hover {
    background: rgba(255, 255, 255, 0.2);
    color: white;
    transform: translateY(-1px);
  }

  .lang-switcher button.active {
    background: white;
    color: black;
    font-weight: bold;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
  }

  @media only screen and (max-width: 600px) {
    .settings-container {
      width: min(88vw, 360px);
      right: -4px;
      max-height: 62vh;
    }
  }
</style>
