import * as Tone from 'tone';
import { mlLofiTrack } from './jacbzLofiStore';

let currentPlayers: Tone.Player[] = [];
let currentSynth: Tone.PolySynth | null = null;

function stopCurrent() {
  currentPlayers.forEach((p) => { try { p.stop(); p.dispose(); } catch {} });
  currentPlayers = [];
  if (currentSynth) {
    currentSynth.disconnect();
    currentSynth.dispose();
    currentSynth = null;
  }
  Tone.Transport.cancel();
  Tone.Transport.stop();
}

function playTrack(track) {
  stopCurrent();
  if (!track) return;
  Tone.Transport.bpm.value = track.bpm || 80;
  // Play chords as block chords (expand as needed)
  if (track.chords && track.chords.length > 0 && track.key && track.mode) {
    currentSynth = new Tone.PolySynth().toDestination();
    for (let i = 0; i < track.chords.length; i++) {
      const midi = 48 + ((track.key - 1 + track.chords[i] - 1) % 12); // crude root note
      const note = Tone.Frequency(midi, 'midi').toNote();
      Tone.Transport.schedule((time) => {
        currentSynth.triggerAttackRelease(note, '2n', time);
      }, `${i * 2}`);
    }
    Tone.Transport.start();
  }
  // TODO: Add drums, melodies, etc. for richer playback
}

mlLofiTrack.subscribe((track) => {
  if (track) playTrack(track);
});

export { playTrack, stopCurrent };
