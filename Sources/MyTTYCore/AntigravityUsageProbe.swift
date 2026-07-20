import Foundation

struct AntigravityUsageProcess: Equatable, Sendable {
    let processID: Int32
    let isCLI: Bool
    let csrfToken: String?
    let extensionPort: Int?
    let extensionToken: String?
}

public enum AntigravityUsageProbe {
    private struct Endpoint: Sendable {
        let scheme: String
        let port: Int
        let csrfToken: String?
    }

    public static func fetch() async -> Data? {
        guard let processList = await NativeUsageProcessRunner.capture(
            executable: "/bin/ps",
            arguments: ["-ax", "-o", "pid=,command="],
            timeout: 2
        ) else { return nil }

        for process in processes(from: processList) {
            guard let lsof = await NativeUsageProcessRunner.capture(
                executable: "/usr/sbin/lsof",
                arguments: [
                    "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p",
                    String(process.processID),
                ],
                timeout: 2
            ) else { continue }
            let ports = listeningPorts(from: lsof)
            for endpoint in endpoints(process: process, ports: ports) {
                if let data = await requestQuota(endpoint: endpoint) {
                    return data
                }
            }
        }
        return nil
    }

    static func processes(from output: String) -> [AntigravityUsageProcess] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            let parts = text.split(
                maxSplits: 1,
                whereSeparator: \.isWhitespace
            )
            guard parts.count == 2,
                  let processID = Int32(parts[0])
            else { return nil }
            let command = String(parts[1])
            let lower = command.lowercased()
            let isCLI = lower.range(
                of: #"(^|[/\\])(agy|antigravity[-_]cli)(\s|$)"#,
                options: .regularExpression
            ) != nil
            let isAppServer = lower.contains("antigravity")
                && lower.range(
                    of: #"(^|[/\\])language[-_]server(\s|$)"#,
                    options: .regularExpression
                ) != nil
            guard isCLI || isAppServer else { return nil }
            let csrfToken = flag("--csrf_token", in: command)
            guard isCLI || csrfToken != nil else { return nil }
            return AntigravityUsageProcess(
                processID: processID,
                isCLI: isCLI,
                csrfToken: csrfToken,
                extensionPort: flag("--extension_server_port", in: command)
                    .flatMap(Int.init),
                extensionToken: flag(
                    "--extension_server_csrf_token",
                    in: command
                )
            )
        }
    }

    static func listeningPorts(from output: String) -> [Int] {
        guard let regex = try? NSRegularExpression(
            pattern: #":(\d+)\s+\(LISTEN\)"#
        ) else { return [] }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        var ports = Set<Int>()
        regex.enumerateMatches(in: output, range: range) { match, _, _ in
            guard let match,
                  let matchRange = Range(match.range(at: 1), in: output),
                  let port = Int(output[matchRange])
            else { return }
            ports.insert(port)
        }
        return ports.sorted()
    }

    private static func endpoints(
        process: AntigravityUsageProcess,
        ports: [Int]
    ) -> [Endpoint] {
        if process.isCLI {
            return ports.prefix(8).map {
                Endpoint(scheme: "https", port: $0, csrfToken: nil)
            }
        }
        var values = ports.prefix(8).map {
            Endpoint(
                scheme: "https",
                port: $0,
                csrfToken: process.csrfToken
            )
        }
        if let extensionPort = process.extensionPort {
            values.insert(
                Endpoint(
                    scheme: "http",
                    port: extensionPort,
                    csrfToken: process.extensionToken ?? process.csrfToken
                ),
                at: 0
            )
        }
        return values
    }

    private static func requestQuota(endpoint: Endpoint) async -> Data? {
        let path = "/exa.language_server_pb.LanguageServerService/"
            + "RetrieveUserQuotaSummary"
        guard let url = URL(
            string: "\(endpoint.scheme)://127.0.0.1:\(endpoint.port)\(path)"
        ) else { return nil }
        let body = Data(#"{"forceRefresh":true}"#.utf8)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 1.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if let csrfToken = endpoint.csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 1.5
        configuration.waitsForConnectivity = false
        let delegate = AntigravityLocalhostTrustDelegate()
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (try? NativeAgentUsageParser.antigravitySummary(from: data)) != nil
        else { return nil }
        return data
    }

    private static func flag(_ name: String, in command: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: "(?:^|\\s)\(escaped)(?:=|\\s+)([^\\s]+)",
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = regex.firstMatch(in: command, range: range),
              let valueRange = Range(match.range(at: 1), in: command)
        else { return nil }
        return String(command[valueRange])
    }
}

private final class AntigravityLocalhostTrustDelegate: NSObject,
    URLSessionDelegate,
    @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.host == "127.0.0.1",
              space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}
