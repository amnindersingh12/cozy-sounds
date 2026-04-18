const { writable } = require('svelte/store');
const fetch = require('node-fetch');

// Mocking Svelte Store
function createWritable(initialValue) {
    let value = initialValue;
    return {
        set: (v) => { value = v; console.log("mlLofiTrack updated:", v); },
        subscribe: (fn) => { fn(value); return () => {}; }
    };
}

const mlLofiTrack = createWritable(null);
const SERVER_URL = 'https://lofiserver.jacobzhang.de';

async function fetchMlTrack({ serverUrl, endpoint }) {
    const url = `${serverUrl}/${endpoint}`;
    const response = await fetch(url);
    if (!response.ok) throw new Error("Fetch failed");
    return await response.json();
}

async function updateTrack() {
    try {
        console.log("Fetching ML track...");
        const track = await fetchMlTrack({ serverUrl: SERVER_URL, endpoint: 'generate' });
        mlLofiTrack.set(track);
        console.log("Successfully fetched ML track:", track);
    } catch (e) {
        console.log('Failed to fetch ML lofi track:', e.message);
    }
}

console.log("Starting ML Fetch test (will run for 2 minutes)...");
updateTrack(); // First call
setInterval(updateTrack, 60000); // Every minute

setTimeout(() => {
    console.log("Test finished.");
    process.exit(0);
}, 130000); // 2 minutes 10 seconds
