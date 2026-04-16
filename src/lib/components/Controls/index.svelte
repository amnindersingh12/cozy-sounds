<script lang="ts">
  import { IconEye, IconEyeOff } from "@tabler/icons-svelte";
  import { onMount } from "svelte";
  import CampFire from "./CampFire/index.svelte";
  import Jungle from "./Jungle/index.svelte";
  import Rain from "./Rain/index.svelte";
  import Settings from "./Settings/index.svelte";
  import Thunder from "./Thunder/index.svelte";

  const UI_CONTROLS_HIDDEN_KEY = "UIControlsHidden";
  const STORAGE_KEY = "Volumes";
  const DEFFAULT_VOLUMES = {
    rain: 0.35,
    thunder: 1,
    campfire: 1,
    jungle: 1,
    main_track: 1,
  };
  // Load previous vols or defualt
  let volumes =
    JSON.parse(localStorage.getItem(STORAGE_KEY)) || DEFFAULT_VOLUMES;
  let isUiHidden = localStorage.getItem(UI_CONTROLS_HIDDEN_KEY) === "true";

  function broadcastUiVisibility() {
    localStorage.setItem(UI_CONTROLS_HIDDEN_KEY, isUiHidden ? "true" : "false");
    window.dispatchEvent(
      new CustomEvent("lofi-ui-visibility-changed", { detail: { hidden: isUiHidden } }),
    );
  }

  function toggleUiVisibility() {
    isUiHidden = !isUiHidden;
    broadcastUiVisibility();
  }

  onMount(() => {
    broadcastUiVisibility();
  });

  // Update
  setInterval(() => {
    volumes =
      JSON.parse(localStorage.getItem(STORAGE_KEY)) || DEFFAULT_VOLUMES;
  }, 200);
</script>

<button
  class="ui-toggle glass"
  on:click={toggleUiVisibility}
  aria-label={isUiHidden ? "Show UI controls" : "Hide UI controls"}
>
  {#if isUiHidden}
    <IconEye size={18} />
  {:else}
    <IconEyeOff size={18} />
  {/if}
</button>

<div class="controls glass">
  <Rain volume={volumes.rain} />
  <Thunder volume={volumes.thunder} />
  <Jungle volume={volumes.jungle} />
  <CampFire volume={volumes.campfire} />
  <Settings />
</div>

<style>
  .controls {
    width: 340px;
    height: 50px;
    color: white;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 20px;
    border-radius: 50px;
    position: fixed;
    left: 20px;
    top: 20px;
  }

  .ui-toggle {
    position: fixed;
    left: 16px;
    bottom: 16px;
    width: 36px;
    height: 36px;
    border-radius: 999px;
    color: white;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    z-index: 120;
  }


  @media only screen and (max-width: 600px) {
    .controls {
      left: 10px;
      top: 10px;
      width: min(90vw, 340px);
    }

    .ui-toggle {
      left: 10px;
      bottom: 10px;
      width: 34px;
      height: 34px;
    }
  }
</style>
