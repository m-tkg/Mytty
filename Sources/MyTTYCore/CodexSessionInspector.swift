import Darwin
import Foundation

public struct AgentSessionStatus: Equatable, Sendable {
    public let sessionID: String?
    public let modelName: String?
    public let contextRemainingPercent: Double?

    public init(
        sessionID: String?,
        modelName: String?,
        contextRemainingPercent: Double?
    ) {
        self.sessionID = sessionID
        self.modelName = modelName
        self.contextRemainingPercent = contextRemainingPercent
    }
}

public enum AgentSessionIDSelection {
    public static func resolve(
        processBound: String?,
        hook: String?
    ) -> String? {
        processBound ?? hook
    }
}

public enum CodexSessionInspector {
    private static let maximumMetadataBytes = 1_024 * 1_024
    private static let maximumStatusTailBytes = 512 * 1_024

    public static func sessionID(
        processID: pid_t,
        codexHome: URL = defaultCodexHome
    ) -> String? {
        guard processID > 0 else { return nil }
        return openSessionTranscripts(
            processID: processID,
            codexHome: codexHome
        )
        .sorted { modificationDate($0) > modificationDate($1) }
        .lazy
        .compactMap(readMetadata)
        .first
    }

    public static func status(
        processID: pid_t,
        codexHome: URL = defaultCodexHome
    ) -> AgentSessionStatus? {
        guard processID > 0 else { return nil }
        return openSessionTranscripts(
            processID: processID,
            codexHome: codexHome
        )
        .sorted { modificationDate($0) > modificationDate($1) }
        .lazy
        .compactMap(readStatus)
        .first
    }

    static func sessionID(from data: Data) -> String? {
        let line: Data
        if let newline = data.firstIndex(of: 0x0A) {
            line = data.prefix(upTo: newline)
        } else {
            line = data
        }
        guard let object = try? JSONSerialization.jsonObject(with: line)
            as? [String: Any],
              let payload = object["payload"] as? [String: Any]
        else { return nil }
        return AgentSessionValidation.identifier(
            payload["session_id"] as? String
                ?? payload["id"] as? String
        )
    }

    static func status(from data: Data) -> AgentSessionStatus? {
        var sessionID: String?
        var modelName: String?
        var contextRemainingPercent: Double?

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(
                with: Data(line)
            ) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any]
            else { continue }

            switch type {
            case "session_meta":
                sessionID = AgentSessionValidation.identifier(
                    payload["session_id"] as? String
                        ?? payload["id"] as? String
                ) ?? sessionID
            case "turn_context":
                modelName = AgentSessionValidation.label(
                    payload["model"] as? String
                ) ?? modelName
            case "event_msg":
                guard payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let window = positiveDouble(
                          info["model_context_window"]
                      ),
                      let usage = (info["last_token_usage"]
                          ?? info["total_token_usage"])
                          as? [String: Any],
                      let tokens = tokenCount(from: usage)
                else { continue }
                contextRemainingPercent = min(
                    100,
                    max(0, (1 - tokens / window) * 100)
                )
            default:
                continue
            }
        }

        guard sessionID != nil || modelName != nil
                || contextRemainingPercent != nil
        else { return nil }
        return AgentSessionStatus(
            sessionID: sessionID,
            modelName: modelName,
            contextRemainingPercent: contextRemainingPercent
        )
    }

    public static var defaultCodexHome: URL {
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"],
           !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private static func openSessionTranscripts(
        processID: pid_t,
        codexHome: URL
    ) -> [URL] {
        let descriptorSize = MemoryLayout<proc_fdinfo>.stride
        let requiredBytes = proc_pidinfo(
            processID,
            PROC_PIDLISTFDS,
            0,
            nil,
            0
        )
        guard requiredBytes > 0 else { return [] }

        let capacity = Int(requiredBytes) / descriptorSize + 16
        var descriptors = [proc_fdinfo](
            repeating: proc_fdinfo(),
            count: capacity
        )
        let actualBytes = descriptors.withUnsafeMutableBytes { buffer in
            proc_pidinfo(
                processID,
                PROC_PIDLISTFDS,
                0,
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
        guard actualBytes > 0 else { return [] }

        let sessionsDirectory = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let sessionsPrefix = sessionsDirectory.hasSuffix("/")
            ? sessionsDirectory
            : sessionsDirectory + "/"
        return descriptors
            .prefix(Int(actualBytes) / descriptorSize)
            .compactMap { descriptor in
                guard descriptor.proc_fdtype == PROX_FDTYPE_VNODE,
                      let path = vnodePath(
                        processID: processID,
                        fileDescriptor: descriptor.proc_fd
                      ),
                      path.hasSuffix(".jsonl")
                else { return nil }
                let url = URL(fileURLWithPath: path, isDirectory: false)
                    .resolvingSymlinksInPath().standardizedFileURL
                guard url.path.hasPrefix(sessionsPrefix) else { return nil }
                return url
            }
    }

    private static func vnodePath(
        processID: pid_t,
        fileDescriptor: Int32
    ) -> String? {
        var info = vnode_fdinfowithpath()
        let expectedSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidfdinfo(
                processID,
                fileDescriptor,
                PROC_PIDFDVNODEPATHINFO,
                pointer,
                expectedSize
            )
        }
        guard result >= expectedSize else { return nil }
        return withUnsafePointer(to: &info.pvip.vip_path) { path in
            path.withMemoryRebound(
                to: CChar.self,
                capacity: Int(MAXPATHLEN)
            ) {
                let value = String(cString: $0)
                return value.isEmpty ? nil : value
            }
        }
    }

    private static func readMetadata(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(
            upToCount: maximumMetadataBytes
        ) else { return nil }
        return sessionID(from: data)
    }

    private static func readStatus(from url: URL) -> AgentSessionStatus? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let tailSize = min(UInt64(maximumStatusTailBytes), end)
        guard let _ = try? handle.seek(toOffset: end - tailSize),
              let data = try? handle.readToEnd()
        else { return nil }

        if let status = status(from: data), status.sessionID != nil {
            return status
        }
        guard let _ = try? handle.seek(toOffset: 0),
              let metadata = try? handle.read(
                  upToCount: maximumMetadataBytes
              )
        else { return status(from: data) }
        var combined = metadata
        combined.append(0x0A)
        combined.append(data)
        return status(from: combined)
    }

    private static func modificationDate(_ url: URL) -> Date {
        FileFingerprint.modificationDate(of: url)
    }

    private static func tokenCount(from usage: [String: Any]) -> Double? {
        if let total = positiveDouble(usage["total_tokens"]) {
            return total
        }
        let input = nonnegativeDouble(usage["input_tokens"])
        let output = nonnegativeDouble(usage["output_tokens"])
        guard input != nil || output != nil else { return nil }
        return (input ?? 0) + (output ?? 0)
    }

    private static func positiveDouble(_ value: Any?) -> Double? {
        guard let value = nonnegativeDouble(value), value > 0 else {
            return nil
        }
        return value
    }

    private static func nonnegativeDouble(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else if let value = value as? String {
            number = Double(value)
        } else {
            number = nil
        }
        guard let number, number.isFinite, number >= 0 else { return nil }
        return number
    }
}
