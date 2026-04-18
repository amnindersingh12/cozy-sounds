import { get } from 'svelte/store';
import * as Tone from 'tone';
import { mlLofiTrack } from './jacbzLofiStore';

let currentSynth: Tone.PolySynth | null = null;

export function playMlLofiTrack(track) {
  if (!track) return;
  if (currentSynth) {
    currentSynth.disconnect();
    currentSynth.dispose();
  }
  currentSynth = new Tone.PolySynth().toDestination();
  Tone.Transport.bpm.value = track.bpm || 80;
  // Play chords as a simple demo (expand as needed)
  if (track.chords && track.chords.length > 0 && track.key && track.mode) {
    const rootNote = Tone.Frequency(track.key, 'midi').toNote();
    for (let i = 0; i < track.chords.length; i++) {
      const time = `${i * 2}`;
      currentSynth.triggerAttackRelease(rootNote, '2n', time);
    }
    Tone.Transport.start();
  }
}

mlLofiTrack.subscribe((track) => {
  if (track) {
    playMlLofiTrack(track);
  }
});
