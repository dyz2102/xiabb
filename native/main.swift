// XiaBB (虾BB) — Native macOS Voice-to-Text powered by Google Gemini
// Hold Globe (fn) key to speak. Real-time preview + accurate final transcription.
// Pure Swift, no external dependencies.

import AppKit
import AVFoundation
import CoreGraphics
import Foundation

// MARK: - Debug Logging

let logFileURL: URL = {
    let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/XiaBB.log")
    // Truncate on launch (keep last log only)
    try? "".write(to: url, atomically: true, encoding: .utf8)
    return url
}()

func log(_ msg: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(ts)] \(msg)\n"
    fputs(line, stderr)
    // Also write to log file for debugging when launched via Finder
    if let fh = try? FileHandle(forWritingTo: logFileURL) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    }
}

// MARK: - Constants

let APP_NAME = "XiaBB"
let APP_ID = "com.xiabb"
let SAMPLE_RATE: Double = 16000
let CHANNELS: UInt32 = 1
let DAILY_FREE_LIMIT = 250 // Gemini 2.5 Flash free tier: 250 RPD
let MODEL_REST = ProcessInfo.processInfo.environment["XIABB_MODEL"] ?? "gemini-2.5-flash"
let MODEL_LIVE = "gemini-2.5-flash-native-audio-latest"
let FN_FLAG: UInt64 = 0x800000 // NSEventModifierFlagFunction

let WS_URL_BASE = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

let PROMPT = """
Transcribe this audio exactly as spoken, with proper punctuation.
- ALL Chinese MUST be Simplified (简体中文). Never output Traditional Chinese.
- Preserve original language per word (Chinese stays Chinese, English stays English).
- Do NOT translate. Output as a SINGLE paragraph. No line breaks.
- Output ONLY the transcribed text.
"""

// MARK: - Paths

let scriptDir: URL = {
    // Resources dir in .app bundle, fallback to ~/Tools/xiabb/
    if let resourcePath = Bundle.main.resourceURL {
        return resourcePath
    }
    return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Tools/xiabb")
}()

let dataDir: URL = {
    // Config/usage data directory
    return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Tools/xiabb")
}()

// MARK: - API Key

func loadAPIKey() -> String {
    if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
        return envKey
    }
    let keyFile = dataDir.appendingPathComponent(".api-key")
    if let data = try? String(contentsOf: keyFile, encoding: .utf8) {
        return data.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return ""
}

var apiKey = loadAPIKey()

// MARK: - T2S (Traditional → Simplified Chinese)

func t2s(_ text: String) -> String {
    let mutable = NSMutableString(string: text)
    CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
    return mutable as String
}

// MARK: - Config

let configFile = dataDir.appendingPathComponent(".config.json")

func loadConfig() -> [String: Any] {
    guard let data = try? Data(contentsOf: configFile),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

func saveConfig(_ updates: [String: Any]) {
    var existing = loadConfig()
    for (k, v) in updates { existing[k] = v }
    if let data = try? JSONSerialization.data(withJSONObject: existing) {
        try? data.write(to: configFile)
    }
}

// MARK: - Themes / Skins

struct HUDTheme {
    let name: String
    let bgRed: CGFloat, bgGreen: CGFloat, bgBlue: CGFloat, bgAlpha: CGFloat
    let cornerRadius: CGFloat
    let textColor: NSColor
    let recordingColor: NSColor
    let successColor: NSColor
    let barColor: NSColor  // wave bar color during recording
    let fontSize: CGFloat
}

// Theme registry — designed for easy extension. Add new themes here.
// Future: load from .cbskin files (ZIP with theme.json + assets)
let themeList: [(id: String, theme: HUDTheme)] = [
    ("lobster", HUDTheme(
        name: "🦞 Lobster Red",
        bgRed: 0.12, bgGreen: 0.06, bgBlue: 0.06, bgAlpha: 0.93,
        cornerRadius: 12,
        textColor: .white,
        recordingColor: NSColor(calibratedRed: 0.94, green: 0.27, blue: 0.27, alpha: 1),
        successColor: NSColor(calibratedRed: 0.2, green: 0.83, blue: 0.45, alpha: 1),
        barColor: NSColor(calibratedRed: 0.94, green: 0.27, blue: 0.27, alpha: 1),
        fontSize: 13
    )),
    ("chill", HUDTheme(
        name: "🌿 Chill Green",
        bgRed: 0.06, bgGreen: 0.12, bgBlue: 0.08, bgAlpha: 0.92,
        cornerRadius: 16,
        textColor: NSColor(calibratedRed: 0.85, green: 1.0, blue: 0.9, alpha: 1),
        recordingColor: NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.5, alpha: 1),
        successColor: NSColor(calibratedRed: 0.5, green: 1.0, blue: 0.7, alpha: 1),
        barColor: NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.5, alpha: 1),
        fontSize: 13
    )),
    ("ocean", HUDTheme(
        name: "🌊 Ocean Blue",
        bgRed: 0.04, bgGreen: 0.08, bgBlue: 0.18, bgAlpha: 0.93,
        cornerRadius: 14,
        textColor: NSColor(calibratedRed: 0.75, green: 0.92, blue: 1.0, alpha: 1),
        recordingColor: NSColor(calibratedRed: 0.25, green: 0.65, blue: 1.0, alpha: 1),
        successColor: NSColor(calibratedRed: 0.3, green: 1.0, blue: 0.75, alpha: 1),
        barColor: NSColor(calibratedRed: 0.25, green: 0.65, blue: 1.0, alpha: 1),
        fontSize: 13
    )),
    ("sunset", HUDTheme(
        name: "🌅 Sunset Orange",
        bgRed: 0.16, bgGreen: 0.08, bgBlue: 0.04, bgAlpha: 0.93,
        cornerRadius: 14,
        textColor: NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.82, alpha: 1),
        recordingColor: NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.15, alpha: 1),
        successColor: NSColor(calibratedRed: 0.4, green: 0.9, blue: 0.5, alpha: 1),
        barColor: NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.15, alpha: 1),
        fontSize: 13
    )),
]

let themes: [String: HUDTheme] = Dictionary(uniqueKeysWithValues: themeList.map { ($0.id, $0.theme) })

var currentTheme: HUDTheme = {
    let name = loadConfig()["theme"] as? String ?? "lobster"
    return themes[name] ?? themes["lobster"]!
}()

// MARK: - i18n

let strings: [String: [String: String]] = [
    "en": [
        "idle": "Idle",
        "recording": "Recording...",
        "transcribing": "Transcribing...",
        "listening": "Listening...",
        "finalizing": "Finalizing...",
        "copied": "Copied!",
        "left": "left",
        "start": "Start Recording",
        "stop": "Stop",
        "hotkey": "Hold Globe key to record",
        "configure_api": "Configure Gemini API Key...",
        "launch_login": "Launch at Login",
        "language": "Language",
        "quit": "Quit XiaBB",
        "daily_limit": "Daily limit reached",
    ],
    "zh": [
        "idle": "待命",
        "recording": "录音中...",
        "transcribing": "识别中...",
        "listening": "聆听中...",
        "finalizing": "处理中...",
        "copied": "已复制!",
        "left": "剩余",
        "start": "开始录音",
        "stop": "停止",
        "hotkey": "按住 Globe 键录音",
        "configure_api": "配置 Gemini API Key...",
        "launch_login": "开机自动启动",
        "language": "语言 / Language",
        "quit": "退出 虾BB",
        "daily_limit": "今日额度已用完",
    ],
]

