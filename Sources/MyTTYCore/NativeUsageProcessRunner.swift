import Foundation

public enum NativeUsageProcessRunner {
    public static func capture(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> String? {
        await Task.detached(priority: .utility) {
            captureSynchronously(
                executable: executable,
                arguments: arguments,
                timeout: timeout
            )
        }.value
    }

    private static func captureSynchronously(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> String? {
        let process = Process()
        let output = Pipe()
        let buffer = NativeUsageOutputBuffer()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(data)
            }
        }
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            _ = finished.wait(timeout: .now() + 0.5)
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        output.fileHandleForReading.readabilityHandler = nil
        buffer.append(output.fileHandleForReading.availableData)
        guard process.terminationStatus == 0 else { return nil }
        return String(data: buffer.data, encoding: .utf8)
    }
}

private final class NativeUsageOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.withLock { storage }
    }

    func append(_ data: Data) {
        lock.withLock { storage.append(data) }
    }
}
