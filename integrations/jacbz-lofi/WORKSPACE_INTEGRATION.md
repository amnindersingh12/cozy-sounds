# jacbz/Lofi Integration In This Workspace

This workspace now embeds the full upstream repository in:

- integrations/jacbz-lofi

## 1) Install Python dependencies

From the repo root:

```bash
python3 -m venv .venv-ml
source .venv-ml/bin/activate
pip install -r integrations/jacbz-lofi/server/requirements.txt
pip install -r integrations/jacbz-lofi/model/requirements.txt
```

## 2) Build or update the dataset (Hooktheory + optional Spotify/Lyrics)

Follow upstream dataset instructions in:

- integrations/jacbz-lofi/model/dataset/README.md

Then run:

```bash
npm run ml:model:dataset:build
```

## 3) Train model checkpoints

Lofi2Lofi decoder model:

```bash
npm run ml:model:lofi2lofi:train
```

Lyrics2Lofi model:

```bash
npm run ml:model:lyrics2lofi:embeddings
npm run ml:model:lyrics2lofi:train
```

## 4) Place checkpoints for server runtime

The Flask server expects:

- integrations/jacbz-lofi/checkpoints/lofi2lofi_decoder.pth
- integrations/jacbz-lofi/checkpoints/lyrics2lofi.pth

## 5) Run integrated local model server

```bash
npm run ml:server:dev
```

The app now defaults to:

- http://127.0.0.1:5050

## 6) Regenerate tunes in the app

Open Song Mode -> ML Preset:

- Source `Generate random latent` for random model tracks
- Source `Predict from text` for text-to-lofi
- Source `Decode latent vector` for vector decoding

Then click `Apply ML Preset`.

Ambient channels (rain, thunder, campfire, jungle) remain independent and can be mixed on top.
