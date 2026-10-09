# yewclic

A little AI buddy that lives next to your cursor on macOS. Hold **⌃⌥ (Control + Option)**, ask a question out loud, let go. Yewclic looks at your screen, answers out loud, and can fly over to point at the button you need.

It's an open re-build of the idea behind [Clicky](https://www.heyclicky.com/) ([MIT source](https://github.com/farzaa/clicky)), with one big difference: **you pick the brain.**

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

- **Listening:** Apple Speech (free, on-device) or any Whisper-style `/audio/transcriptions` API (Groq, OpenAI, a local whisper server).
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
| `Overlay/BuddyOverlay.swift` | The click-through cursor buddy and speech bubble |
| `UI/SettingsView.swift` | Settings window |

## Not (yet) included

Clicky's paid "agent" mode (doing tasks for you), dictation into other apps, multi-monitor screenshots in one request, and a rebindable shortcut.

## License

MIT. Inspired by Clicky by Farza Majeed (MIT).