var currentLang: String = loadConfig()["lang"] as? String ?? "zh"

func L(_ key: String) -> String {
    return strings[currentLang]?[key] ?? strings["en"]?[key] ?? key
}

// MARK: - Usage Tracker

class UsageTracker {
    private let file = dataDir.appendingPathComponent(".usage.json")
    private var date: String
    private(set) var count: Int

    init() {
        let today = Self.today()
        if let data = try? Data(contentsOf: file),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let d = json["date"] as? String, d == today,
           let c = json["count"] as? Int {
            date = d
            count = c
        } else {
            date = today
            count = 0
        }
    }

    static func today() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    var remaining: Int { max(0, DAILY_FREE_LIMIT - count) }

    func statusLine() -> String { "\(count)/\(DAILY_FREE_LIMIT) (\(remaining) left)" }

    @discardableResult
    func increment() -> Int {
        let today = Self.today()
        if date != today { date = today; count = 0 }
        count += 1
        save()
        return count
    }

    private func save() {
        let json: [String: Any] = ["date": date, "count": count]
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            try? data.write(to: file)
        }
    }
}

let usage = UsageTracker()

// MARK: - Sound Effects

func generateTone(frequencies: [(Double, Double)], duration: Double, attack: Double = 0.008, release: Double = 0.04, amplitude: Double = 0.05) -> Data {
    let sampleRate = 44100.0
    let numSamples = Int(sampleRate * duration)
    var samples = [Int16](repeating: 0, count: numSamples)

    for i in 0..<numSamples {
        let t = Double(i) / sampleRate
        var value = 0.0
        for (freq, amp) in frequencies {
            value += amp * sin(2.0 * .pi * freq * t)
        }
        // Envelope
        let attackSamples = Int(sampleRate * attack)
        let releaseSamples = Int(sampleRate * release)
        var env = 1.0
        if i < attackSamples {
            env = 0.5 * (1.0 - cos(.pi * Double(i) / Double(attackSamples)))
        } else if i > numSamples - releaseSamples {
            let ri = i - (numSamples - releaseSamples)
            env = 0.5 * (1.0 + cos(.pi * Double(ri) / Double(releaseSamples)))
        }
        samples[i] = Int16(clamping: Int(value * env * amplitude * 32767.0))
    }

    return makeWAVData(samples: samples, sampleRate: Int(sampleRate))
}

func makeWAVData(samples: [Int16], sampleRate: Int, channels: Int = 1) -> Data {
    var data = Data()
    let dataSize = samples.count * 2
    let fileSize = 36 + dataSize

    // RIFF header
    data.append(contentsOf: "RIFF".utf8)
    data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
    data.append(contentsOf: "WAVE".utf8)

    // fmt chunk
    data.append(contentsOf: "fmt ".utf8)
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
    data.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * channels * 2).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(channels * 2).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // bits per sample

    // data chunk
    data.append(contentsOf: "data".utf8)
    data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
    for s in samples {
        data.append(contentsOf: withUnsafeBytes(of: s.littleEndian) { Array($0) })
    }
    return data
}

func sfxStart() -> Data {
    // Two ascending tones (D5 → A5)
    let tone1 = generateTone(frequencies: [(587, 1.0), (1174, 0.2)], duration: 0.07, amplitude: 0.05)
    let tone2 = generateTone(frequencies: [(880, 1.0), (1760, 0.2)], duration: 0.07, amplitude: 0.06)
    // Combine with gap
    let sr = 44100
    let gap = [Int16](repeating: 0, count: Int(Double(sr) * 0.04))
    // Extract PCM from tone1 and tone2, combine, re-wrap
    return combineSounds([tone1, makeWAVData(samples: gap, sampleRate: sr), tone2])
}

func sfxStop() -> Data {
    generateTone(frequencies: [(880, 0.7), (698, 0.5)], duration: 0.12, amplitude: 0.05)
}

func sfxDone() -> Data {
    let tone1 = generateTone(frequencies: [(784, 1.0), (2352, 0.15)], duration: 0.10, amplitude: 0.05)
    let tone2 = generateTone(frequencies: [(1047, 1.0), (3141, 0.12)], duration: 0.18, amplitude: 0.06)
    return combineSounds([tone1, tone2])
}

func sfxError() -> Data {
    let sr = 44100
    let tone = generateTone(frequencies: [(330, 1.0)], duration: 0.08, amplitude: 0.05)
    let gap = [Int16](repeating: 0, count: Int(Double(sr) * 0.06))
    return combineSounds([tone, makeWAVData(samples: gap, sampleRate: sr), tone])
}

func combineSounds(_ wavDatas: [Data]) -> Data {
    // Extract PCM from each WAV, concatenate, re-wrap
    var allSamples = [Int16]()
    for wav in wavDatas {
        // Skip 44-byte WAV header
        if wav.count > 44 {
            let pcmData = wav.subdata(in: 44..<wav.count)
            pcmData.withUnsafeBytes { ptr in
                let bound = ptr.bindMemory(to: Int16.self)
                allSamples.append(contentsOf: bound)
            }
        }
    }
    return makeWAVData(samples: allSamples, sampleRate: 44100)
}

var currentSound: NSSound?

func playSound(_ wavData: Data) {
    DispatchQueue.global(qos: .userInteractive).async {
        let sound = NSSound(data: wavData)
        sound?.play()
        currentSound = sound // prevent dealloc
    }
}

// MARK: - Audio Recording

class AudioRecorder {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private(set) var frames: [Data] = []
    private let lock = NSLock()
    var isRecording = false
    private var configObserver: NSObjectProtocol?

    func start() {
        guard !isRecording else { return }
        frames = []
        isRecording = true

        let engine = AVAudioEngine()
        self.engine = engine

        // Watch for audio config changes (mic disconnected/changed)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            log("⚠️ Audio config changed (mic disconnected?)")
            guard let self = self, self.isRecording else { return }
            // Try to restart engine with new config
            do {
                try self.engine?.start()
                log("  Audio engine restarted after config change")
            } catch {
                log("  ❌ Audio engine restart failed: \(error)")
                self.isRecording = false
            }
        }

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        // Validate hardware format
        guard hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 else {
            log("❌ Invalid audio input format (no mic?): \(hwFormat)")
            isRecording = false
            cleanup()
            return
        }

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: SAMPLE_RATE, channels: 1, interleaved: true) else {
            log("❌ Cannot create target audio format")
            isRecording = false
            cleanup()
            return
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            log("❌ Cannot create audio converter")
            isRecording = false
            cleanup()
            return
        }
        self.converter = converter

        let chunkSize: AVAudioFrameCount = AVAudioFrameCount(hwFormat.sampleRate * 0.1)

        inputNode.installTap(onBus: 0, bufferSize: chunkSize, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }

            let ratio = SAMPLE_RATE / hwFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if let error = error {
                log("⚠️ Audio convert error: \(error.localizedDescription)")
                return
            }

            if status == .haveData || status == .endOfStream, outputBuffer.frameLength > 0 {
                let byteCount = Int(outputBuffer.frameLength) * Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
                let data = Data(bytes: outputBuffer.int16ChannelData![0], count: byteCount)
                self.lock.lock()
                self.frames.append(data)
                self.lock.unlock()
            }
        }

        engine.prepare()
        do {
            try engine.start()
            log("🎙 Audio engine started (hw: \(hwFormat.sampleRate)Hz → 16000Hz)")
        } catch {
            log("❌ Audio engine start failed: \(error)")
            isRecording = false
            cleanup()
        }
    }

    private func cleanup() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = nil
    }

    func stop() -> [Data] {
        isRecording = false
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        cleanup()
        lock.lock()
        let result = frames
        lock.unlock()
        print("🎙 Recording stopped (\(result.count) chunks)")
        return result
    }

    func getFramesSoFar() -> [Data] {
        lock.lock()
        let result = frames
        lock.unlock()
        return result
    }
}

