import Chords from './Chords';
import Chord from './Chord';

class ChordProgression {
    static generate(length, rng = Math.random) {
        if(length < 2)
            return null;

        const progression = [];
        let chord = Chords[Math.floor(rng()*Chords.length)];
        
        for(let i = 0; i < length; i++) {
            progression.push(new Chord(
                chord.degree,
                [...chord.intervals],
                [...chord.nextChordIdxs]));
            chord = Chords[chord.nextChordIdx(rng)];
        }
        
        return progression;
    }
}

export default ChordProgression;