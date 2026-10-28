import SwiftUI

struct LiveView: View {
    @Environment(CaptionController.self) private var controller
    @AppStorage(SettingsKey.captionSize) private var captionSize: Double = 32
    @AppStorage(SettingsKey.captionFont) private var captionFont: CaptionFont = .system

    /// Finished text plus the words still being recognized, which are dimmed and flow on
    /// from the last sentence (or start a new paragraph after a pause) so nothing jumps.
    private var lines: [(id: Int, text: AttributedString)] {
        let segments = controller.current?.segments ?? []
        var result = CaptionParagraph.group(segments).map { (id: $0.id, text: AttributedString($0.text)) }
        let pending = controller.transcriber.volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty else { return result }

        var dimmed = AttributedString(pending)
        dimmed.foregroundColor = .secondary
        if let lastTime = segments.last?.time, Date.now.timeIntervalSince(lastTime) < 4, !result.isEmpty {
            result[result.count - 1].text += AttributedString(" ") + dimmed
        } else {
            result.append((id: result.count, text: dimmed))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            statusLine
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: captionSize * 0.45) {
                    let lines = lines
                    if lines.isEmpty {
                        Text("Words spoken around you will appear here.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lines, id: \.id) { line in
                        Text(line.text)
                    }
                }
                .font(captionFont.font(size: captionSize, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
            }
            // Keep the newest words in view as the text grows.
            .defaultScrollAnchor(.bottom, for: .sizeChanges)

            Divider()
            controls
                .padding()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack {
            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if case .preparing(let message) = controller.transcriber.phase {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            } else if controller.isRecording {
                Image(systemName: "circle.fill").foregroundStyle(.red).font(.caption)
                Text("Listening…").foregroundStyle(.secondary)
            } else {
                if controller.isSummarizing { ProgressView().controlSize(.small) }
                Text(controller.status).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.callout)
        .frame(minHeight: 24)
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button {
                captionSize = max(18, captionSize - 4)
            } label: {
                Text("A−").font(.title3.bold()).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Smaller text")

            Button {
                Task {
                    if controller.isRecording { await controller.stop() } else { await controller.start() }
                }
            } label: {
                Text(controller.isRecording ? "Stop" : "Start")
                    .font(.title2.bold())
                    .frame(minWidth: 140, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isRecording ? .red : .accentColor)
            .disabled(isPreparing || controller.isSummarizing)
            .keyboardShortcut(.space, modifiers: [])

            Button {
                captionSize = min(72, captionSize + 4)
            } label: {
                Text("A+").font(.title3.bold()).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Larger text")
        }
    }

    private var isPreparing: Bool {
        if case .preparing = controller.transcriber.phase { return true }
        return false
    }
}
