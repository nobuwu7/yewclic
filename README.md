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

## Build and run

Needs macOS 14.2+ and the Swift toolchain (Xcode or Command Line Tools).

```bash
scripts/build-app.sh
open build/Yewclic.app
```

On first launch Settings opens on **Permissions**. Grant Screen Recording, Accessibility (for the global shortcut), Microphone and Speech Recognition, then restart the app.

> Ad-hoc signed builds get a new signature every build, so macOS may forget the permissions. To avoid that, sign with a stable identity:
> `SIGN_IDENTITY="Apple Development: you@example.com" scripts/build-app.sh`

API keys are stored in your Mac's Keychain, never in files.

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
| `UI/SettingsView.swift` | Settings window |

## Not (yet) included

Clicky's paid "agent" mode (doing tasks for you), dictation into other apps, Clicky's Claude-only precise pointing (Computer Use), its onboarding video, analytics and auto-updates, and a rebindable shortcut.

## Contributors

| | Who | Role |
|---|---|---|
| <img src="https://github.com/nobuwu7.png" width="40" alt=""> | **[Aubrey Yeong (@nobuwu7)](https://github.com/nobuwu7)** | Creator and maintainer: idea, direction, design choices and testing |
| <img src="https://github.com/anthropics.png" width="40" alt=""> | **[Claude](https://claude.com/claude-code)** (Anthropic) | Co-developer: wrote and reviewed code with Aubrey in Claude Code, and runs the weekly Clicky update check |

yewclic builds on [Clicky](https://github.com/farzaa/clicky) by [Farza (@farzaa)](https://github.com/farzaa), whose original commits are kept in this repo's history.

## License

MIT. Portions adapted from [Clicky](https://github.com/farzaa/clicky) by Farza Majeed, MIT licensed (see `LICENSE`).