// MARK: - WAV Encoder (for Gemini API)

func encodeToWAV(frames: [Data]) -> (Data, Double) {
    var allBytes = Data()
    for f in frames { allBytes.append(f) }
    let numSamples = allBytes.count / 2
    let duration = Double(numSamples) / SAMPLE_RATE

    var wav = Data()
    let dataSize = allBytes.count
    let fileSize = 36 + dataSize

    wav.append(contentsOf: "RIFF".utf8)
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
    wav.append(contentsOf: "WAVE".utf8)
    wav.append(contentsOf: "fmt ".utf8)
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(Int(SAMPLE_RATE)).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(Int(SAMPLE_RATE) * 2).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
    wav.append(contentsOf: "data".utf8)
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
    wav.append(allBytes)

    return (wav, duration)
}

// MARK: - Gemini REST API

func transcribeREST(wavData: Data, completion: @escaping (Result<String, Error>) -> Void) {
    let b64 = wavData.base64EncodedString()
    guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(MODEL_REST):generateContent") else {
        completion(.failure(NSError(domain: "XiaBB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
    request.timeoutInterval = 30

    let body: [String: Any] = [
        "contents": [["parts": [
            ["text": PROMPT],
            ["inline_data": ["mime_type": "audio/wav", "data": b64]]
        ]]],
        "generationConfig": ["temperature": 0.0, "maxOutputTokens": 4096]
    ]

    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            log("[REST] Network error: \(error)")
            completion(.failure(error))
            return
        }
        guard let data = data else {
            completion(.failure(NSError(domain: "XiaBB", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
            return
        }

        // Log the raw response for debugging
        if let httpResp = response as? HTTPURLResponse {
            log("[REST] HTTP \(httpResp.statusCode), \(data.count) bytes")
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let raw = String(data: data.prefix(500), encoding: .utf8) ?? "binary"
                log("[REST] Not a JSON object: \(raw)")
                completion(.failure(NSError(domain: "XiaBB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }

            // Check for error response
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                log("[REST] API error: \(message)")
                completion(.failure(NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: message])))
                return
            }

            // Parse candidates
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                // Check if this is a valid response with no text (e.g. silence)
                if let candidates = json["candidates"] as? [[String: Any]],
                   let content = candidates.first?["content"] as? [String: Any],
                   content["parts"] == nil {
                    log("[REST] No text in response — likely silence or unintelligible audio")
                    completion(.failure(NSError(domain: "XiaBB", code: -2, userInfo: [NSLocalizedDescriptionKey: "No speech detected"])))
                    return
                }
                let raw = String(data: data.prefix(500), encoding: .utf8) ?? "binary"
                log("[REST] Unexpected structure: \(raw)")
                completion(.failure(NSError(domain: "XiaBB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])))
                return
            }

            let cleaned = t2s(text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " "))
            log("[REST] ✅ Transcribed: \(cleaned.prefix(100))")
            completion(.success(cleaned))
        } catch {
            log("[REST] JSON parse error: \(error)")
            completion(.failure(error))
        }
    }.resume()
}

// MARK: - Gemini Live WebSocket

class LiveSession: NSObject, URLSessionWebSocketDelegate {
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var liveText = ""
    private var onTextUpdate: ((String) -> Void)?
    private var isActive = false
    private var chunksSent = 0

    func start(onTextUpdate: @escaping (String) -> Void) {
        self.onTextUpdate = onTextUpdate
        self.liveText = ""
        self.isActive = true
        self.chunksSent = 0

        let urlStr = "\(WS_URL_BASE)?key=\(apiKey)"
        guard let url = URL(string: urlStr) else {
            log("[live] Invalid WebSocket URL")
            return
        }

        log("[live] Connecting to WebSocket...")
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        // Send setup message
        let setup: [String: Any] = [
            "setup": [
                "model": "models/\(MODEL_LIVE)",
                "generationConfig": ["responseModalities": ["AUDIO"]],
                "systemInstruction": ["parts": [["text": "Listen and acknowledge briefly."]]],
                "inputAudioTranscription": [:] as [String: Any],
            ]
        ]

        guard let setupData = try? JSONSerialization.data(withJSONObject: setup),
              let setupStr = String(data: setupData, encoding: .utf8) else {
            log("[live] Failed to serialize setup message")
            return
        }

        webSocket?.send(.string(setupStr)) { [weak self] error in
            if let error = error {
                log("[live] Setup send error: \(error)")
                return
            }
            log("[live] Setup message sent, waiting for response...")
            self?.receiveSetupResponse()
        }
    }

    // URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        log("[live] WebSocket opened (protocol: \(`protocol` ?? "none"))")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        log("[live] WebSocket closed (code: \(closeCode.rawValue))")
    }

    private func receiveSetupResponse() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let text):
                    if text.contains("setupComplete") {
                        log("[live] ✅ Setup complete (string)")
                        self?.startReceiving()
                    } else {
                        log("[live] Unexpected setup response: \(text.prefix(300))")
                        self?.stop()
                    }
                case .data(let data):
                    // Log raw bytes to understand format
                    let hex = data.prefix(60).map { String(format: "%02x", $0) }.joined(separator: " ")
                    log("[live] Setup binary (\(data.count) bytes): \(hex)")
                    if let text = String(data: data, encoding: .utf8) {
                        log("[live] Setup as UTF-8: \(text.prefix(200))")
                        if text.contains("setupComplete") {
                            log("[live] ✅ Setup complete (from binary)")
                            self?.startReceiving()
                        } else {
                            // Maybe it's JSON with setup info, continue anyway
                            log("[live] ⚠️ No setupComplete in binary, starting anyway")
                            self?.startReceiving()
                        }
                    } else {
                        // Likely protobuf — start receiving anyway
                        log("[live] ⚠️ Non-UTF8 binary, assuming setup complete")
                        self?.startReceiving()
                    }
                @unknown default:
                    break
                }
            case .failure(let error):
                log("[live] Setup receive error: \(error)")
            }
        }
    }

    private var msgCount = 0

    private func startReceiving() {
        guard isActive else { return }
        webSocket?.receive { [weak self] result in
            guard let self = self, self.isActive else { return }
            switch result {
            case .success(let msg):
                self.msgCount += 1
                switch msg {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    // Try UTF-8 first
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    } else if self.msgCount <= 10 {
                        let hex = data.prefix(40).map { String(format: "%02x", $0) }.joined(separator: " ")
                        log("[live] Binary msg #\(self.msgCount): \(data.count) bytes — \(hex)...")
                    }
                @unknown default:
                    break
                }
                self.startReceiving() // Continue receiving
            case .failure(let error):
                if self.isActive {
                    log("[live] Receive error: \(error)")
                }
            }
        }
    }

    private func handleMessage(_ jsonStr: String) {
        // Log first few messages to debug
        if msgCount <= 5 {
            log("[live] Msg #\(msgCount): \(jsonStr.prefix(300))")
        }

        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if msgCount <= 5 {
                log("[live] Failed to parse JSON for msg #\(msgCount)")
            }
            return
        }

        // Check for inputTranscription in serverContent
        if let sc = json["serverContent"] as? [String: Any] {
            if let it = sc["inputTranscription"] as? [String: Any],
               let chunk = it["text"] as? String, !chunk.isEmpty {
                liveText += chunk
                let display = t2s(liveText)
                log("[live] 📝 Chunk: \"\(chunk)\" → total: \"\(display.suffix(60))\"")
                DispatchQueue.main.async { [weak self] in
                    self?.onTextUpdate?(display)
                }
            }

            // Also check for modelTurn (the model's audio response) — we can ignore these
            if sc["modelTurn"] != nil {
                if msgCount <= 5 {
                    log("[live] Got modelTurn (ignored)")
                }
            }

            // Check turnComplete
            if let tc = sc["turnComplete"] as? Bool, tc {
                log("[live] Turn complete")
            }
        }
    }

    var currentText: String { return t2s(liveText) }

    func sendAudio(_ pcmData: Data) {
        guard isActive, let ws = webSocket else { return }
        let b64 = pcmData.base64EncodedString()
        let msg: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [[
                    "mimeType": "audio/pcm;rate=16000",
                    "data": b64
                ]]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let str = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(str)) { [weak self] error in
            if let error = error {
                log("[live] Audio send error: \(error)")
            } else {
                self?.chunksSent += 1
            }
        }
    }

    func stop() {
        let sent = chunksSent
        isActive = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        log("[live] Stopped — \(liveText.count) chars transcribed, \(sent) chunks sent")
    }
}

