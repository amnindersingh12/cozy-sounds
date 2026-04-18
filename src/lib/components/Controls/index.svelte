<script lang="ts">
  import { onMount } from "svelte";
  import CampFire from "./CampFire/index.svelte";
  import Jungle from "./Jungle/index.svelte";
  import Rain from "./Rain/index.svelte";
  import Thunder from "./Thunder/index.svelte";

  const STORAGE_KEY = "volumes";
  const DEFAULT_VOLUMES = {
    rain: 0.35,
    thunder: 1,
    campfire: 1,
    jungle: 1,
    main_track: 1,
  };
  // Load previous vols or default
  let volumes =
    JSON.parse(localStorage.getItem(STORAGE_KEY)) || DEFAULT_VOLUMES;

  onMount(() => {
    const refreshTimer = window.setInterval(() => {
      volumes =
        JSON.parse(localStorage.getItem(STORAGE_KEY)) || DEFAULT_VOLUMES;
    }, 200);

    return () => {
      window.clearInterval(refreshTimer);
    };
  });
</script>

<div class="controls glass">
  <Rain volume={volumes.rain} />
  <Thunder volume={volumes.thunder} />
  <Jungle volume={volumes.jungle} />
  <CampFire volume={volumes.campfire} />
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
    right: 20px;
    top: 20px;
  }

  @media only screen and (max-width: 600px) {
    .controls {
      right: 10px;
      top: 10px;
      width: min(90vw, 340px);
    }
  }
</style>
