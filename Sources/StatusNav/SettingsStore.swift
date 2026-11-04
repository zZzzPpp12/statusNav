import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var showPercentage: Bool { didSet { defaults.set(showPercentage, forKey: "showPercentage") } }
    @Published var colorful: Bool { didSet { defaults.set(colorful, forKey: "colorful") } }
    @Published var showDock: Bool { didSet { defaults.set(showDock, forKey: "showDock") } }
    @Published var iconSize: Double { didSet { defaults.set(iconSize, forKey: "iconSize") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showPercentage = defaults.object(forKey: "showPercentage") as? Bool ?? false
        colorful = defaults.object(forKey: "colorful") as? Bool ?? true
        showDock = defaults.object(forKey: "showDock") as? Bool ?? false
        let savedSize = defaults.object(forKey: "iconSize") as? Double ?? 26
        iconSize = savedSize.isFinite ? min(32, max(22, savedSize)) : 26
    }
}
