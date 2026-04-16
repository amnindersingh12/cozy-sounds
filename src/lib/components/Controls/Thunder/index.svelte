<script lang="ts">
  import { IconCloudStorm } from "@tabler/icons-svelte";
  import { onMount } from "svelte";
  import * as Tone from "tone";

  export let volume: number;

  const linearToDb = (value: number) => (value === 0 ? -Infinity : 20 * Math.log10(value));
  const storm = new Tone.Player("assets/engine/effects/thunder.mp3", () => {
    if (isStorming) {
      storm.start();
    }
  });
  storm.loop = true;
  storm.connect(Tone.Master);
  let isStorming = false;

  function toggleThunder() {
    if (isStorming) {
      storm.stop();
    } else {
      storm.volume.value = linearToDb(volume);
      storm.start();
    }

    isStorming = !isStorming;
  }

  // Shortuct to toggle storm with "S" key
  window.addEventListener("keydown", (e) => {
    if (e.key === "s") {
      toggleThunder();
    }
  });

  // Update volume
  onMount(() => {
    window.addEventListener("lofi-toggle-thunder", toggleThunder);
    setInterval(() => {
      storm.volume.value = linearToDb(volume);
    }, 100);

    return () => {
      window.removeEventListener("lofi-toggle-thunder", toggleThunder);
    };
  });
</script>

<button
  style={`
    background-color: ${isStorming ? "white" : "transparent"};
    `}
  on:click={toggleThunder}
>
  <IconCloudStorm size={25} color={isStorming ? "black" : "white"} />
</button>

<style>
  button {
    color: white;
    border-radius: 50%;
    aspect-ratio: 4/4;
  }
</style>
