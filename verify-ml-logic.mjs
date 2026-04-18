import { writable } from 'svelte/store';
import fetch from 'node-fetch';

function createWritable(initialValue) {
    let value = initialValue;
    const subscribers = [];
    return {
        set: (v) => { 
            value = v; 
            subscribers.forEach(fn => fn(v));
        },
        subscribe: (fn) => { 
            fn(value); 
            subscribers.push(fn);
            return () => {
                const index = subscribers.indexOf(fn);
                if (index > -1) subscribers.splice(index, 1);
            }; 
        }
    };
}

const mlLofiTrack = createWritable(null);
const SERVER_URL = 'https://lofiserver.jacobzhang.de';

async function fetchMlTrack({ serverUrl, endpoint }) {
    const url = serverUrl + "/" + endpoint;
    const response = await fetch(url);
    if (!response.ok) throw new Error("Fetch failed");
    return await response.json();
}

async function updateTrack() {
    try {
        console.log("[" + new Date().toISOString() + "] Fetching ML track...");
        const track = await fetchMlTrack({ serverUrl: SERVER_URL, endpoint: 'generate' });
        mlLofiTrack.set(track);
    } catch (e) {
        console.log('Failed to fetch ML lofi track:', e.message);
    }
}

mlLofiTrack.subscribe((track) => {
    if (track) {
        console.log("[" + new Date().toISOString() + "] MlLofiPlayer received track: " + JSON.stringify(track).substring(0, 100) + "...");
        console.log("Playing track with BPM:", track.bpm);
    }
});

function startMlLofiAutoUpdate() {
    updateTrack();
    setInterval(updateTrack, 60000);
}

console.log("Starting ML Logic verification...");
startMlLofiAutoUpdate();

setTimeout(() => {
    console.log("Verification finished.");
    process.exit(0);
}, 125000);
