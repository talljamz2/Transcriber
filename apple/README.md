# Live Captions for iPhone, iPad and Mac

A native app that captions speech around you with Apple's on-device speech engine (SpeechAnalyzer, the same technology behind Live Captions), saves each transcript when you stop, and summarizes it with Apple Intelligence.

- **Free and private:** speech recognition and summaries run on the device. No audio or text leaves it.
- **Works offline** once the speech model for your language has downloaded (this happens once, automatically).
- **Long sessions:** no time limits, and it keeps going when you plug in or remove headphones.

## Requirements

- iPhone/iPad with **iOS 26** or later, or a Mac with **macOS 26** or later.
- A Mac with **Xcode 26** or later (free from the Mac App Store) to install the app.
- Summaries by Apple Intelligence need a device that supports it (iPhone 15 Pro or newer, or a Mac with an M-series chip) with Apple Intelligence turned on. Other devices get a basic summary.

## Install it

### 1. Get the code onto your Mac
Download and unzip: <https://github.com/talljamz2/Transcriber/archive/refs/heads/apple-app.zip>

### 2. Open the project
Open the `apple` folder and double-click **LiveCaptions.xcodeproj**. Xcode opens.

### 3. Sign it with your Apple ID (one time)
1. Xcode menu **Settings… → Apple Accounts** (or **Accounts**) → **+** → sign in with your Apple ID.
2. In the left sidebar, click the blue **LiveCaptions** project icon, then the **LiveCaptions** target → **Signing & Capabilities** tab.
3. Under **Team**, pick your name (Personal Team).
4. If Xcode says the bundle identifier is unavailable, change **Bundle Identifier** to something unique, e.g. `com.yourname.LiveCaptions`.

### 4a. Run it on your Mac
In the toolbar at the top, pick **My Mac** as the destination and press **▶ (Run)**.

### 4b. Install it on your iPhone
1. Connect the iPhone with a cable and unlock it. Tap **Trust** if asked.
2. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode** and restart when asked (one time).
3. In Xcode's toolbar, pick your iPhone as the destination and press **▶ (Run)**.
4. The first time, iOS blocks the app: go to **Settings → General → VPN & Device Management**, tap your Apple ID and **Trust**. Then open the app.

With a free Apple ID, apps installed this way stop opening after **7 days**; just connect the phone and press Run again. A paid Apple Developer account ($99/year) extends this to a year and allows TestFlight installs without a cable.

## Using it

- **Live:** press **Start** (or the space bar on Mac). Words appear as they're spoken; grey text is still being recognized. **A− / A+** change the size.
- **Everything is saved automatically** when you press **Stop**. In the background, Apple Intelligence sorts each session into a category (Conversation, Meeting, Voice note, Phone call, Lecture / talk, TV & media), writes a summary, and pulls out **actions**: yours, other people's, and unclear ones you can mark **Mine** or **Not mine**.
- **Saved** is grouped by day. Each day has a **Daily summary**: a short recap, every action from the day, and each session in one line. TV & media is left out.
- **Tidy up:** sessions that look like TV or media are flagged for review. Delete them or keep them; nothing is ever deleted automatically. TV & media sessions aren't summarized unless you tap **Summarize**.
- **Evening reminder** (Settings): one notification on days with a summary to read or sessions to tidy up.
- **Settings:** spoken language, font and text size, keep the screen on, reminder time.

Only text is stored, never audio: an hour of conversation takes about 70 KB.

The first time you use a language, the app downloads Apple's speech model for it (a short wait, one time only).

**Microphone:** on iPhone a connected headset, AirPods or other Bluetooth headset mic is used automatically. On Mac, choose the input in **System Settings → Sound → Input**.

## Project layout

| File | Purpose |
| --- | --- |
| `LiveCaptionsApp.swift` | App entry point and tabs |
| `LiveTranscriber.swift` | Microphone + SpeechAnalyzer live transcription |
| `CaptionController.swift` | Recording, saving, background processing queue, daily summaries |
| `Summarizer.swift` | Apple Intelligence categories, summaries and actions (Foundation Models), with a basic fallback |
| `Models.swift` | Saved session data (SwiftData) and formatting |
| `EveningReminder.swift` | The evening notification |
| `LiveView.swift`, `HistoryView.swift`, `DayView.swift`, `TidyUpView.swift`, `ActionsList.swift`, `SettingsView.swift` | Screens |