// MARK: - Permissions Window

// i18n for setup window
let setupStrings: [String: [String: String]] = [
    "en": [
        "title": "XiaBB Setup",
        "subtitle": "Grant these permissions for XiaBB to work properly.",
        "acc_title": "Accessibility",
        "acc_detail": "For Globe key detection",
        "mic_title": "Microphone",
        "mic_detail": "For voice recording",
        "key_title": "Google Gemini API Key",
        "key_detail_ok": "Configured",
        "key_detail_no": "Free at aistudio.google.com/apikey",
        "grant": "Grant",
        "done": "All set! Hold Globe key to start.",
        "perm_menu": "Permissions...",
    ],
    "zh": [
        "title": "虾BB 设置",
        "subtitle": "虾BB 需要以下权限才能正常工作",
        "acc_title": "辅助功能",
        "acc_detail": "用于检测 Globe 按键",
        "mic_title": "麦克风",
        "mic_detail": "用于语音录制",
        "key_title": "Google Gemini API Key",
        "key_detail_ok": "已配置",
        "key_detail_no": "免费获取: aistudio.google.com/apikey",
        "grant": "授权",
        "done": "一切就绪! 按住 Globe 键开始录音",
        "perm_menu": "权限设置...",
    ],
]

func S(_ key: String) -> String {
    setupStrings[currentLang]?[key] ?? setupStrings["en"]?[key] ?? key
}

class PermissionsWindow {
    private var window: NSWindow?
    private var refreshTimer: Timer?

    func show() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w: CGFloat = 400, h: CGFloat = 340
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = currentLang == "zh" ? "虾BB — 设置" : "XiaBB — Setup"
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win

        buildContent(w: w, h: h)

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, let win = self.window, win.isVisible else {
                self?.refreshTimer?.invalidate()
                return
            }
            self.buildContent(w: win.frame.width, h: win.frame.height)
        }
    }

    private func buildContent(w: CGFloat, h: CGFloat) {
        let cv = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        window?.contentView = cv

        let pad: CGFloat = 28
        let rowH: CGFloat = 68

        // Subtitle only — window title bar already shows "XiaBB — Setup"
        let subtitle = NSTextField(labelWithString: S("subtitle"))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: pad, y: h - 30, width: w - pad * 2, height: 18)
        cv.addSubview(subtitle)

        // Permission rows
        let firstRowY = h - 48 - rowH
        let accOK = AXIsProcessTrusted()
        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let keyOK = !apiKey.isEmpty

        addRow(to: cv, y: firstRowY, w: w, pad: pad,
               title: S("acc_title"), detail: S("acc_detail"), granted: accOK) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        addRow(to: cv, y: firstRowY - rowH, w: w, pad: pad,
               title: S("mic_title"), detail: S("mic_detail"), granted: micOK) {
            if micStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            } else {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }

        let keyDetail = keyOK ? "\(S("key_detail_ok")) (\(apiKey.prefix(8))...)" : S("key_detail_no")
        addRow(to: cv, y: firstRowY - rowH * 2, w: w, pad: pad,
               title: S("key_title"), detail: keyDetail, granted: keyOK) {
            NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/apikey")!)
        }

        // Bottom status
        if accOK && micOK && keyOK {
            let done = NSTextField(labelWithString: S("done"))
            done.font = .systemFont(ofSize: 13, weight: .medium)
            done.textColor = .systemGreen
            done.frame = NSRect(x: pad, y: 30, width: w - pad * 2, height: 20)
            cv.addSubview(done)
            saveConfig(["onboarded": true])
        }

        let logLabel = NSTextField(labelWithString: "~/Library/Logs/XiaBB.log")
        logLabel.font = .systemFont(ofSize: 10)
        logLabel.textColor = .tertiaryLabelColor
        logLabel.frame = NSRect(x: pad, y: 10, width: w - pad * 2, height: 14)
        cv.addSubview(logLabel)
    }

    private func addRow(to parent: NSView, y: CGFloat, w: CGFloat, pad: CGFloat,
                        title: String, detail: String, granted: Bool, action: @escaping () -> Void) {
        let iconSize: CGFloat = 22
        let textX = pad + iconSize + 12
        let textW = w - textX - (granted ? pad : 100)

        // Icon
        let icon = NSTextField(labelWithString: granted ? "✅" : "⬜")
        icon.font = .systemFont(ofSize: 16)
        icon.frame = NSRect(x: pad, y: y + 18, width: iconSize, height: iconSize)
        parent.addSubview(icon)

        // Title
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.frame = NSRect(x: textX, y: y + 32, width: textW, height: 20)
        parent.addSubview(titleLabel)

        // Detail
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.frame = NSRect(x: textX, y: y + 14, width: textW, height: 16)
        parent.addSubview(detailLabel)

        // Grant button
        if !granted {
            let btn = PermissionButton(title: S("grant"), action: action)
            btn.frame = NSRect(x: w - pad - 72, y: y + 22, width: 64, height: 24)
            btn.bezelStyle = .rounded
            btn.font = .systemFont(ofSize: 12)
            parent.addSubview(btn)
        }

        // Separator
        let sep = NSBox(frame: NSRect(x: pad, y: y + 6, width: w - pad * 2, height: 1))
        sep.boxType = .separator
        parent.addSubview(sep)
    }
}

