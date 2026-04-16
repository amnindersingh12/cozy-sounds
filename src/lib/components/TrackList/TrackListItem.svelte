<script lang="ts">
  import { afterUpdate, onMount } from "svelte";
  import { t } from "../../locales/store";

  export let setMeVisible;
  export let onToggleTrack;
  export let onSetTrackVolume;
  export let currentVolume = 0.5;
  export let track = {
    id: -1,
    track: "none",
    isPlaying: false,
    imageId: 1,
    quoteId: 1,
    isCustom: false,
    src: "",
    customName: "",
  };

  export let totalTracks = 13;

  export let visibleTrackId = -1;
  let trackItemAnimationClass = "item-hidden";
  let volume = 0.5;

  function updateAnimation() {
    if (track.id == visibleTrackId) {
      trackItemAnimationClass = "item-visible";
    } else if (track.id + 1 == visibleTrackId) {
      trackItemAnimationClass = "item-before-visible";
    } else if (track.id - 1 == visibleTrackId) {
      trackItemAnimationClass = "item-after-visible";
    }
    // Edge tracks
    else if (track.id == totalTracks && visibleTrackId == 1) {
      trackItemAnimationClass = "item-before-visible";
    } else if (track.id == 1 && visibleTrackId == totalTracks) {
      trackItemAnimationClass = "item-after-visible";
    } else {
      trackItemAnimationClass = "item-hidden";
    }
  }

  function handleVolumeChange(event) {
    volume = Number(event.target.value);
    if (onSetTrackVolume) {
      onSetTrackVolume(track.id, volume);
    }
  }

  onMount(() => {
    volume = currentVolume;
  });

  updateAnimation();
  afterUpdate(updateAnimation);

  $: imageId = track.imageId || ((track.id - 1) % 9) + 1;
  $: quoteId = track.quoteId || ((track.id - 1) % 9) + 1;
  $: quote = $t.tracks[quoteId]?.quote || $t.tracks[1].quote;
  $: title = track.isCustom ? track.customName || `Custom ${track.id}` : track.title || `Track ${track.id}`;
  $: volume = currentVolume;
</script>

<!-- svelte-ignore a11y-click-events-have-key-events -->
<div
  on:contextmenu={() => {
    if (!track.isPlaying) {
      setMeVisible(track.id);
    }
  }}
  on:click={() => {
    if (onToggleTrack) {
      onToggleTrack(track.id);
    }
  }}
  class={"carousel__item " + trackItemAnimationClass}
>
  <div
    class={"carousel__item-body glass " + (track.isPlaying ? "playing" : "")}
  >
    <img
      class="carousel__item-body__img"
      src="assets/images/{imageId}.jpg"
      alt=""
    />
    <div>
      <p id="title">{title}</p>
      <p id="info">{quote}</p>
      {#if track.isPlaying}
        <input
          type="range"
          min="0"
          max="1"
          step="0.01"
          bind:value={volume}
          on:input={handleVolumeChange}
          on:click={(e) => e.stopPropagation()}
          id="volume-slider"
          class="volume-slider"
        />
      {/if}
    </div>
  </div>
</div>

<style>
  .carousel__item {
    display: flex;
    align-items: center;
    position: absolute;
    width: 100%;
    will-change: transform, opacity;
    transition-duration: 500ms;
  }
  .carousel__item-body {
    position: relative;
    width: 100%;
    color: white;
    border-radius: 8px;
    padding-right: 10px;
    display: flex;
    gap: 12px;
    min-width: max-content;
  }

  .carousel__item-body__img {
    width: 64px;
    min-width: 64px;
    height: 64px;
    margin: 8px;
    border-radius: 5px;
    overflow: hidden;
  }
  #title {
    font-size: 14px;
    font-weight: 600;
    margin-top: 8px;
    margin-bottom: 4px;
  }
  #info {
    display: flex;
    flex-wrap: wrap;
    font-size: 10px;
    max-width: 250px;
  }

  .playing {
    background-color: rgba(0, 0, 0, 60%);
  }
  .item-visible {
    opacity: 1;
    visibility: visible;
  }
  .item-hidden {
    opacity: 0.2;
    visibility: hidden;
    animation-duration: 0ms;
    transform: scale(0.1);
  }
  .item-before-visible {
    opacity: 0.5;
    visibility: visible;
    transform: scale(0.8) translate(0, -120px);
  }
  .item-after-visible {
    opacity: 0.5;
    visibility: visible;
    transform: scale(0.8) translate(0, 120px);
  }
  .volume-slider {
    position: absolute;
    bottom: 8px;
    right: 8px;
    width: 70px;
    height: 5px;
  }

  @media only screen and (max-width: 600px) {
    .carousel__item-body {
      gap: 8px;
    }
    .carousel__item-body__img {
      width: 34px;
      min-width: 34px;
      height: 34px;
    }
    #title,
    #info {
      margin: 0;
    }
    #info {
      font-size: 10px;
      max-width: 56vw;
    }
  }
</style>
