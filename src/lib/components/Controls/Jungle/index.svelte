<script lang="ts">
  import { IconTrees } from "@tabler/icons-svelte";
  import { onMount } from "svelte";
  import * as Tone from "tone";

  export let volume: number;

  const linearToDb = (value: number) => (value === 0 ? -Infinity : 20 * Math.log10(value));
  const jungle = new Tone.Player("assets/engine/effects/jungle.mp3", () => {
    if (isActive) {
      jungle.start();
    }
  });
  jungle.loop = true;
  jungle.connect(Tone.Master);
  let isActive = false;

  function toggleJungle() {
    if (isActive) {
      jungle.stop();
    } else {
      jungle.volume.value = linearToDb(volume);
      jungle.start();
    }

    isActive = !isActive;
  }

  // Shortuct to toggle jungle with "D" key
  window.addEventListener("keydown", (e) => {
    if (e.key === "d") {
      toggleJungle();
    }
  });
  // Update volume
  onMount(() => {
    window.addEventListener("lofi-toggle-jungle", toggleJungle);
    setInterval(() => {
      jungle.volume.value = linearToDb(volume);
    },100);

    return () => {
      window.removeEventListener("lofi-toggle-jungle", toggleJungle);
    };
  });
</script>

<button
  style={`
        background-color: ${isActive ? "white" : "transparent"};
        `}
  on:click={toggleJungle}
>
  <IconTrees size={25} color={isActive ? "black" : "white"} />
</button>

<style>
  button {
    color: white;
    border-radius: 50%;
    aspect-ratio: 4/4;
  }
</style>
