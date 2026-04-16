<script lang="ts">
  import { IconCampfire } from "@tabler/icons-svelte";
  import { onMount } from "svelte";
  import * as Tone from "tone";

  export let volume: number;

  const linearToDb = (value: number) => (value === 0 ? -Infinity : 20 * Math.log10(value));
  const fire = new Tone.Player("assets/engine/effects/fire.mp3", () => {
    if (isFire) {
      fire.start();
    }
  });
  fire.loop = true;
  fire.connect(Tone.Master);
  let isFire = false;

  function toggleFire() {
    if (isFire) {
      fire.stop();
    } else {
      fire.volume.value = linearToDb(volume);
      fire.start();
    }

    isFire = !isFire;
  }

  // Shortuct to toggle fire with "F" key
  window.addEventListener("keydown", (e) => {
    if (e.key === "f") {
      toggleFire();
    }
  });

  // Update volume
  onMount(() => {
    window.addEventListener("lofi-toggle-campfire", toggleFire);
    setInterval(() => {
      fire.volume.value = linearToDb(volume);
    },100);

    return () => {
      window.removeEventListener("lofi-toggle-campfire", toggleFire);
    };
  });
</script>

<button
  style={`
        background-color: ${isFire ? "white" : "transparent"};
        `}
  on:click={toggleFire}
>
  <IconCampfire size={25} color={isFire ? "black" : "white"} />
</button>

<style>
  button {
    color: white;
    border-radius: 50%;
    aspect-ratio: 4/4;
  }
</style>
