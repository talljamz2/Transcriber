import AVFoundation
import Speech
import Observation

enum CaptionError: LocalizedError {
    case microphoneDenied
    case noMicrophone
    case unsupportedDevice
    case unsupportedLanguage(String)
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is off. Turn it on for Live Captions in Settings › Privacy & Security › Microphone."
        case .noMicrophone:
            return "No microphone was found. Connect a microphone or headset and try again."
        case .unsupportedDevice:
            return "This device doesn't support Apple's on-device speech recognition."
        case .unsupportedLanguage(let name):
            return "\(name) isn't supported for on-device captions. Pick another language in Settings."
        case .noAudioFormat:
            return "Couldn't set up audio for speech recognition."
        }
    }
}

/// Streams microphone audio into Apple's SpeechAnalyzer and publishes the recognized text.
@MainActor
@Observable
final class LiveTranscriber {
    enum Phase: Equatable {
        case idle
        case preparing(String)
        case listening
    }

    private(set) var phase: Phase = .idle
    /// Text the recognizer may still revise. Shown dimmed until it becomes final.
    private(set) var volatileText = ""
    /// Called with each finalized piece of text.
    var onFinal: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var feeder: AudioFeeder?
    private var resultsTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    func start(localeIdentifier: String) async throws {
        guard phase == .idle else { return }
        phase = .preparing("Checking microphone access…")
        do {
            try await setUp(localeIdentifier: localeIdentifier)
            phase = .listening
        } catch {
            await tearDown()
            throw error
        }
    }

    func stop() async {
        guard phase != .idle else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        feeder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()

        // Let the last results arrive, but don't wait forever.
        if let pending = resultsTask {
            let timeout = Task {
                try? await Task.sleep(for: .seconds(3))
                pending.cancel()
            }
            await pending.value
            timeout.cancel()
        }
        commitVolatile()
        await tearDown()
    }

    // MARK: - Setup

    private func setUp(localeIdentifier: String) async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw CaptionError.microphoneDenied }
        guard SpeechTranscriber.isAvailable else { throw CaptionError.unsupportedDevice }

        let wanted = localeIdentifier.isEmpty ? Locale.current : Locale(identifier: localeIdentifier)
        guard let locale = try? await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else {
            let name = Locale.current.localizedString(forIdentifier: wanted.identifier) ?? wanted.identifier
            throw CaptionError.unsupportedLanguage(name)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        // The speech model for each language is downloaded once and then works offline.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            phase = .preparing("Downloading the \(name) speech model (one time only)…")
            try await request.downloadAndInstall()
        }

        phase = .preparing("Starting microphone…")
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [.allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        guard engine.inputNode.outputFormat(forBus: 0).sampleRate > 0 else { throw CaptionError.noMicrophone }
        guard let format = try? await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CaptionError.noAudioFormat
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.handle(text: String(result.text.characters), isFinal: result.isFinal)
                }
            } catch {
                // The stream ends with an error if analysis is cancelled; nothing to report.
            }
        }

        try await analyzer.start(inputSequence: stream)

        let feeder = AudioFeeder(continuation: continuation, outputFormat: format)
        self.feeder = feeder
        feeder.installTap(on: engine.inputNode)
        engine.prepare()
        try engine.start()
        observeAudioChanges()
    }

    private func tearDown() async {
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer {
            try? await analyzer.cancelAndFinishNow()
        }
        analyzer = nil
        feeder?.finish()
        feeder = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        volatileText = ""
        phase = .idle
    }

    // MARK: - Results

    private func handle(text: String, isFinal: Bool) {
        if isFinal {
            volatileText = ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { onFinal?(trimmed) }
        } else {
            volatileText = text
        }
    }

    private func commitVolatile() {
        let trimmed = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        volatileText = ""
        if !trimmed.isEmpty { onFinal?(trimmed) }
    }

    // MARK: - Audio route changes

    /// Plugging in headphones or a phone call stops the audio engine; restart it so captions continue.
    private func observeAudioChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAudio() }
        })
        #if os(iOS)
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            MainActor.assumeIsolated {
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.restartAudio()
            }
        })
        #endif
    }

    private func restartAudio() {
        guard phase == .listening, let feeder else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        guard engine.inputNode.outputFormat(forBus: 0).sampleRate > 0 else { return }
        feeder.installTap(on: engine.inputNode)
        engine.prepare()
        try? engine.start()
    }
}

/// Converts microphone buffers to the analyzer's format and queues them.
/// Kept off the main actor because the audio tap runs on a real-time audio thread.
final class AudioFeeder: @unchecked Sendable {
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(continuation: AsyncStream<AnalyzerInput>.Continuation, outputFormat: AVAudioFormat) {
        self.continuation = continuation
        self.outputFormat = outputFormat
    }

    func installTap(on node: AVAudioInputNode) {
        let inputFormat = node.outputFormat(forBus: 0)
        if inputFormat == outputFormat {
            converter = nil
        } else {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            converter?.primeMethod = .none
        }
        node.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
    }

    func finish() {
        continuation.finish()
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        final class Once { var done = false }
        let once = Once()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if once.done {
                inputStatus.pointee = .noDataNow
                return nil
            }
            once.done = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status != .error, output.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: output))
        }
    }
}
