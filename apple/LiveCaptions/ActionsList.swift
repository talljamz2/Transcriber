import SwiftUI

/// An action together with the session it came from.
struct ActionEntry: Identifiable {
    let session: CaptionSession
    let action: ActionItem
    var id: UUID { action.id }
}

/// Actions grouped into yours, other people's, and unclear (with Mine / Not mine buttons).
struct ActionsList: View {
    let entries: [ActionEntry]
    /// Show which session each action came from (used on the daily summary).
    var showSource = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            group("Your actions", systemImage: "person.fill", owner: .me, tint: .accentColor)
            group("Unclear: who's doing this?", systemImage: "questionmark.circle", owner: .unclear, tint: .orange)
            group("Other people's actions", systemImage: "person.2", owner: .other, tint: .secondary)
        }
    }

    @ViewBuilder
    private func group(_ title: String, systemImage: String, owner: ActionItem.Owner, tint: Color) -> some View {
        let items = entries.filter { $0.action.owner == owner }
        if !items.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { entry in
                        ActionRow(entry: entry, showSource: showSource)
                        if entry.id != items.last?.id { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("\(title) (\(items.count))", systemImage: systemImage)
                    .foregroundStyle(tint)
            }
        }
    }
}

struct ActionRow: View {
    let entry: ActionEntry
    let showSource: Bool
    @Environment(CaptionController.self) private var controller
    @AppStorage(SettingsKey.captionFont) private var captionFont: CaptionFont = .newYork

    private var action: ActionItem { entry.action }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(action.task)
                .font(captionFont.font(size: 17, weight: .medium))
            let details = [action.owner == .other ? action.ownerLabel : "", action.dueLabel]
                .filter { !$0.isEmpty }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !action.quote.isEmpty {
                Text("“\(action.quote)”")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            if showSource {
                NavigationLink(value: entry.session) {
                    Text("From: \(entry.session.displayTitle) · \(Format.time(entry.session.startedAt))")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            if action.owner == .unclear {
                HStack {
                    Button("Mine") { set(.me) }
                    Button("Not mine") { set(.other) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .contextMenu {
            Button("Mine") { set(.me) }
            Button("Not mine") { set(.other) }
            Button("Not sure") { set(.unclear) }
        }
    }

    private func set(_ owner: ActionItem.Owner) {
        controller.setOwner(owner, for: action.id, in: entry.session)
    }
}
