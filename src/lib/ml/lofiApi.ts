export type MlTrackOutput = {
  title?: string;
  key?: number;
  mode?: number;
  bpm?: number;
  energy?: number;
  valence?: number;
  chords?: number[];
  melodies?: number[][];
};

export type MlTrackRequest = {
  serverUrl: string;
  endpoint: "predict" | "decode" | "generate";
  input?: string | number[];
};

function normalizeServerUrl(serverUrl: string) {
  return serverUrl.trim().replace(/\/+$/, "");
}

function parseResponsePayload(payload: unknown): MlTrackOutput {
  if (typeof payload === "string") {
    return JSON.parse(payload) as MlTrackOutput;
  }

  return payload as MlTrackOutput;
}

function isTauriRuntime() {
  return typeof window !== "undefined" && ("__TAURI_INTERNALS__" in window || "__TAURI__" in window);
}

async function fetchViaTauriHttp(url: string) {
  const { fetch: tauriFetch } = await import("@tauri-apps/plugin-http");
  const response = await tauriFetch(url, { method: "GET" });
  if (!response.ok) {
    throw new Error(`ML service request failed with status ${response.status}`);
  }
  return response.json();
}

export async function fetchMlTrack({ serverUrl, endpoint, input }: MlTrackRequest): Promise<MlTrackOutput> {
  const baseUrl = normalizeServerUrl(serverUrl);
  const url = new URL(`${baseUrl}/${endpoint}`);
  if (endpoint !== "generate") {
    if (typeof input === "undefined") {
      throw new Error("ML input is required for predict/decode endpoints.");
    }
    url.searchParams.set("input", typeof input === "string" ? input : JSON.stringify(input));
  }

  let payload: unknown;
  try {
    const response = await fetch(url.toString(), { method: "GET" });

    if (!response.ok) {
      throw new Error(`ML service request failed with status ${response.status}`);
    }

    payload = await response.json();
  } catch (error) {
    if (!isTauriRuntime()) {
      throw error;
    }
    payload = await fetchViaTauriHttp(url.toString());
  }

  return parseResponsePayload(payload);
}