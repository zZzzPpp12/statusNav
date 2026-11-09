import Foundation
import IOKit
import StatusNavCore

enum BacklightReader {
    static func read() -> BacklightSnapshot {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"))
        guard service != 0 else { return BacklightSnapshot() }
        defer { IOObjectRelease(service) }
        guard let parameters = IORegistryEntryCreateCFProperty(service, "IODisplayParameters" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { return BacklightSnapshot() }
        return BacklightSnapshot.parse(parameters: parameters)
    }
}
