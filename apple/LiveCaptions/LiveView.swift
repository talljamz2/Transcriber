import SwiftUI

struct LiveView: View {
    @Environment(CaptionController.self) private var controller
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingsKey.captionSize) private var captionSize: Double = 32
    @AppStorage(SettingsKey.captionFont) private var captionFont: CaptionFont = .newYork
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceMode = .system

    /// Newest first: the words being spoken right now at the top, then each earlier sentence
    /// below it. Only the live view is reversed; saved transcripts read in normal order.
    private var blocks: [(id: String, text: String)] {
        var result: [(id: String, text: String)] = []
        let pending = controller.transcriber.volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pending.isEmpty { result.append((id: "pending", text: pending)) }
        let segments = controller.current?.segments ?? []
        for segment in segments.reversed().prefix(60) {
            result.append((id: segment.id.uuidString, text: segment.text))
        }
        return result
    }

    /// The newest words are full strength; older lines fade toward grey as they move down.
    private func opacity(at index: Int, hasPending: Bool) -> Double {
        let age = index - (hasPending ? 1 : 0)
        switch age {
        case ...0: return 1
        case 1: return 0.62
        case 2: return 0.45
        default: return 0.34
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
            // Newest words are at the top, so the view stays anchored there.
            .defaultScrollAnchor(.top)
            .scrollIndicators(.hidden)

            controls
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .background(Theme.canvas)
    }

    // MARK: - Captions

    @ViewBuilder
    private var captions: some View {
        let blocks = blocks
        if blocks.isEmpty {
            Text(controller.isRecording ? "Listening…" : "Tap the button below to start captioning.")
                .font(captionFont.font(size: 22).italic())
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
                .multilineTextAlignment(.center)
        } else {
            let hasPending = blocks.first?.id == "pending"
            VStack(alignment: .leading, spacing: captionSize * 0.5) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    Text(block.text)
                        .lineSpacing(captionSize * 0.18)
                        .opacity(opacity(at: index, hasPending: hasPending))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(captionFont.font(size: captionSize))
            .animation(.easeOut(duration: 0.35), value: blocks.count)
            .textSelection(.enabled)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 8)
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
            RecordButton(isRecording: controller.isRecording, isBusy: isPreparing) {
                Task {
                    if controller.isRecording { await controller.stop() } else { await controller.start() }
                }
            }
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
        .accessibilityLabel(isRecording ? "Stop" : "Start captioning")
    }
}