class PermissionButton: NSButton {
    private var onClick: (() -> Void)?

    convenience init(title: String, action: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        self.onClick = action
        self.target = self
        self.action = #selector(clicked)
    }

    @objc private func clicked() {
        onClick?()
    }
}

// MARK: - HUD Overlay

class HUDOverlay {
    private var window: NSWindow!
    private var label: NSTextField!
    private var dot: NSView!
    private var bg: NSView!
    private var bars: [NSView] = []  // 6 bars: [left0,left1,left2, right0,right1,right2]
    private var doneCheck: NSTextField!
    private var hudIcon: NSImageView!
    private var leftB: NSTextField!
    private var rightB: NSTextField!
    private var copyBtn: NSButton!
    var resultText = ""
    private var hideTimer: Timer?
    private var pulsePhase: Double = 0
    var isPulsing = false
    var isProcessing = false  // true when finalizing (after recording stops)

    init() {
        let cfg = loadConfig()
        let w: CGFloat = 280, h: CGFloat = 48
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let x = (cfg["hud_x"] as? CGFloat) ?? ((screen.width - w) / 2)
        let y = (cfg["hud_y"] as? CGFloat) ?? (screen.height - h - 60)

        window = NSWindow(contentRect: NSRect(x: x, y: y, width: w, height: h),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = true

        let cv = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        window.contentView = cv

        // Rounded background
        bg = HUDBackground(frame: NSRect(x: 0, y: 0, width: w, height: h))
        cv.addSubview(bg)

        // === Brand area: icon centered, wave bars on both sides, BB for success ===
        let iconH: CGFloat = 36
        let iconW: CGFloat = iconH * (14.0 / 36.0)
        let brandCenterX: CGFloat = 24 // center of the brand area
        let iconView = NSImageView(frame: NSRect(x: brandCenterX - iconW / 2, y: (h - iconH) / 2, width: iconW, height: iconH))
        let iconPaths = [
            Bundle.main.resourceURL?.appendingPathComponent("icon@2x.png"),
            dataDir.appendingPathComponent("icon@2x.png"),
            Bundle.main.resourceURL?.appendingPathComponent("icon.png"),
            dataDir.appendingPathComponent("icon.png"),
        ].compactMap { $0 }
        for path in iconPaths {
            if let img = NSImage(contentsOf: path) {
                img.isTemplate = true
                iconView.image = img
                break
            }
        }
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .systemRed
        cv.addSubview(iconView)
        hudIcon = iconView

        // Wave bars — 3 on each side, short→medium→long outward
        let barW: CGFloat = 2
        let barGap: CGFloat = 2.5
        let barHeights: [CGFloat] = [6, 10, 14]
        bars = []

        for i in 0..<3 {
            let x = brandCenterX - iconW / 2 - CGFloat(i + 1) * (barW + barGap)
            let bh = barHeights[i]
            let bar = NSView(frame: NSRect(x: x, y: (h - bh) / 2, width: barW, height: bh))
            bar.wantsLayer = true
            bar.layer?.cornerRadius = barW / 2
            bar.layer?.backgroundColor = NSColor.systemRed.cgColor
            cv.addSubview(bar)
            bars.append(bar)
        }
        for i in 0..<3 {
            let x = brandCenterX + iconW / 2 + CGFloat(i) * (barW + barGap) + barGap
            let bh = barHeights[i]
            let bar = NSView(frame: NSRect(x: x, y: (h - bh) / 2, width: barW, height: bh))
            bar.wantsLayer = true
            bar.layer?.cornerRadius = barW / 2
            bar.layer?.backgroundColor = NSColor.systemRed.cgColor
            cv.addSubview(bar)
            bars.append(bar)
        }

        // "BB!" — super tiny, top-right of mic icon, like a little speech bubble saying hi
        let bbFont = NSFont(name: "Futura-Bold", size: 7) ?? .systemFont(ofSize: 7, weight: .black)
        let iconRight = brandCenterX + iconW / 2
        let iconTop = (h + iconH) / 2

        rightB = NSTextField(labelWithString: "BB!")
        rightB.font = bbFont
        rightB.textColor = .systemGreen
        rightB.backgroundColor = .clear
        rightB.isBezeled = false
        rightB.isEditable = false
        rightB.frame = NSRect(x: iconRight - 3, y: iconTop - 5, width: 20, height: 9)
        rightB.wantsLayer = true
        rightB.layer?.setAffineTransform(CGAffineTransform(rotationAngle: -0.25))
        rightB.isHidden = true
        cv.addSubview(rightB)

        leftB = rightB // alias to avoid crash on old references

        dot = iconView

        // Text label — starts after the brand area
        label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 52, y: (h - 20) / 2, width: w - 86, height: 20)
        label.textColor = currentTheme.textColor
        label.font = .systemFont(ofSize: currentTheme.fontSize, weight: .medium)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingHead
        cv.addSubview(label)

        // Copy button — right side of HUD, hidden until result
        copyBtn = NSButton(frame: NSRect(x: w - 36, y: (h - 20) / 2, width: 28, height: 20))
        copyBtn.title = "📋"
        copyBtn.bezelStyle = .inline
        copyBtn.isBordered = false
        copyBtn.font = .systemFont(ofSize: 14)
        copyBtn.target = self
        copyBtn.action = #selector(handleClick)
        copyBtn.toolTip = "复制 / Copy"
        copyBtn.isHidden = true
        cv.addSubview(copyBtn)

        // Also keep whole-HUD click to copy
        let clickGR = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        window.contentView?.addGestureRecognizer(clickGR)
    }

