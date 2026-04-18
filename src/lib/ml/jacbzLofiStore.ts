import { writable } from 'svelte/store';
import type { MlTrackOutput } from './lofiApi';
import { fetchMlTrack } from './lofiApi';

const SERVER_URL = 'https://lofiserver.jacobzhang.de';

export const mlLofiTrack = writable<MlTrackOutput | null>(null);

let intervalId: ReturnType<typeof setInterval> | null = null;

async function updateTrack() {
  try {
    const track = await fetchMlTrack({ serverUrl: SERVER_URL, endpoint: 'generate' });
    mlLofiTrack.set(track);
    console.log("Successfully fetched ML track:", track);
  } catch (e) {
    console.log('Failed to fetch ML lofi track:', e);
  }
}

export function startMlLofiAutoUpdate() {
  updateTrack();
  if (intervalId) clearInterval(intervalId);
  intervalId = setInterval(updateTrack, 60000); // 1 minute
}

export function stopMlLofiAutoUpdate() {
  if (intervalId) clearInterval(intervalId);
  intervalId = null;
}
