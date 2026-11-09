import Foundation
import Darwin

enum LocalReportProcess {
    static func read(_ path: String, arguments: [String], timeout: TimeInterval) -> Data? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("statusnav-report-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let handle = try? FileHandle(forWritingTo: file) else { return nil }
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.standardOutput = handle; process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.5) == .timedOut {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                _ = finished.wait(timeout: .now() + 1)
            }
            return nil
        }
        guard process.terminationStatus == 0,
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 4_000_000 else { return nil }
        return try? Data(contentsOf: file)
    }
}