    @objc private func handleClick() {
        guard !resultText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        label.stringValue = "✅ " + L("copied")
        copyBtn.title = "✅"
        // Hide after brief confirmation
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    private func resize(for text: String) {
        let minW: CGFloat = 200, maxW: CGFloat = 700, h: CGFloat = 48
        let w = min(maxW, max(minW, CGFloat(text.count) * 7.5 + 56))
        let f = window.frame
        let cx = f.origin.x + f.width / 2
        let newX = cx - w / 2
        window.setFrame(NSRect(x: newX, y: f.origin.y, width: w, height: h), display: true)
        bg.frame = NSRect(x: 0, y: 0, width: w, height: h)
        bg.needsDisplay = true
        label.frame = NSRect(x: 52, y: (h - 20) / 2, width: w - 86, height: 20)
        copyBtn.frame = NSRect(x: w - 36, y: (h - 20) / 2, width: 28, height: 20)
    }

    func show(text: String) {
        DispatchQueue.main.async { [self] in
            resultText = ""
            hideTimer?.invalidate()
            hideTimer = nil
            resize(for: text)
            label.stringValue = text
            isProcessing = false
            let rc = currentTheme.recordingColor
            bars.forEach { $0.isHidden = false; $0.layer?.backgroundColor = rc.cgColor }
            rightB.isHidden = true
            copyBtn.isHidden = true
            hudIcon.contentTintColor = rc
            window.alphaValue = 1.0
            window.orderFrontRegardless()
            isPulsing = true
            pulsePhase = 0
        }
    }

    func updateText(_ text: String) {
        DispatchQueue.main.async { [self] in
            resize(for: text)
            label.stringValue = text
        }
    }

    func hide() {
        DispatchQueue.main.async { [self] in
            isPulsing = false
            window.orderOut(nil)
        }
    }

    func showResult(_ text: String, isError: Bool = false) {
        DispatchQueue.main.async { [self] in
            let display = isError ? "Error: \(text.prefix(50))" : String(text.prefix(60)) + (text.count > 60 ? "..." : "")
            if !isError { resultText = text }
            resize(for: display)
            label.stringValue = display
            isPulsing = false
            isProcessing = false
            // Hide wave bars, show B B! for success (or hide for error)
            bars.forEach { $0.isHidden = true }
            if isError {
                rightB.isHidden = true
            } else {
                // BB! pops out at upper-right of icon with spring bounce
                rightB.textColor = currentTheme.successColor
                rightB.isHidden = false
                rightB.alphaValue = 0
                rightB.layer?.setAffineTransform(
                    CGAffineTransform(scaleX: 0.1, y: 0.1).rotated(by: -0.2))

                // Pop in
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    ctx.allowsImplicitAnimation = true
                    self.rightB.alphaValue = 1
                    self.rightB.layer?.setAffineTransform(
                        CGAffineTransform(scaleX: 1.3, y: 1.3).rotated(by: -0.2))
                }
                // Settle back
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.2
                        ctx.allowsImplicitAnimation = true
                        self.rightB.layer?.setAffineTransform(
                            CGAffineTransform(scaleX: 1, y: 1).rotated(by: -0.2))
                    }
                }
            }
            hudIcon.contentTintColor = isError ? currentTheme.recordingColor : currentTheme.successColor
            copyBtn.isHidden = isError  // show copy button on success
            dot.alphaValue = 1.0
            window.alphaValue = 1.0
            window.orderFrontRegardless()

            hideTimer?.invalidate()
            hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    func tickPulse() {
        guard isPulsing else { return }
        pulsePhase += 0.15
        let h: CGFloat = 48
        let maxHeights: [CGFloat] = [6, 10, 14, 6, 10, 14]

        if isProcessing {
            for (i, bar) in bars.enumerated() {
                let idx = i % 3
                let delay = Double(2 - idx) * 3.0
                let t = pulsePhase * 2.5 - delay
                let spike = max(0, sin(t)) * exp(-0.3 * max(0, t.truncatingRemainder(dividingBy: .pi * 2)))
                let maxH: CGFloat = maxHeights[i]
                let barH = max(2, maxH * CGFloat(spike))
                bar.frame = NSRect(x: bar.frame.origin.x, y: (h - barH) / 2, width: bar.frame.width, height: barH)
            }
        } else {
            for (i, bar) in bars.enumerated() {
                let idx = i % 3
                let delay = Double(idx) * 3.0
                let t = pulsePhase * 2.0 - delay
                let spike = max(0, sin(t)) * exp(-0.2 * max(0, t.truncatingRemainder(dividingBy: .pi * 2)))
                let maxH: CGFloat = maxHeights[i]
                let barH = max(2, maxH * CGFloat(spike))
                bar.frame = NSRect(x: bar.frame.origin.x, y: (h - barH) / 2, width: bar.frame.width, height: barH)
            }
        }
    }
}

class HUDBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let t = currentTheme
        let path = NSBezierPath(roundedRect: bounds, xRadius: t.cornerRadius, yRadius: t.cornerRadius)
        NSColor(calibratedRed: t.bgRed, green: t.bgGreen, blue: t.bgBlue, alpha: t.bgAlpha).setFill()
        path.fill()
    }
}

// MARK: - App Controller

class XiaBBApp: NSObject {
    var statusItem: NSStatusItem!
    var statusMenuItem: NSMenuItem!
    var toggleItem: NSMenuItem!
    var iconIdle: NSImage?
    var iconRec: NSImage?
    var menuItems: [String: NSMenuItem] = [:]

    let recorder = AudioRecorder()
    let permissionsWindow = PermissionsWindow()
    var liveSession: LiveSession?
    var hud: HUDOverlay!
    var liveSendTimer: Timer?
    var liveReconnectTimer: Timer?
    var liveAccumulatedText = "" // carries text across reconnections
    var lastSentChunk = 0
    var isTranscribing = false
    var tickCount = 0
    var idleTickCounter = 0

    var fnHeld = false
    var recordingStartTime: Date?
    var minRecordingDuration: TimeInterval = {
        // Configurable via .config.json "min_duration", default 2.0s
        return (loadConfig()["min_duration"] as? Double) ?? 2.0
    }()

    func setup() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        hud = HUDOverlay()

