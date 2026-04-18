<script lang="ts">
  import { onMount } from "svelte";
  import RainAnimation from "./Controls/Rain/RainAnimation.svelte";

  let isRaining = false;

  onMount(() => {
    const handler = (e: CustomEvent) => {
      isRaining = !!e.detail?.isRaining;
    };
    window.addEventListener("lofi-rain-state-changed", handler as EventListener);
    return () => window.removeEventListener("lofi-rain-state-changed", handler as EventListener);
  });
</script>

<RainAnimation {isRaining} />
