# 🦞 虾BB / ClawBB

**按住 Globe 键，说话，文字出现。就这么简单。**

**Hold Globe. Speak. Text appears. That's it.**

Native macOS voice-to-text | Powered by Google Gemini | 280KB | Zero dependencies

https://github.com/dyz2102/clawbb/raw/main/clawbb-intro.mp4

---

## Why ClawBB?

Every voice typing tool falls apart when you mix Chinese and English. Siri gives up. Whisper garbles it. Paid tools want $15/month.

ClawBB is the lobster that refuses to let go. Free, open source, and actually good at bilingual transcription.

> 虾BB = 瞎BB ("talking nonsense") — because the best ideas sound crazy until you say them out loud. 🦞

---

## Features

| | Feature | Description |
|---|---|---|
| 🌐 | **Globe key** | Hold to record, release to transcribe + auto-paste |
| 🔴 | **Live preview** | See text appear as you speak (Gemini Live API) |
| 🌏 | **Bilingual** | Chinese + English in the same sentence, no problem |
| 📋 | **Auto-paste** | Text goes straight to your cursor via Cmd+V |
| 🦞 | **HUD overlay** | Draggable floating window with wave animation |
| ⚡ | **280KB** | Pure Swift, no Electron, no Python, no Node |
| 🆓 | **Free forever** | 250 transcriptions/day on Gemini free tier |
| 🎵 | **Sound feedback** | Tones for start, stop, done, error |

## Quick Install

```bash
git clone https://github.com/dyz2102/clawbb.git
cd clawbb && bash install.sh
```

## Build from Source

Requires: macOS 14+, Apple Silicon, Xcode Command Line Tools.

```bash
xcode-select --install  # if needed
cd clawbb/native && bash build.sh
open /Applications/XiaBB.app
```

## Setup (3 steps)

### 1. Gemini API Key (free)

Get one at [aistudio.google.com/apikey](https://aistudio.google.com/apikey), then:

```bash
echo 'YOUR_KEY' > .api-key
```

Or set `GEMINI_API_KEY` env var. Or configure via the menu bar.

### 2. Accessibility Permission

ClawBB detects the Globe key via `CGEventTap`, which requires Accessibility permission.

**System Settings > Privacy & Security > Accessibility** — add **Terminal.app**.

ClawBB auto-relaunches through Terminal to inherit this permission (the window minimizes automatically).

### 3. Microphone

System will prompt on first recording. Click Allow.

## Usage

| Action | What happens |
|--------|-------------|
| **Hold 🌐 Globe** | Recording starts, HUD appears with live preview |
| **Release 🌐 Globe** | Transcription finalizes, text pastes at cursor |
| **Click HUD** | Copy last result to clipboard |
| **Drag HUD** | Move it anywhere |
| **Tap < 2s** | Ignored (prevents accidental triggers) |

Mix languages freely. The model handles punctuation. Simplified Chinese output.

## How It Works

```
Hold Globe ─── AVAudioEngine (16kHz mono) ──┬──> Gemini Live WebSocket
                                             │   (real-time preview in HUD)
                                             │
Release    ─── WAV encode ──────────────────>└──> Gemini REST API
                                                  (final transcription)
                                                       │
                                              clipboard + Cmd+V paste
```

## Config

`~/.config.json` in the install directory:

| Key | Default | What it does |
|-----|---------|-------------|
| `lang` | `"zh"` | UI language (`"en"` or `"zh"`) |
| `min_duration` | `2.0` | Minimum recording seconds |
| `hud_x` / `hud_y` | center | HUD position (or just drag it) |

Env vars: `GEMINI_API_KEY`, `XIABB_MODEL` (default: `gemini-2.5-flash`)

## FAQ

**Globe key doesn't work?** Add Terminal.app to Accessibility in System Settings.

**"Too short" in logs?** Hold Globe longer. Adjust `min_duration` in config.

**Traditional Chinese?** Should auto-convert. File an issue if not.

**Different model?** Set `XIABB_MODEL=gemini-2.0-flash` before launching.

**Logs?** `tail -f ~/Library/Logs/XiaBB.log`

**Uninstall?** `bash uninstall.sh`

---

## 中文说明

虾BB（ClawBB）是一个免费开源的 macOS 语音转文字工具。

按住键盘左下角的 🌐 Globe 键说话，松开后文字自动出现在光标处。中英文随便混着说，它都能搞定。

**为什么叫虾BB？** 因为虾BB谐音"瞎BB"——最好的想法，说出来的时候都像在瞎说。🦞

特点：
- 纯 Swift 原生应用，280KB，零依赖
- Google Gemini 免费额度，每天 250 次
- 实时预览（边说边看文字）
- 自动粘贴到光标位置
- HUD 悬浮窗 + 龙虾麦克风动画

```bash
git clone https://github.com/dyz2102/clawbb.git
cd clawbb && bash install.sh
```

---

## Contributing

Issues and PRs welcome. The entire app is one `main.swift` — read it in 10 minutes.

## License

MIT
