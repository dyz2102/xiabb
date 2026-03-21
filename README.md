<div align="center">

# 🦞 虾BB / ClawBB

### Hold Globe. Speak. Text appears.

**Free, open-source macOS voice-to-text powered by Google Gemini**

按住 Globe 键，说话，文字自动出现。就这么简单。

[![Swift](https://img.shields.io/badge/Swift-6.2-orange?logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Binary Size](https://img.shields.io/badge/Size-280KB-blue)]()
[![Gemini](https://img.shields.io/badge/Powered%20by-Gemini%20API-4285F4?logo=google&logoColor=white)](https://ai.google.dev/)

<br>

<img src="xiabb-demo.gif" width="720" alt="XiaBB Demo">

<br>

*中英文混着说，它都能搞定。Mix Chinese and English freely.*

</div>

---

## Why ClawBB?

Every voice typing tool falls apart when you mix Chinese and English. Siri gives up. Whisper garbles it. Paid tools want $15/month.

ClawBB is the lobster that refuses to let go. 🦞

> **虾BB = 瞎BB** ("talking nonsense") — because the best ideas sound crazy until you say them out loud.

---

## Features

<table>
<tr>
<td width="50%">

**🌐 Globe Key Hotkey**
Hold to record, release to transcribe. One key does everything.

**🔴 Real-time Preview**
See text streaming as you speak. Powered by Gemini Live API.

**🌏 Truly Bilingual**
"帮我 schedule a meeting" → works perfectly. No language switching needed.

</td>
<td width="50%">

**📋 Auto-Paste**
Text appears at your cursor instantly. No Cmd+V needed.

**⚡ 280KB Binary**
Pure Swift. No Electron. No Python. No Node. Just works.

**🎙 Up to 9.5 Hours Per Recording**
Gemini handles massive audio files. Tested with multi-minute recordings — no cutoffs. MacWhisper chokes on long audio; ClawBB doesn't.

**🆓 Free Forever**
250 transcriptions/day on Google's free tier. No account needed.

</td>
</tr>
</table>

**Bonus:** Floating HUD with lobster-mic branding, wave animations, and a "BB!" that pops out when transcription succeeds. 🦞

---

## Install

```bash
git clone https://github.com/dyz2102/xiabb.git
cd xiabb && bash install.sh
```

<details>
<summary><b>Build from source</b></summary>

```bash
xcode-select --install  # Xcode CLT if needed
cd xiabb/native && bash build.sh
open /Applications/XiaBB.app
```

Requires macOS 14+, Apple Silicon.

</details>

---

## Setup

| Step | What to do |
|------|-----------|
| **1. API Key** | Free from [aistudio.google.com/apikey](https://aistudio.google.com/apikey) → save to `.api-key` or set `GEMINI_API_KEY` |
| **2. Accessibility** | System Settings → Privacy → Accessibility → enable **Terminal.app** |
| **3. Microphone** | System prompts on first use → click Allow |

---

## Usage

| Action | Result |
|--------|--------|
| **Hold 🌐 Globe** | 🔴 Recording starts, HUD shows live preview |
| **Release 🌐 Globe** | Text finalizes → copies → pastes at cursor |
| **Tap < 2s** | Ignored (no accidental triggers) |
| **Click HUD** | Copy last result |
| **Drag HUD** | Move it anywhere |

---

## Architecture

```
Hold 🌐 ─── AVAudioEngine (16kHz) ──┬──> Gemini Live WebSocket
                                     │   (streaming preview → HUD)
                                     │
Release  ─── WAV encode ────────────>└──> Gemini REST API
                                          (final transcription)
                                               │
                                      📋 clipboard + ⌘V paste
```

<details>
<summary><b>Config options</b></summary>

`.config.json` in install directory:

| Key | Default | Description |
|-----|---------|-------------|
| `lang` | `"zh"` | `"en"` or `"zh"` |
| `min_duration` | `2.0` | Min recording seconds |
| `hud_x`/`hud_y` | center | HUD position |

Env vars: `GEMINI_API_KEY`, `XIABB_MODEL` (default `gemini-2.5-flash`)

</details>

<details>
<summary><b>FAQ</b></summary>

**Globe key not working?** → Add Terminal.app to Accessibility permission.

**"Too short" in logs?** → Hold Globe longer, or lower `min_duration`.

**Traditional Chinese?** → Auto-converts. File an issue if not.

**Logs?** → `tail -f ~/Library/Logs/XiaBB.log`

**Uninstall?** → `bash uninstall.sh`

</details>

---

<div align="center">

## 中文说明

虾BB（ClawBB）是免费开源的 macOS 语音转文字工具。

按住 🌐 Globe 键说话，松开后文字自动粘贴到光标位置。

中英文随便混着说，它都能搞定。

**为什么叫虾BB？** 谐音"瞎BB"——最好的想法说出来都像在瞎说 🦞

纯 Swift · 280KB · Google Gemini 免费额度 · 每天 250 次

---

**Built with 🦞 by [dyz2102](https://github.com/dyz2102)**

MIT License

</div>
