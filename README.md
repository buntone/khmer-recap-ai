# 🎬 Khmer Recap AI Studio (សម្រាយរឿង AI)

> **Zero-PC Android Application**: An end-to-end automated mobile studio that converts raw Chinese recap videos into high-quality, dubbed Khmer movie recaps using Google Gemini 1.5 Multimodal AI, Khmer Natural Voiceover (Prasith & Sreymom), and FFmpeg hardware-accelerated audio ducking.

---

## 🌟 Key Features

1. **One-Tap Workflow**:
   - Pick raw Chinese recap video (`.mp4`, `.mkv`, `.mov`).
   - Preview resolution & duration.
   - Choose Khmer voice: **Prasith (Male)** or **Sreymom (Female)**.
   - Fine-tune audio ducking (lower original Chinese track from 0% to 100%).
   - Hit **🚀 បង្កើតវីដេអូសម្រាយរឿង (Generate Recap)**.

2. **4-Stage Real-Time Pipeline**:
   - **Stage 1: Analyzing Video (កំពុងវិភាគវីដេអូ)** — Probes resolution/duration and extracts audio track for lightweight upload.
   - **Stage 2: Writing Khmer Script (កំពុងសរសេរអត្ថបទសម្រាយ)** — Gemini 1.5 Flash generates storytelling narration with engaging, smooth phrasing (រៀបរាប់ដំណើររឿងបែបសម្រាយរឿងកុន មិនរឹង មិនកកស្ទះ) with 100% Khmer translation guarantee and API quota multi-key failover.
   - **Stage 3: Generating Khmer Voice (កំពុងបំប្លែងសំឡេង)** — Multi-speaker Khmer TTS with Auto-Dialogue switching (Prasith & Sreymom), smart digit/tag suppression, and cinematic inner monologue reverb/echo effect (`aecho`).
   - **Stage 4: Merging Audio & Video (កំពុងបញ្ចូលសំឡេងក្នុងវីដេអូ)** — FFmpeg hardware-accelerated sidechain ducking, auto-compression, and automated temporary file cleanup (`cleanTempFiles`).

3. **Cinematic Inner Monologue Audio Effect (សំឡេងក្នុងចិត្ត)**:
   - Recognizes thought/monologue tags like `(ក្នុងចិត្ត)`, `(សំឡេងក្នុងចិត្ត)`, `[គិតក្នុងចិត្ត]` and strips them completely from spoken audio.
   - Automatically applies spatial reverb & echo (`aecho` filter + acoustic EQ) so the voice sounds like an authentic character's inner mental voice.

4. **Review & Post-Production Studio**:
   - In-app preview player with instant audio-video sync.
   - Collapsible & editable Khmer script: make quick edits and press **🔄 Re-generate Voice & Mux**.
   - One-tap actions:
     - 💾 **Save to Gallery** (`Movies/KhmerRecap`)
     - 🎧 **Export Audio** (`.mp3` directly to Downloads)
     - 📄 **Export Script** (`.txt / .srt`)
     - 📲 **Share Video** to TikTok, Facebook Reels, Telegram, or YouTube Shorts.

---

## 🚀 Zero-PC Build (GitHub Actions)

You don't need Android Studio or a high-end PC installed locally to generate the `.apk`. Everything is configured in `.github/workflows/build_apk.yml`.

### How to get your `app-release.apk`:
1. Push this code to your GitHub repository:
   ```bash
   git init
   git add .
   git commit -m "feat: Khmer Recap AI mobile studio"
   git branch -M main
   git remote add origin https://github.com/<YOUR_USERNAME>/<YOUR_REPO_NAME>.git
   git push -u origin main
   ```
2. Navigate to your GitHub repository in your browser.
3. Click on the **Actions** tab.
4. You will see the **Build Android Release APK** workflow running automatically.
5. Once complete (takes ~3-5 minutes), click on the workflow run and download the **`app-release`** artifact containing `app-release.apk`.
6. Transfer and install the `.apk` directly onto your Android device!

---

## ⚙️ Configuration (In-App Settings)

Tap the **Settings (⚙️)** icon in the top right corner of the app:

- **Gemini API Key**: Obtain a free key from [Google AI Studio](https://aistudio.google.com).
- **Khmer TTS Endpoint**: Defaults to `https://api.khmervoice.ai/v1/tts` or enter your custom Khmer TTS REST server endpoint.
- **Voice Mapping**:
  - `Prasith (Male)`: `prasith_male_natural_v2`
  - `Sreymom (Female)`: `sreymom_female_expressive_v2`

---

## 📂 Project Architecture

```
├── .github/workflows/
│   └── build_apk.yml                # CI/CD: Automated APK release builder
├── android/
│   ├── app/
│   │   ├── build.gradle             # MinSdkVersion 24+, NDK packaging & release config
│   │   └── src/main/AndroidManifest.xml # Storage & Internet permissions
│   ├── build.gradle
│   └── settings.gradle
├── lib/
│   ├── main.dart                    # Material3 dark theme with Google Fonts Kantumruy Pro
│   ├── screens/
│   │   ├── home_screen.dart         # One-Tap Studio & Real-time Progress Tracker
│   │   ├── result_screen.dart       # Video preview, script editing & export studio
│   │   └── settings_screen.dart     # Gemini & Khmer TTS config
│   └── services/
│       ├── gemini_recap_service.dart# Multimodal video analysis & narrative storytelling
│       ├── khmer_tts_service.dart   # Prasith / Sreymom voice synthesis
│       ├── ffmpeg_service.dart      # Audio ducking, mixing & media exporting
│       └── settings_service.dart    # Persistent SharedPreferences storage
└── pubspec.yaml                     # Dependencies & assets configuration
```
