import AppKit
import GhosttyAdapter
import MyTTYCore

extension TerminalAppearance {
    var appKitAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    func ghosttyColorScheme(
        effectiveAppearance: NSAppearance
    ) -> GhosttyColorScheme {
        switch self {
        case .light:
            .light
        case .dark:
            .dark
        case .system:
            effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                == .darkAqua ? .dark : .light
        }
    }
}
