<div align="center">

# 🦞 虾BB

### 按住 Globe 键，说话，文字出现。

**免费开源的 macOS 语音转文字工具，由 Google Gemini 驱动**

*Hold Globe. Speak. Text appears. Free & open-source macOS voice-to-text.*

[![Swift](https://img.shields.io/badge/Swift-6.2-orange?logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Binary Size](https://img.shields.io/badge/体积-280KB-blue)]()
[![Gemini](https://img.shields.io/badge/Powered%20by-Gemini%20API-4285F4?logo=google&logoColor=white)](https://ai.google.dev/)

<br>

<img src="xiabb-demo.gif" width="720" alt="虾BB 演示">

<br>

*中英文混着说，它都能搞定。*

</div>

---

## 为什么做虾BB？

市面上所有语音输入工具，中英文混着说都会翻车。Siri 直接放弃，Whisper 乱码，付费工具要 $15/月。

虾BB 是那只死不松手的龙虾。🦞

> **虾BB = 瞎BB** —— 最好的想法，说出来的时候都像在瞎说。

### 为什么不用 Whisper？

Whisper 是 ASR 模型 —— 只"听"不"懂"。没有标点、经常错别字、中英切换容易乱。

Gemini 是大语言模型 —— 它**理解**你在说什么，再输出文字。标点完美，语义纠错，中英混搭自然。

| | Whisper | Gemini (虾BB) |
|---|---|---|
| 标点符号 | 没有 | 完美 |
| 错别字 | 多 | 少 |
| 中英混搭 | 一般 | 很好 |
| 模型大小 | 3GB | 0（云端） |
| 单次最长 | 容易出错 | 9.5 小时 |

---

## 功能

<table>
<tr>
<td width="50%">

**🌐 Globe 键一键录音**
按住录音，松开转写+自动粘贴。一个键搞定。

**🔴 实时预览**
边说边看文字出现。Gemini Live API 流式传输。

**🌏 真正的中英混输**
"帮我 schedule a meeting" → 完美识别，不需要切换语言。

</td>
<td width="50%">

**📋 自动粘贴**
文字直接出现在光标位置，任何 app 都能用。

**⚡ 280KB 极致轻量**
纯 Swift 原生。没有 Electron，没有 Python，没有 Node。

**🎙 超长录音支持**
单次最长 9.5 小时。实测几分钟连续录音完全没问题，MacWhisper 长音频经常出错。

**🆓 完全免费**
Google Gemini 免费额度，每天 250 次，够用。

</td>
</tr>
</table>

**彩蛋：** 龙虾麦克风 HUD 悬浮窗 + 声波动画 + 识别成功弹出 "BB!" 🦞

---

## 安装

**方式一：直接下载（推荐）**

去 [Releases](https://github.com/dyz2102/xiabb/releases) 下载 `XiaBB-v1.0.0-macOS-arm64.zip`，解压，拖到 Applications，双击打开。

已经过 Apple 公证（Notarized），不会弹 Gatekeeper 警告。

**方式二：从源码编译**

```bash
git clone https://github.com/dyz2102/xiabb.git
cd xiabb && bash install.sh
```

<details>
<summary><b>手动编译</b></summary>

```bash
xcode-select --install  # 需要 Xcode 命令行工具
cd xiabb/native && bash build.sh
open /Applications/XiaBB.app
```

要求 macOS 14+，Apple Silicon。

</details>

---

## 设置（3 步）

| 步骤 | 操作 |
|------|------|
| **1. 获取 API Key** | 免费申请：[aistudio.google.com/apikey](https://aistudio.google.com/apikey) → 保存到 `.api-key` 文件或设置环境变量 `GEMINI_API_KEY` |
| **2. 辅助功能权限** | 系统设置 → 隐私与安全性 → 辅助功能 → 添加 **Terminal.app** |
| **3. 麦克风权限** | 首次录音时系统会弹窗，点允许 |

---

## 使用方法

| 操作 | 效果 |
|------|------|
| **按住 🌐 Globe 键** | 开始录音，HUD 显示实时预览 |
| **松开 🌐 Globe 键** | 转写完成 → 复制 → 粘贴到光标位置 |
| **按住不到 2 秒** | 忽略（防误触） |
| **点击 HUD** | 复制上次结果 |
| **拖动 HUD** | 移动到任意位置 |

说话就行，不用管标点。中英文随便混着说。

---

## 技术架构

```
按住 🌐 ─── AVAudioEngine (16kHz) ──┬──> Gemini Live WebSocket
                                     │   (流式预览 → HUD 实时显示)
                                     │
松开 🌐 ─── WAV 编码 ──────────────>└──> Gemini REST API
                                          (最终准确转写)
                                               │
                                      📋 剪贴板 + ⌘V 粘贴
```

双引擎架构：说话时用 Live API 做实时预览（低延迟），松手后用 REST API 做最终转写（高准确率）。

<details>
<summary><b>配置选项</b></summary>

`.config.json`：

| 键 | 默认值 | 说明 |
|-----|---------|------|
| `lang` | `"zh"` | 界面语言（`"en"` 或 `"zh"`） |
| `min_duration` | `2.0` | 最短录音秒数（更短的会被忽略） |
| `hud_x`/`hud_y` | 屏幕居中 | HUD 位置（或直接拖动） |
| `theme` | `"lobster"` | 皮肤主题 |

环境变量：`GEMINI_API_KEY`，`XIABB_MODEL`（默认 `gemini-2.5-flash`）

</details>

<details>
<summary><b>常见问题</b></summary>

**Globe 键没反应？** → 在系统设置 → 辅助功能里添加 Terminal.app 权限。

**日志显示 "Too short"？** → 按住 Globe 键久一点，或在配置里降低 `min_duration`。

**出现繁体字？** → 自动转换简体。如果还有问题请开 Issue。

**查看日志？** → `tail -f ~/Library/Logs/XiaBB.log`

**卸载？** → `bash uninstall.sh`

</details>

---

## English

XiaBB (虾BB) is a free, open-source macOS voice-to-text tool powered by Google Gemini.

Hold the Globe key to speak, release to transcribe. Works seamlessly with mixed Chinese and English. Pure Swift, 280KB binary, zero dependencies.

- **Download:** [Releases](https://github.com/dyz2102/xiabb/releases)
- **API Key:** Free from [Google AI Studio](https://aistudio.google.com/apikey)
- **Requires:** macOS 14+, Apple Silicon

---

<div align="center">

**用 🦞 做的 by [dyz2102](https://github.com/dyz2102)**

MIT License · [xiabb.lol](https://xiabb.lol)

</div>