        // Load icons from bundle resources
        iconIdle = loadIcon(name: "icon", template: true)
        iconRec = loadIcon(name: "icon-red", template: false)
        if iconIdle == nil {
            iconIdle = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: APP_NAME)
            iconIdle?.isTemplate = true
        }
        if iconRec == nil { iconRec = iconIdle }

        // Menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = iconIdle
        statusItem.button?.toolTip = APP_NAME

        let menu = NSMenu()

        let title = NSMenuItem(title: "XiaBB 🦞", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        statusMenuItem = NSMenuItem(title: "\(L("idle")) — \(usage.statusLine())", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let hotkey = NSMenuItem(title: L("hotkey"), action: nil, keyEquivalent: "")
        hotkey.isEnabled = false
        menu.addItem(hotkey)
        menuItems["hotkey"] = hotkey

        menu.addItem(.separator())

        toggleItem = NSMenuItem(title: L("start"), action: #selector(toggleRecording), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menuItems["toggle"] = toggleItem

        menu.addItem(.separator())

        let apiItem = NSMenuItem(title: L("configure_api"), action: #selector(configureAPI), keyEquivalent: "")
        apiItem.target = self
        menu.addItem(apiItem)
        menuItems["api"] = apiItem

        let launchItem = NSMenuItem(title: L("launch_login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = isLaunchAtLogin() ? .on : .off
        menu.addItem(launchItem)
        menuItems["launch"] = launchItem

        menu.addItem(.separator())

        let langItem = NSMenuItem(title: L("language"), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()

        let enItem = NSMenuItem(title: "English", action: #selector(setLangEN), keyEquivalent: "")
        enItem.target = self
        enItem.state = currentLang == "en" ? .on : .off
        langMenu.addItem(enItem)
        menuItems["en"] = enItem

        let zhItem = NSMenuItem(title: "中文", action: #selector(setLangZH), keyEquivalent: "")
        zhItem.target = self
        zhItem.state = currentLang == "zh" ? .on : .off
        langMenu.addItem(zhItem)
        menuItems["zh"] = zhItem

        langItem.submenu = langMenu
        menu.addItem(langItem)
        menuItems["lang"] = langItem

        // Theme selector
        let themeItem = NSMenuItem(title: currentLang == "zh" ? "皮肤 / Theme" : "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for (id, theme) in themeList {
            let item = NSMenuItem(title: theme.name, action: #selector(switchTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = (loadConfig()["theme"] as? String ?? "lobster") == id ? .on : .off
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        // Permissions / Settings
        let permItem = NSMenuItem(title: S("perm_menu"), action: #selector(showPermissions), keyEquivalent: ",")
        permItem.target = self
        menu.addItem(permItem)
        menuItems["perm"] = permItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L("quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menuItems["quit"] = quitItem

        statusItem.menu = menu

        // UI tick timer — fast when active, slow when idle
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Skip ticks when idle to save CPU (only tick every 20th cycle = 1/sec)
            if !self.recorder.isRecording && !self.isTranscribing {
                self.idleTickCounter += 1
                if self.idleTickCounter % 20 != 0 { return }
            } else {
                self.idleTickCounter = 0
            }
            self.tick()
        }

        // Setup event tap for Globe key
        setupEventTap()

        log("🦞 \(APP_NAME) — Native Swift Voice-to-Text")
        log("   Model:  \(MODEL_REST) + \(MODEL_LIVE)")
        log("   Quota:  \(usage.statusLine())")
        log("   API key: \(apiKey.isEmpty ? "❌ MISSING" : "✅ set")")
        log("   Hotkey: 🌐 Globe (fn) — hold to speak")
        log("   HUD:    drag to reposition")
        log("✅ Ready!")

        // Auto-show permissions on first launch or if any permission is missing
        let hasSeenOnboarding = loadConfig()["onboarded"] as? Bool ?? false
        let missingPerms = !AXIsProcessTrusted()
            || AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            || apiKey.isEmpty
        if !hasSeenOnboarding || missingPerms {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.permissionsWindow.show()
                if !missingPerms { saveConfig(["onboarded": true]) }
            }
        }
    }

    func loadIcon(name: String, template: Bool) -> NSImage? {
        // Try bundle resources first, then ~/Tools/xiabb/
        let paths = [
            Bundle.main.resourceURL?.appendingPathComponent("\(name)@2x.png"),
            Bundle.main.resourceURL?.appendingPathComponent("\(name).png"),
            dataDir.appendingPathComponent("\(name)@2x.png"),
            dataDir.appendingPathComponent("\(name).png"),
        ].compactMap { $0 }

        for path in paths {
            if let img = NSImage(contentsOf: path) {
                let sz = img.size
                if sz.height > 0 {
                    let scale = 18.0 / sz.height
                    img.size = NSSize(width: sz.width * scale, height: 18)
                }
                img.isTemplate = template
                return img
            }
        }
        return nil
    }

    // MARK: - Event Tap

    func setupEventTap() {
        log("Setting up event tap...")

        // Check accessibility permission first
        let trusted = AXIsProcessTrusted()
        log("AXIsProcessTrusted: \(trusted)")

        if !trusted {
            log("⚠️ Not trusted for accessibility — prompting user")

            // Trigger system accessibility permission prompt
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)

            // Poll for permission grant (user may grant it in System Settings)
            DispatchQueue.global().async { [weak self] in
                for _ in 0..<300 { // check every 2s for up to 10 minutes
                    Thread.sleep(forTimeInterval: 2)
                    if AXIsProcessTrusted() {
                        log("✅ Accessibility granted! Setting up event tap...")
                        DispatchQueue.main.async {
                            self?.setupEventTapCore()
                        }
                        return
                    }
                }
                log("⏰ Timed out waiting for accessibility permission")
            }
            return
        }

        setupEventTapCore()
    }

    private var eventTap: CFMachPort?

    func setupEventTapCore() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        XiaBBApp.shared = self

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                // tapDisabledByTimeout — re-enable IMMEDIATELY
                if type == .tapDisabledByTimeout || type.rawValue == 0xFFFFFFFF {
                    if let tap = XiaBBApp.shared?.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        // Log on background to keep callback fast
                        DispatchQueue.global().async { log("⚠️ Event tap re-enabled (was disabled by timeout)") }
                    }
                    return Unmanaged.passUnretained(event)
                }
                // Handle Globe key — dispatch immediately, no work in callback
                XiaBBApp.shared?.handleFlagsChanged(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            log("❌ CGEvent.tapCreate returned nil (AXIsProcessTrusted=\(AXIsProcessTrusted()))")
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("✅ Event tap created and enabled")

        // Watchdog: re-enable event tap every 5 seconds in case it was silently disabled
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let tap = self?.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                log("⚠️ Watchdog re-enabled event tap")
            }
        }
    }

    static var shared: XiaBBApp?

    // MUST be extremely fast — macOS disables the tap if callback is slow
    func handleFlagsChanged(_ event: CGEvent) {
        let fnNow = (event.flags.rawValue & FN_FLAG) != 0
        if fnNow && !fnHeld {
            fnHeld = true
            // Dispatch immediately, don't log in the callback
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                log("🌐 Globe DOWN")
                self?.startRecording()
            }
        } else if !fnNow && fnHeld {
            fnHeld = false
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                log("🌐 Globe UP")
                self?.stopRecording()
            }
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard !recorder.isRecording else { return }
        log("🎙 Starting recording...")
        recordingStartTime = Date()

        playSound(sfxStart())

        let remaining = usage.remaining
        hud.show(text: L("listening"))

        recorder.start()
        lastSentChunk = 0

        // Start live session for real-time preview
        liveAccumulatedText = ""
        startNewLiveSession()

        // Timer to send audio chunks to live session
        DispatchQueue.main.async { [weak self] in
            self?.liveSendTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, self.recorder.isRecording else { return }
                let frames = self.recorder.getFramesSoFar()
                let newFrames = Array(frames.dropFirst(self.lastSentChunk))
                self.lastSentChunk = frames.count
                if !newFrames.isEmpty {
                    for frame in newFrames {
                        self.liveSession?.sendAudio(frame)
                    }
                }
            }

            // Reconnect live session every 15s to prevent degradation
            self?.liveReconnectTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
                guard let self = self, self.recorder.isRecording else { return }
                // Save text from current session before reconnecting
                if let currentSession = self.liveSession {
                    self.liveAccumulatedText = self.liveAccumulatedText + currentSession.currentText
                    log("[live] 🔄 Reconnecting (15s). Accumulated: \(self.liveAccumulatedText.count) chars")
                    currentSession.stop()
                }
                self.startNewLiveSession()
            }
        }
        log("🎙 Recording started")
    }

    func startNewLiveSession() {
        liveSession = LiveSession()
        liveSession?.start { [weak self] sessionText in
            guard let self = self else { return }
            // Combine accumulated text from previous sessions + current session text
            let fullText = self.liveAccumulatedText + sessionText
            let display = fullText.count > 60 ? String(fullText.suffix(60)) : fullText
            self.hud.updateText(display)
        }
    }

    func stopRecording() {
        guard recorder.isRecording else { return }

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        log("🎙 Stopping recording... (\(String(format: "%.2f", duration))s)")

        let frames = recorder.stop()

        DispatchQueue.main.async { [weak self] in
            self?.liveSendTimer?.invalidate()
            self?.liveSendTimer = nil
            self?.liveReconnectTimer?.invalidate()
            self?.liveReconnectTimer = nil
        }
        liveSession?.stop()
        liveSession = nil
        liveAccumulatedText = ""

        // Ignore accidental taps (< minRecordingDuration, default 2.0s)
        if duration < minRecordingDuration {
            log("  ⏭ Too short (\(String(format: "%.2f", duration))s < \(minRecordingDuration)s) — discarded")
            hud.hide()
            return
        }

        playSound(sfxStop())

        isTranscribing = true
        hud.isProcessing = true  // switch wave direction
        hud.updateText(L("finalizing"))

        guard !frames.isEmpty else {
            log("  No audio frames captured")
            isTranscribing = false
            hud.hide()
            return
        }

        guard usage.remaining > 0 else {
            isTranscribing = false
            playSound(sfxError())
            hud.showResult("\(L("daily_limit")) (\(DAILY_FREE_LIMIT))", isError: true)
            return
        }

        let (wavData, audioDuration) = encodeToWAV(frames: frames)
        log("  Audio: \(String(format: "%.1f", audioDuration))s, \(wavData.count) bytes, \(frames.count) chunks")

        transcribeREST(wavData: wavData) { [weak self] result in
            guard let self = self else { return }
            self.isTranscribing = false
            switch result {
            case .success(let text):
                let count = usage.increment()
                log("✅ [\(count)/\(DAILY_FREE_LIMIT)] \(text)")
                playSound(sfxDone())
                self.hud.showResult(text)
                self.copyAndPaste(text)
            case .failure(let error):
                log("❌ Transcription error: \(error.localizedDescription)")
                playSound(sfxError())
                self.hud.showResult(error.localizedDescription, isError: true)
            }
        }
    }

    func copyAndPaste(_ text: String) {
        // Copy to clipboard
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            let success = NSPasteboard.general.setString(text, forType: .string)
            log("📋 Clipboard: \(success ? "OK" : "FAILED")")

            // Simulate Cmd+V after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let src = CGEventSource(stateID: .hidSystemState)
                // V key = 0x09
                if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
                    keyDown.flags = .maskCommand
                    keyDown.post(tap: .cghidEventTap)
                    keyUp.flags = .maskCommand
                    keyUp.post(tap: .cghidEventTap)
                    log("📋 Cmd+V posted")
                } else {
                    log("❌ Failed to create CGEvent for Cmd+V")
                    // Fallback: use osascript
                    DispatchQueue.global().async {
                        let proc = Process()
                        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                        proc.arguments = ["-e", "tell application \"System Events\" to keystroke \"v\" using command down"]
                        try? proc.run()
                        proc.waitUntilExit()
                        log("📋 osascript Cmd+V fallback: exit \(proc.terminationStatus)")
                    }
                }
            }
        }
    }

    // MARK: - Menu Actions

    @objc func toggleRecording() {
        if recorder.isRecording {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.stopRecording()
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.startRecording()
            }
        }
    }

    @objc func configureAPI() {
        let script = """
        tell application "System Events"
          display dialog "\(L("configure_api"))\\n(Get one free at aistudio.google.com/apikey)" default answer "" with title "XiaBB API Config" buttons {"Cancel", "Save"} default button "Save"
          set theKey to text returned of result
          return theKey
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if proc.terminationStatus == 0 && !output.isEmpty {
            let keyFile = dataDir.appendingPathComponent(".api-key")
            try? output.write(to: keyFile, atomically: true, encoding: .utf8)
            apiKey = output
        }
    }

    @objc func toggleLaunchAtLogin() {
        let currently = isLaunchAtLogin()
        setLaunchAtLogin(!currently)
        menuItems["launch"]?.state = currently ? .off : .on
    }

    @objc func setLangEN() {
        currentLang = "en"
        saveConfig(["lang": "en"])
        refreshMenuTitles()
    }

    @objc func setLangZH() {
        currentLang = "zh"
        saveConfig(["lang": "zh"])
        refreshMenuTitles()
    }

    @objc func switchTheme(_ sender: NSMenuItem) {
        guard let themeId = sender.representedObject as? String,
              let theme = themes[themeId] else { return }
        currentTheme = theme
        saveConfig(["theme": themeId])
        // Update checkmarks
        if let themeMenu = sender.menu {
            for item in themeMenu.items { item.state = .off }
        }
        sender.state = .on
        // Rebuild HUD with new theme
        hud = HUDOverlay()
        log("🎨 Theme: \(theme.name)")
    }

    @objc func showPermissions() {
        permissionsWindow.show()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func refreshMenuTitles() {
        menuItems["hotkey"]?.title = L("hotkey")
        menuItems["toggle"]?.title = recorder.isRecording ? L("stop") : L("start")
        menuItems["api"]?.title = L("configure_api")
        menuItems["launch"]?.title = L("launch_login")
        menuItems["lang"]?.title = L("language")
        menuItems["quit"]?.title = L("quit")
        menuItems["en"]?.state = currentLang == "en" ? .on : .off
        menuItems["zh"]?.state = currentLang == "zh" ? .on : .off
    }

    // MARK: - Launch at Login

    let plistPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/LaunchAgents/com.xiabb.plist")

    func isLaunchAtLogin() -> Bool {
        FileManager.default.fileExists(atPath: plistPath.path)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            let appPath = Bundle.main.bundlePath
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>com.xiabb</string>
              <key>ProgramArguments</key><array>
                <string>/usr/bin/open</string>
                <string>-a</string>
                <string>\(appPath)</string>
              </array>
              <key>RunAtLoad</key><true/>
              <key>KeepAlive</key><false/>
            </dict></plist>
            """
            try? plist.write(to: plistPath, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: plistPath)
        }
    }

    // MARK: - Tick

    func tick() {
        tickCount += 1
        hud.tickPulse()

        if let btn = statusItem.button {
            if recorder.isRecording {
                btn.image = iconRec
                btn.alphaValue = 1.0
            } else if isTranscribing {
                btn.image = iconRec
                let phase = Double(tickCount) * 0.15
                btn.alphaValue = CGFloat(0.4 + 0.6 * abs(sin(phase)))
            } else {
                btn.image = iconIdle
                btn.alphaValue = 1.0
            }
        }

        if recorder.isRecording {
            statusMenuItem.title = "\(L("recording")) — \(usage.statusLine())"
            toggleItem.title = L("stop")
        } else if isTranscribing {
            statusMenuItem.title = "\(L("transcribing")) — \(usage.statusLine())"
        } else {
            statusMenuItem.title = "\(L("idle")) — \(usage.statusLine())"
            toggleItem.title = L("start")
        }
    }
}

// MARK: - Main

if apiKey.isEmpty {
    log("⚠️ No API key — set GEMINI_API_KEY env var or create ~/Tools/xiabb/.api-key")
    log("   Get a free key at https://aistudio.google.com/apikey")
}

let app = NSApplication.shared
let controller = XiaBBApp()
controller.setup()
app.run()
