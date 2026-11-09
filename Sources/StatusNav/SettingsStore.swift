import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var showPercentage: Bool { didSet { defaults.set(showPercentage, forKey: "showPercentage") } }
    @Published var colorful: Bool { didSet { defaults.set(colorful, forKey: "colorful") } }
    @Published var showDock: Bool { didSet { defaults.set(showDock, forKey: "showDock") } }
    @Published var iconSize: Double { didSet { defaults.set(iconSize, forKey: "iconSize") } }
    @Published var showBluetoothPanel: Bool { didSet { defaults.set(showBluetoothPanel, forKey: "showBluetoothPanel") } }
    @Published var showApplicationActivity: Bool { didSet { defaults.set(showApplicationActivity, forKey: "showApplicationActivity") } }
    @Published var showBatteryPowerInMenuBar: Bool { didSet { defaults.set(showBatteryPowerInMenuBar, forKey: "showBatteryPowerInMenuBar") } }
    @Published var showNetworkRatesInMenuBar: Bool { didSet { defaults.set(showNetworkRatesInMenuBar, forKey: "showNetworkRatesInMenuBar") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showBluetoothPanel = defaults.object(forKey: "showBluetoothPanel") as? Bool ?? true
        showApplicationActivity = defaults.object(forKey: "showApplicationActivity") as? Bool ?? true
        showBatteryPowerInMenuBar = defaults.object(forKey: "showBatteryPowerInMenuBar") as? Bool ?? false
        showNetworkRatesInMenuBar = defaults.object(forKey: "showNetworkRatesInMenuBar") as? Bool ?? false
        showPercentage = defaults.object(forKey: "showPercentage") as? Bool ?? false
        colorful = defaults.object(forKey: "colorful") as? Bool ?? true
        showDock = defaults.object(forKey: "showDock") as? Bool ?? false
        let savedSize = defaults.object(forKey: "iconSize") as? Double ?? 26
        iconSize = savedSize.isFinite ? min(32, max(22, savedSize)) : 26
    }
}
