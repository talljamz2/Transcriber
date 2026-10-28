import SwiftUI

/// Typefaces offered for captions and transcripts. All are built into iOS and macOS.
enum CaptionFont: String, CaseIterable, Identifiable {
    case system
    case newYork
    case georgia
    case charter
    case iowan
    case palatino
    case baskerville
    case timesNewRoman
    case rounded

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "San Francisco (default)"
        case .newYork: "New York"
        case .georgia: "Georgia"
        case .charter: "Charter"
        case .iowan: "Iowan Old Style"
        case .palatino: "Palatino"
        case .baskerville: "Baskerville"
        case .timesNewRoman: "Times New Roman"
        case .rounded: "Rounded"
        }
    }

    var isSerif: Bool {
        switch self {
        case .system, .rounded: false
        default: true
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system: .system(size: size, weight: weight)
        case .newYork: .system(size: size, weight: weight, design: .serif)
        case .rounded: .system(size: size, weight: weight, design: .rounded)
        case .georgia: .custom("Georgia", size: size).weight(weight)
        case .charter: .custom("Charter", size: size).weight(weight)
        case .iowan: .custom("Iowan Old Style", size: size).weight(weight)
        case .palatino: .custom("Palatino", size: size).weight(weight)
        case .baskerville: .custom("Baskerville", size: size).weight(weight)
        case .timesNewRoman: .custom("Times New Roman", size: size).weight(weight)
        }
    }
}
