# 🦞 虾BB / ClawBB

**Hold Globe key. Speak. Text appears.** Native macOS voice-to-text powered by Google Gemini.

Pure Swift | 280KB binary | Zero dependencies | Bilingual (EN/ZH)

<!-- ![Demo](demo.gif) -->

---

## Features

- **Globe key hotkey** — hold to record, release to transcribe + auto-paste
- **Dual-engine transcription** — Gemini Live API for real-time preview, REST API for final accuracy
- **Bilingual** — seamless Chinese/English mixed transcription, always Simplified Chinese output
- **HUD overlay** — floating, draggable status window with live preview
- **Menu bar app** — lives in your menu bar, no Dock icon
- **Sound effects** — audio feedback for record start/stop/done/error
- **Auto-paste** — transcribed text is copied to clipboard and pasted at cursor
- **Daily quota** — 500 free transcriptions per day
- **Launch at login** — optional auto-start via launchd
- **Tiny footprint** — ~280KB compiled binary, no Python, no Node, no Electron

## Quick Install

```bash
git clone https://github.com/dyz2102/clawbb.git ~/Tools/xiabb
cd ~/Tools/xiabb && bash install.sh
```

## Build from Source

Requirements: macOS 14.0+, Apple Silicon, Xcode Command Line Tools.

```bash
# Install Xcode CLT if needed
xcode-select --install

# Build and install
cd ~/Tools/xiabb/native
bash build.sh

# Run
open /Applications/XiaBB.app
```

## Setup

### 1. Get a Gemini API Key (free)

Visit [aistudio.google.com/apikey](https://aistudio.google.com/apikey) and create a key.

Save it:
```bash
echo 'YOUR_KEY_HERE' > ~/Tools/xiabb/.api-key
```

Or set the environment variable `GEMINI_API_KEY`.

### 2. Grant Accessibility Permission

XiaBB uses `CGEventTap` to detect the Globe (fn) key. This requires Accessibility permission.

**System Settings > Privacy & Security > Accessibility** — add **Terminal.app** (or your terminal emulator).

XiaBB will automatically relaunch through Terminal to inherit this permission. The Terminal window is minimized automatically.

### 3. Grant Microphone Permission

The system will prompt you on first recording. Click **Allow**.

## Usage

| Action | Result |
|--------|--------|
| **Hold Globe key** | Start recording (you'll hear a tone and see the HUD) |
| **Release Globe key** | Stop recording, transcribe, auto-paste at cursor |
| **Click HUD** | Copy last transcription to clipboard |
| **Drag HUD** | Reposition the overlay |
| **Menu bar icon** | Access settings, language, permissions, quit |

Tips:
- Speak naturally. The model handles punctuation automatically.
- Mix languages freely — Chinese and English in the same sentence works.
- Recordings shorter than the minimum duration (default 2s) are discarded to prevent accidental taps.

## Configuration

Settings are stored in `~/Tools/xiabb/.config.json`:

```json
{
  "lang": "zh",
  "min_duration": 2.0,
  "hud_x": 500,
  "hud_y": 900,
  "onboarded": true
}
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `lang` | `"en"` or `"zh"` | `"zh"` | UI language |
| `min_duration` | float | `2.0` | Minimum recording seconds (shorter = discarded) |
| `hud_x` / `hud_y` | float | center | HUD overlay position (or drag to reposition) |

Environment variables:
- `GEMINI_API_KEY` — API key (overrides `.api-key` file)
- `XIABB_MODEL` — REST model name (default: `gemini-2.5-flash`)

## How It Works

```
Globe key held ──> Audio Engine (16kHz mono PCM)
                      │
                      ├──> Gemini Live API (WebSocket)
                      │    Real-time transcription preview in HUD
                      │
Globe key released ──> WAV encoding
                      │
                      └──> Gemini REST API (gemini-2.5-flash)
                           Final accurate transcription
                           │
                           ├──> Copy to clipboard
                           ├──> Simulate Cmd+V paste
                           └──> Show result in HUD
```

The dual-engine approach gives you real-time feedback while recording (via the Live API's `inputAudioTranscription`) and a polished final result (via the REST API with the full audio).

## FAQ

**Q: The Globe key doesn't work.**
A: Ensure Terminal.app has Accessibility permission in System Settings. XiaBB inherits Terminal's permission. If you changed terminals, add your new terminal app too.

**Q: I see "Too short" in the logs.**
A: Quick taps under 2 seconds are ignored. Hold the Globe key longer while speaking. Adjust `min_duration` in config if needed.

**Q: Traditional Chinese appears in output.**
A: XiaBB applies `Traditional-Simplified` conversion automatically. If you still see traditional characters, file an issue.

**Q: Can I use a different model?**
A: Set `XIABB_MODEL=gemini-2.0-flash` (or any Gemini model that supports audio) before launching.

**Q: How do I check logs?**
A: `tail -f ~/Library/Logs/XiaBB.log`

**Q: How do I uninstall?**
A:
```bash
rm -rf /Applications/XiaBB.app
rm -f ~/Library/LaunchAgents/com.xiabb.plist
rm -f ~/Tools/xiabb/.api-key ~/Tools/xiabb/.config.json ~/Tools/xiabb/.usage.json
```

## 中文说明

虾BB 是一个原生 macOS 语音转文字工具，使用 Google Gemini API。

- 按住 Globe (fn) 键说话，松开自动转写并粘贴
- 支持中英文混合识别，输出简体中文
- 纯 Swift 编写，280KB 体积，无任何依赖
- 每天 500 次免费额度

安装：
```bash
cd ~/Tools/xiabb && bash install.sh
```

首次使用需要在 系统设置 > 隐私与安全 > 辅助功能 中添加终端应用的权限。

## Contributing

Issues and PRs welcome. The codebase is a single `main.swift` file — read it top to bottom in 10 minutes.

## License

MIT
