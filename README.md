# Transcriber: Live Captions

A web app for people with hearing loss. It listens through your phone's or computer's microphone (or a headset mic), shows what people are saying as large live captions, saves each transcript when you press Stop, and writes a summary of it.

It runs in the browser and can be installed to your home screen or desktop like a normal app. There's no build step and no server.

## Features

- **Live captions** in large, high-contrast text. A− / A+ change the size (18–72px). Words still being recognized show in grey and firm up as they're confirmed.
- **Stays on:** recognition restarts by itself after pauses, and the screen is kept awake while captioning.
- **Saved automatically** on your device (IndexedDB) while you record, and again when you press Stop. If the page closes mid-session, what was captured up to then is kept.
- **Summaries** when you stop:
  - With an Anthropic API key (Settings), Claude writes an overview, key points, action items (dates, names, numbers), and a list of passages that may have been misheard.
  - Without a key, the app makes a basic summary on the device.
- **Saved tab:** read old transcripts, summarize them again, copy them, download them as `.txt`, or delete them.
- **25 languages**, chosen in Settings.

## Browser support

| Device | Browser |
| --- | --- |
| Android | Chrome, Edge |
| Windows / Mac / Linux | Chrome, Edge |
| iPhone / iPad | Safari (iOS 14.5+). Use it in a Safari tab. Speech recognition may not work once it's added to the home screen. |
| Mac | Safari |

Firefox doesn't support speech recognition yet.

**Privacy:** in Chrome and Edge, the browser sends the audio to Google's or Microsoft's speech service to be recognized. Transcripts are stored only on your device. If you add an API key, a transcript goes to Anthropic only when it's summarized.

**Microphone:** the browser uses the device's default mic. To use a headset or earbud mic, connect it before you press Start.

## Running it

Browsers allow microphone access only over HTTPS (or on `localhost`).

### On your computer

```bash
python3 -m http.server 8000
# then open http://localhost:8000
```

### On your phone (GitHub Pages)

1. On GitHub, go to **Settings → Pages** and set **Source** to **GitHub Actions**.
2. Push to `main`. The workflow in `.github/workflows/pages.yml` publishes the app to `https://<your-username>.github.io/transcriber/`.
3. Open that address on your phone and allow microphone access.
4. To install it: **Android/Chrome** → menu → *Add to Home screen*. **iPhone** → bookmark it in Safari (see the note above).

### AI summaries

1. Create an API key at [console.anthropic.com](https://console.anthropic.com/).
2. In the app, open **Settings** and paste it into *Anthropic API key*.
3. Pick a model: Opus 5.5 (best quality, default), Sonnet 5.5, or Haiku 5.5 (cheapest). An hour of conversation is about 10–15k words, so a summary costs a few cents with Opus and a fraction of a cent with Haiku.

The key is stored only in your browser's local storage on that device. Don't use this setup on a shared computer.

## Files

| File | Purpose |
| --- | --- |
| `index.html` | Page layout: Live, Saved and Settings tabs |
| `app.js` | Speech recognition, storage, summaries, UI |
| `styles.css` | Styling (follows your device's light/dark mode) |
| `sw.js` | Offline caching of the app itself |
| `manifest.webmanifest`, `icon.svg` | Install-as-app metadata |
