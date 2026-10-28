import SwiftUI

struct LiveView: View {
    @Environment(CaptionController.self) private var controller
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingsKey.captionSize) private var captionSize: Double = 32
    @AppStorage(SettingsKey.captionFont) private var captionFont: CaptionFont = .newYork
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceMode = .system
    @State private var showTranscript = false

    /// The conversation as flowing paragraphs in normal reading order, newest words at the end.
    /// The newest words are solid; each earlier sentence is a little lighter, so the eye is drawn
    /// to what was just said. A new paragraph starts after a pause.
    private var flowingText: AttributedString {
        let segments = (controller.current?.segments ?? []).suffix(80)
        let pending = controller.transcriber.volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = AttributedString()
        var previous: Date?
        for (offset, segment) in segments.enumerated() {
            if let previous {
                text += AttributedString(segment.time.timeIntervalSince(previous) > 4 ? "\n\n" : " ")
            }
            var part = AttributedString(segment.text)
            part.foregroundColor = Color.primary.opacity(Self.opacity(age: segments.count - 1 - offset))
            text += part
            previous = segment.time
        }
        if !pending.isEmpty {
            if let previous {
                text += AttributedString(Date.now.timeIntervalSince(previous) > 4 ? "\n\n" : " ")
            }
            var part = AttributedString(pending)
            part.foregroundColor = Color.primary
            text += part
        }
        return text
    }

    /// 0 is the newest finished sentence.
    private static func opacity(age: Int) -> Double {
        switch age {
        case 0: 1
        case 1: 0.72
        case 2: 0.56
        case 3: 0.46
        default: 0.38
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView {
                captions
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
            // Text starts at the top and fills down; once the screen is full the newest words stay
            // pinned to the bottom and older lines scroll off the top, like dictation.
            .defaultScrollAnchor(.top, for: .alignment)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollIndicators(.hidden)

            controls
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .background(Theme.canvas)
        .sheet(isPresented: $showTranscript) {
            TranscriptSearchView(session: controller.current, initialQuery: demoFind)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
                #endif
        }
        #if DEBUG
        .onAppear { if DemoData.screen == "transcript" { showTranscript = true } }
        #endif
    }

    // MARK: - Captions

    @ViewBuilder
    private var captions: some View {
        let text = flowingText
        if text.characters.isEmpty {
            Text(controller.isRecording ? "Listening…" : "Tap the button below to start captioning.")
                .font(captionFont.font(size: 22).italic())
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
                .multilineTextAlignment(.center)
        } else {
            Text(text)
                .font(captionFont.font(size: captionSize))
                .lineSpacing(captionSize * 0.18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 8)
            Button {
                showTranscript = true
            } label: {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(controller.current == nil)
            .accessibilityLabel("Full transcript and search")
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    appearance = colorScheme == .dark ? .light : .dark
                }
            } label: {
                Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(colorScheme == .dark ? "Switch to light mode" : "Switch to dark mode")
        }
        .frame(minHeight: 36)
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 8) {
            if let error = controller.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.record)
                Text(error).foregroundStyle(Theme.record)
            } else if case .preparing(let message) = controller.transcriber.phase {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            } else if controller.isRecording {
                Circle().fill(Theme.record).frame(width: 8, height: 8)
                Text("Live").fontWeight(.semibold)
            } else if controller.isPaused {
                Image(systemName: "pause.fill").foregroundStyle(.secondary)
                Text("Paused · tap ▶ to resume or ■ to end").foregroundStyle(.secondary)
            } else {
                Text(controller.status).foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .lineLimit(2)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            sizeButton("textformat.size.smaller", label: "Smaller text") {
                captionSize = max(18, captionSize - 4)
            }
            Spacer()
            HStack(spacing: 22) {
                if controller.isSessionActive {
                    Button {
                        Task {
                            if controller.isPaused { await controller.resume() } else { await controller.pause() }
                        }
                    } label: {
                        Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 22))
                            .frame(width: 58, height: 58)
                            .background(Theme.card, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPreparing)
                    .accessibilityLabel(controller.isPaused ? "Resume" : "Pause")
                    .transition(.scale.combined(with: .opacity))
                }
                RecordButton(isRecording: controller.isSessionActive, isBusy: isPreparing) {
                    Task {
                        if controller.isSessionActive { await controller.end() } else { await controller.start() }
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: controller.isSessionActive)
            Spacer()
            sizeButton("textformat.size.larger", label: "Larger text") {
                captionSize = min(72, captionSize + 4)
            }
        }
    }

    private func sizeButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 48, height: 48)
                .background(Theme.card, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var demoFind: String {
        #if DEBUG
        DemoData.query ?? ""
        #else
        ""
        #endif
    }

    private var isPreparing: Bool {
        if case .preparing = controller.transcriber.phase { return true }
        return false
    }
}

/// A Voice Memos–style button: a red dot to start, a red rounded square to stop.
struct RecordButton: View {
    let isRecording: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 4)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 31, style: .continuous)
                    .fill(Theme.record)
                    .frame(width: isRecording ? 30 : 62, height: isRecording ? 30 : 62)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isRecording)
            .opacity(isBusy ? 0.4 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityLabel(isRecording ? "End and save" : "Start captioning")
    }
}
