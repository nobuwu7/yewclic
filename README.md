# yewclic

A little AI buddy that lives next to your cursor on macOS. Hold **⌃⌥ (Control + Option)**, ask a question out loud, let go. Yewclic looks at your screen, answers out loud, and can fly over to point at the button you need.

It combines the best of [Clicky](https://www.heyclicky.com/) ([MIT source](https://github.com/farzaa/clicky)) with one big difference: **you pick the brain.**

### What came from Clicky


- The curved "swoop" flight to whatever it's pointing at 
- Multi-monitor screenshots, with `[POINT:x,y:label:screen2]` to point on another display
- The listen-only event tap for a reliable ⌃⌥ shortcut
- Its well-tuned spoken-answer prompt (casual, short, ends by "planting a seed")
- AssemblyAI live streaming transcription
- A dark menu bar panel and the "always show buddy" option

### What yewclic adds

- Switch between 12 AI providers, including Claude Code, Ollama and other local models
- No server to run: keys live in your Keychain and calls go straight to the provider
- Free/offline voice options, plus Whisper-style APIs and ElevenLabs
- On-device OCR so text-only models can still see and point
- Up to three pointing steps in order
- One-command build, no Xcode project

## Providers

Switch any time from the menu bar icon → **Brain**, or in Settings.

| Provider | How it connects | Needs |
|---|---|---|
| Claude (Anthropic API) | Messages API, streaming | API key |
| **Claude Code** | runs `claude -p` locally | Claude Code installed and logged in (uses your Pro/Max plan, no key) |
| OpenAI | OpenAI-compatible | API key |
| Google Gemini | Gemini's OpenAI-compatible endpoint | API key |
| Mistral | OpenAI-compatible | API key |
| DeepSeek | OpenAI-compatible, text-only → screen sent as OCR text | API key |
| Qwen (DashScope) | OpenAI-compatible | API key |
| **Ollama** (local) | `http://localhost:11434/v1` | `ollama pull qwen2.5vl` (or any model) |
| LM Studio (local) | `http://localhost:1234/v1` | local server running |
| OpenRouter, Groq | OpenAI-compatible | API key |
| Custom | any `/chat/completions` server (vLLM, llama.cpp, LiteLLM…) | — |

The default model names are only starting points. Use **Fetch models** in Settings to pick from what your account actually has, and **Test connection** to check it works.

**Text-only models still work.** Turn off "Model can see images" and Yewclic reads the screen's text on-device (Apple Vision OCR) and sends that with positions, so the model can still answer and point.

## Voice

- **Listening:** Apple Speech (free, on-device), AssemblyAI live streaming (fastest), or any Whisper-style `/audio/transcriptions` API (Groq, OpenAI, a local whisper server).
- **Talking:** the built-in macOS voice (free, offline), any OpenAI-compatible `/audio/speech` API, ElevenLabs, or off.

A fully local, free setup: **Ollama + Apple Speech + macOS voice.**

## Install

1. Download `Yewclic-vX.Y.Z.zip` from [Releases](https://github.com/nobuwu7/yewclic/releases) and unzip it.
2. Drag **Yewclic.app** into Applications.
3. The app isn't notarised by Apple yet, so the first time, **right-click it → Open → Open**. (Or run `xattr -dr com.apple.quarantine /Applications/Yewclic.app`.)

Needs macOS 14.2 or later.

## First launch

A short welcome guide walks you through everything:

1. **Welcome:** what yewclic does and what it can see.
2. **Brain:** pick *Free and private* (Ollama / LM Studio), *My Claude plan* (Claude Code) or *An API key*, then **Test it**.
3. **Permissions:** Screen Recording, Accessibility, Microphone (and Speech Recognition for Apple's engine), each with the reason. If macOS needs a restart to apply one, the guide offers it and picks up where you left off.
4. **Voice:** read answers out loud or not, choose a voice, and play a sample.
5. **Try it:** hold ⌃⌥, ask something, let go. The guide shows it listening, thinking and answering.

You can skip it and come back any time from **Yewclic → Welcome Guide…**.

## Build from source

Needs the Swift toolchain (Xcode or the Command Line Tools).

```bash
scripts/build-app.sh
open build/Yewclic.app
```

```bash
scripts/test.sh
```

To see every guide step without clicking through, render them to PNGs (light and dark):

```bash
build/Yewclic.app/Contents/MacOS/Yewclic --snapshot-onboarding ~/Desktop/yewclic-guide
```

> Ad-hoc signed builds get a new signature every build, so macOS may forget the permissions. To avoid that, sign with a stable identity:
> `SIGN_IDENTITY="Apple Development: you@example.com" scripts/build-app.sh`

API keys are stored in your Mac's Keychain, never in files.

### Releasing

Bump the version, push a tag, and GitHub builds a **draft** release with the zip attached:

```bash
git tag v0.2.0
git push origin v0.2.0
```

Release notes come from `release-notes/<tag>.md` when that file exists.

## How it works

```
hold ⌃⌥ ──► mic on + screenshot of the display under the cursor
release ──► transcribe ──► provider (screenshot or OCR text + question + recent history)
         ──► streamed reply in a bubble ──► spoken aloud
         ──► [POINT:x,y:label] tags ──► buddy flies to those spots
```

| File | What it does |
|---|---|
| `Companion.swift` | The push-to-talk → answer → speak → point loop |
| `Providers/ProviderCatalog.swift` | List of providers and their defaults. Add new OpenAI-compatible vendors here |
| `Providers/*Provider.swift` | Anthropic, OpenAI-compatible, and Claude Code CLI clients |
| `Screen/ScreenCapture.swift` | ScreenCaptureKit screenshot + pixel → screen coordinate mapping |
| `Screen/ScreenTextReader.swift` | On-device OCR for text-only models |
| `Voice/` | Shortcut monitor, speech-to-text engines, text-to-speech engines |
| `Overlay/BuddyOverlay.swift` | The click-through cursor buddy, flight animation and speech bubble |
| `UI/CompanionPanelView.swift` | The panel under the menu bar icon |
| `UI/Onboarding/` | The first-launch welcome guide (flow logic, screens, window) |
| `UI/SettingsView.swift` | Settings window |

## Not (yet) included

Clicky's paid "agent" mode (doing tasks for you), dictation into other apps, Clicky's Claude-only precise pointing (Computer Use), its onboarding video, analytics and auto-updates, and a rebindable shortcut.

## License

MIT. Portions adapted from [Clicky](https://github.com/farzaa/clicky) by Farza Majeed, MIT licensed (see `LICENSE`).
