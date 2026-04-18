// Use native fetch (available in Node.js 18+)
function createWritable(initialValue) {
    let value = initialValue;
    return {
        set: (v) => { value = v; console.log("mlLofiTrack updated:", JSON.stringify(v, null, 2)); },
        subscribe: (fn) => { fn(value); return () => {}; }
    };
}

const mlLofiTrack = createWritable(null);
const SERVER_URL = 'https://lofiserver.jacobzhang.de';

async function fetchMlTrack({ serverUrl, endpoint }) {
    const url = `${serverUrl}/${endpoint}`;
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Fetch failed with status ${response.status}`);
    return await response.json();
}

async function updateTrack() {
    try {
        console.log(`[${new Date().toISOString()}] Fetching ML track...`);
        const track = await fetchMlTrack({ serverUrl: SERVER_URL, endpoint: 'generate' });
        mlLofiTrack.set(track);
        console.log(`[${new Date().toISOString()}] Successfully fetched ML track.`);
    } catch (e) {
        console.log(`[${new Date().toISOString()}] Failed to fetch ML lofi track:`, e.message);
    }
}

console.log("Starting ML Fetch test (will run for 2 minutes)...");
updateTrack(); 
setInterval(updateTrack, 60000); 

setTimeout(() => {
    console.log("Test finished.");
    process.exit(0);
}, 125000); 
