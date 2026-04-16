<script lang="ts">
    import { t } from "../../../locales/store";

    const STORAGE_KEY = "Volumes";
    const DEFFAULT_VOLUMES = {
        rain: 0.35,
        thunder: 1,
        campfire: 1,
        jungle: 1,
        main_track: 1,
    };

    let volumes =
        JSON.parse(localStorage.getItem(STORAGE_KEY)) || DEFFAULT_VOLUMES;
    let selectedSongVolume = 0.5;

    function saveVolume() {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(volumes));
    }

    function updateSelectedSongVolume(event: Event) {
        const target = event.target as HTMLInputElement;
        selectedSongVolume = Number(target.value);
        window.dispatchEvent(
            new CustomEvent("lofi-selected-track-volume", {
                detail: { volume: selectedSongVolume },
            }),
        );
    }

    function updateBackgroundMusicVolume(event: Event) {
        const target = event.target as HTMLInputElement;
        volumes.main_track = Number(target.value);
        saveVolume();
        window.dispatchEvent(
            new CustomEvent("lofi-background-music-volume", {
                detail: { volume: volumes.main_track },
            }),
        );
    }
</script>

<div>
    <h4>{$t.settings.volume.title}</h4>

    <section class="volume-row">
        <div class="label-line">
            <h5>Selected song</h5>
            <p>{Math.round(selectedSongVolume * 100)}%</p>
        </div>
        <input
            class="volume-slider"
            type="range"
            bind:value={selectedSongVolume}
            min="0"
            max="1"
            step="0.01"
            on:input={updateSelectedSongVolume}
        />
    </section>

    <section class="volume-row">
        <div class="label-line">
            <h5>Background music</h5>
            <p>{Math.round(volumes.main_track * 100)}%</p>
        </div>
        <input
            class="volume-slider"
            type="range"
            bind:value={volumes.main_track}
            min="0"
            max="1"
            step="0.01"
            on:input={updateBackgroundMusicVolume}
        />
    </section>
</div>

<style>
    .volume-row {
        margin-bottom: 12px;
    }

    .label-line {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 0 4px;
    }

    h5 {
        margin: 0;
        font-size: 12px;
    }

    p {
        margin: 0;
        font-size: 12px;
        opacity: 0.8;
    }

    .volume-slider {
        width: 100%;
    }
</style>
