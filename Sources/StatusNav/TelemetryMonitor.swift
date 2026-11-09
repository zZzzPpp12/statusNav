import AppKit
import Combine
import StatusNavCore

@MainActor
final class TelemetryMonitor: ObservableObject {
    @Published private(set) var power = PowerSnapshot()
    @Published private(set) var rates: TrafficRates?
    @Published private(set) var applications: [ApplicationActivity] = []
    @Published private(set) var applicationSampling = false
    private var trafficTracker = TrafficTracker()
    private var activityTracker = ActivityTracker()
    private var interface: String?
    private var context = BatteryPowerContext(external: false, charging: false)
    private var wantsPower = false
    private var wantsRates = false
    private var wantsApps = false
    private var powerRunning = false
    private var appsRunning = false
    private var generation = 0
    private var lastPower = 0.0
    private var lastApps = 0.0
    private var timer: Timer?

    func configure(power: Bool, rates: Bool, applications: Bool) {
        guard wantsPower != power || wantsRates != rates || wantsApps != applications else { return }
        if wantsApps != applications {
            activityTracker.reset(); self.applications = []; lastApps = 0
            applicationSampling = applications
        }
        if wantsRates != rates { trafficTracker.reset(); self.rates = nil }
        if wantsPower != power || wantsApps != applications { generation += 1 }
        wantsPower = power; wantsRates = rates; wantsApps = applications
        if !power { self.power = PowerSnapshot(); lastPower = 0 }
        let active = power || rates || applications
        if active && timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else if !active { timer?.invalidate(); timer = nil }
        if active { tick() }
    }

    func update(interface: String?, context: BatteryPowerContext) {
        if self.interface != interface { self.interface = interface; trafficTracker.reset(); rates = nil }
        if self.context != context {
            self.context = context; generation += 1; power = PowerSnapshot(); lastPower = 0
        }
    }

    func reset() {
        generation += 1; trafficTracker.reset(); activityTracker.reset()
        rates = nil; power = PowerSnapshot(); applications = []; lastPower = 0; lastApps = 0
        tick()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if wantsRates {
            if let interface, let sample = TrafficReader.read(interface: interface) { rates = trafficTracker.receive(sample) }
            else { rates = nil; trafficTracker.reset() }
        }
        if let date = power.updatedAt, Date().timeIntervalSince(date) > 12 { power = PowerSnapshot() }
        if wantsPower, !powerRunning, now - lastPower >= 4 {
            lastPower = now; powerRunning = true
            let context = context; let epoch = generation
            Task.detached(priority: .utility) { [weak self] in
                let sample = PowerReader.read(context: context)
                await self?.acceptPower(sample, epoch: epoch)
            }
        }
        if wantsApps, !appsRunning, now - lastApps >= 4 {
            lastApps = now; appsRunning = true
            let epoch = generation
            let identities = NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationIdentity? in
                guard let path = app.bundleURL?.path, let name = app.localizedName else { return nil }
                return ApplicationIdentity(path: path, name: name)
            }
            Task.detached(priority: .utility) { [weak self] in
                let time = ProcessInfo.processInfo.systemUptime
                let rows = ApplicationActivityReader.read(applications: identities)
                await self?.acceptApplications(rows, at: time, epoch: epoch)
            }
        }
    }

    private func acceptPower(_ value: PowerSnapshot, epoch: Int) {
        powerRunning = false
        guard wantsPower, epoch == generation else { return }
        power = value
    }
    private func acceptApplications(_ values: [ProcessSample], at time: Double, epoch: Int) {
        appsRunning = false
        guard wantsApps, epoch == generation, ProcessInfo.processInfo.systemUptime - time < 10 else { return }
        applications = activityTracker.receive(values, at: time)
        applicationSampling = !values.isEmpty && applications.isEmpty
    }
    func stop(preserveReadings: Bool = false) {
        if preserveReadings {
            wantsPower = false; wantsRates = false; wantsApps = false
            timer?.invalidate(); timer = nil
        } else { configure(power: false, rates: false, applications: false) }
        generation += 1
    }
}
