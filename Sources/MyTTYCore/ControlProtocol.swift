import Foundation

/// Wire protocol for `mytty-ctl`, the local CLI AI agents use to drive
/// Mytty panes (create/split panes, type text, read the screen, and wait
/// for an agent to go idle or need attention) so a "team" of subagents can
/// run as real, visible panes instead of hidden background processes. See
/// `docs/reference/mytty-ctl.md`.
///
/// Unlike `RemoteMessage` (paired, encrypted, TCP), this protocol only ever
/// travels over a local Unix-domain socket restricted to the current user
/// (`ApplicationPaths.aiControlSocket`), one JSON request per connection —
/// the same trust model as `AgentEventEnvelope`.
public enum ControlSplitDirection: String, Codable, Equatable, Sendable {
    case left
    case right
    case up
    case down
}

public enum ControlWaitCondition: String, Codable, Equatable, Sendable {
    /// Satisfied once the pane's most relevant agent run reaches idle,
    /// succeeded, failed, or disconnected — i.e. it's done producing more
    /// output without being asked something first.
    case idle
    /// Satisfied once the pane's most relevant agent run is waiting on
    /// input or approval. Cursor and Antigravity hooks don't expose these
    /// events (see `docs/reference/agent-providers.md`), so this never resolves
    /// for panes running those providers until the timeout.
    case attention
}

public struct ControlPaneInfo: Codable, Equatable, Sendable {
    public let paneID: String
    public let windowID: String
    public let tabID: String
    public let title: String
    public let command: String
    public let workingDirectory: String?
    public let isActive: Bool
    /// `AgentProvider.rawValue` of the most relevant agent run tracked for
    /// this pane, if any hook event has been recorded for it.
    public let provider: String?
    /// `AgentRunState.rawValue` of that same run.
    public let agentState: String?
    /// The pane agent's own latest `mytty-ctl status` self-report, if any.
    public let statusNote: String?

    public init(
        paneID: String,
        windowID: String,
        tabID: String,
        title: String,
        command: String,
        workingDirectory: String?,
        isActive: Bool,
        provider: String?,
        agentState: String?,
        statusNote: String? = nil
    ) {
        self.paneID = paneID
        self.windowID = windowID
        self.tabID = tabID
        self.title = title
        self.command = command
        self.workingDirectory = workingDirectory
        self.isActive = isActive
        self.provider = provider
        self.agentState = agentState
        self.statusNote = statusNote
    }
}

/// Validation for `mytty-ctl status` self-reports: a short, single-line,
/// human-readable progress note. Mirrors the label rules `agent spawn`
/// applies (100 Unicode scalars, no control characters — which also rules
/// out newlines) with the addition that an explicit status must be
/// nonempty; clearing is its own operation, not an empty-string write.
public enum ControlStatusNoteValidation {
    public static let maximumScalars = 100

    public static func isValid(_ note: String) -> Bool {
        !note.isEmpty
            && note.unicodeScalars.count <= maximumScalars
            && note.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}

/// One provider's hook-integration state as reported by
/// `mytty-ctl integration list/enable/repair`. `status` carries
/// `AgentIntegrationStatus.controlValue`; `error` is the same
/// human-readable install error the Settings pane would show, if the last
/// install/repair attempt failed.
public struct ControlIntegrationInfo: Codable, Equatable, Sendable {
    public let provider: String
    public let status: String
    public let error: String?

    public init(provider: String, status: String, error: String?) {
        self.provider = provider
        self.status = status
        self.error = error
    }
}

public extension AgentIntegrationStatus {
    /// The wire value `ControlIntegrationInfo.status` carries.
    var controlValue: String {
        switch self {
        case .notInstalled: "not-installed"
        case .installed: "installed"
        case .needsRepair: "needs-repair"
        }
    }
}

public struct ControlPaneContent: Codable, Equatable, Sendable {
    public let paneID: String
    public let text: String
    public let cursorRow: Int?
    public let cursorColumn: Int?

    public init(
        paneID: String,
        text: String,
        cursorRow: Int?,
        cursorColumn: Int?
    ) {
        self.paneID = paneID
        self.text = text
        self.cursorRow = cursorRow
        self.cursorColumn = cursorColumn
    }
}

public enum ControlRequest: Equatable, Sendable {
    case list
    /// `command`, when present, is delivered to the new pane as transient
    /// initial input the same way `agent spawn` delivers its launch
    /// command and task: prefixed with
    /// `AgentLaunchPlan.historySuppressionPrefix` and terminated with a
    /// single trailing newline, via `AgentLaunchPlan.initialInput(command:)`.
    /// This lets `new-tab --command` launch a worker with its task inline
    /// instead of racing a separate `send` against the worker's still-
    /// initializing TUI.
    case newTab(workingDirectory: String?, command: String?)
    /// See `newTab`'s `command` doc — `split --command` gets the identical
    /// one-shot delivery.
    case split(
        paneID: String,
        direction: ControlSplitDirection,
        workingDirectory: String?,
        command: String?
    )
    case send(paneID: String, text: String, pressEnter: Bool)
    case sendKey(paneID: String, key: String, modifiers: [String])
    case read(paneID: String)
    case wait(
        paneID: String,
        until: ControlWaitCondition,
        timeoutSeconds: Double
    )
    case closePane(paneID: String)
    case focus(paneID: String)
    /// A pane agent's own progress self-report ("running tests", ...),
    /// shown in the status bar and echoed in `list`/`agent result`
    /// answers. Ephemeral by design — never persisted, cleared when the
    /// pane's run starts or ends. `status: nil` clears an earlier report.
    case setPaneStatus(paneID: String, status: String?)

    /// Long-poll fan-in over every pane's agent events, for an
    /// orchestrator watching several workers at once: one `events` call
    /// replaces one `wait`/`agent wait` per pane. `afterSequence` is a
    /// cursor from a previous `ControlResponse.events.latestSequence`; `0`
    /// (the default for a first call) deliberately returns no history —
    /// it only establishes a cursor at the current tip, so a fresh
    /// listener doesn't replay everything that happened before it started
    /// watching. A nonzero `afterSequence` with newer events retained
    /// returns them immediately; otherwise the request blocks until a new
    /// event arrives or `timeoutSeconds` elapses. `ControlEventLedger`
    /// retains at most 1000 records, so a cursor that goes stale long
    /// enough (a listener that stopped polling for a while) can silently
    /// skip evicted history — see `ControlEventLedger.records(after:)`.
    case events(afterSequence: UInt64, timeoutSeconds: Double)

    /// Creates a new worker pane split off `anchorPaneID`, launches
    /// `provider` in it with `access` and `task` as one shell input, and
    /// returns an `AgentJobID` an orchestrator can `waitAgent`/`sendAgent`/
    /// etc. on for that exact spawn — see `AgentJobTracker` for how a job
    /// binds to the run it observes. The high-level counterpart to
    /// `split` + `send`.
    case spawnAgent(
        anchorPaneID: String,
        direction: ControlSplitDirection,
        provider: AgentWorkerProvider,
        cwd: String?,
        access: AgentAccessPolicy,
        model: String?,
        task: String,
        label: String?
    )
    case waitAgent(
        jobID: AgentJobID,
        until: AgentWaitCondition,
        timeoutSeconds: Double
    )
    case agentResult(jobID: AgentJobID)
    case sendAgent(jobID: AgentJobID, text: String, pressEnter: Bool)
    case focusAgent(jobID: AgentJobID)
    case closeAgent(jobID: AgentJobID)

    /// Read-only status of every provider's hook integration.
    case integrationList
    /// Install `provider`'s hook integration. The app puts a confirmation
    /// dialog in front of a human first — there is deliberately no flag to
    /// bypass it, since installing a hook amounts to arbitrary code
    /// execution inside that provider's sessions. Declining answers with
    /// failure code `integration-declined`.
    case integrationEnable(provider: AgentProvider)
    /// Repair `provider`'s integration, or every integration that needs
    /// repair when `provider` is nil. Same human confirmation as
    /// `integrationEnable`.
    case integrationRepair(provider: AgentProvider?)
}

public enum ControlResponse: Equatable, Sendable {
    case list(panes: [ControlPaneInfo])
    /// The pane ID created or split, in response to `newTab`/`split`.
    case pane(paneID: String)
    case ok
    case content(ControlPaneContent)
    case waitResult(state: String?, timedOut: Bool)
    /// Answer to `events`: `records` newer than the request's
    /// `afterSequence` (empty when establishing a cursor, or when the
    /// poll timed out), `latestSequence` the fresh cursor to pass as the
    /// next call's `--after`, and `timedOut` true only when the deadline
    /// was reached without a new event arriving.
    case events(
        records: [ControlAgentEventRecord],
        latestSequence: UInt64,
        timedOut: Bool
    )
    case failure(code: String)

    case agentJob(AgentJobSnapshot)
    case agentWaitResult(job: AgentJobSnapshot, timedOut: Bool)
    case agentResult(job: AgentJobSnapshot, content: ControlPaneContent)

    /// Answer to every `integration*` request: the fresh status of all
    /// providers, so `enable`/`repair` callers see the state they produced
    /// without a second `list` round-trip.
    case integrationStatuses([ControlIntegrationInfo])
}

extension ControlRequest: Codable {
    private enum RequestType: String, Codable {
        case list
        case newTab
        case split
        case send
        case sendKey
        case read
        case wait
        case closePane
        case focus
        case setPaneStatus
        case events
        case spawnAgent
        case waitAgent
        case agentResult
        case sendAgent
        case focusAgent
        case closeAgent
        case integrationList
        case integrationEnable
        case integrationRepair
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case paneID
        case direction
        case workingDirectory
        case text
        case pressEnter
        case key
        case modifiers
        case until
        case timeoutSeconds
        case anchorPaneID
        case provider
        case cwd
        case access
        case model
        case task
        case label
        case jobID
        case command
        case status
        case afterSequence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(RequestType.self, forKey: .type)
        switch type {
        case .list:
            self = .list
        case .newTab:
            self = .newTab(
                workingDirectory: try container.decodeIfPresent(
                    String.self,
                    forKey: .workingDirectory
                ),
                command: try container.decodeIfPresent(
                    String.self,
                    forKey: .command
                )
            )
        case .split:
            self = .split(
                paneID: try container.decode(String.self, forKey: .paneID),
                direction: try container.decode(
                    ControlSplitDirection.self,
                    forKey: .direction
                ),
                workingDirectory: try container.decodeIfPresent(
                    String.self,
                    forKey: .workingDirectory
                ),
                command: try container.decodeIfPresent(
                    String.self,
                    forKey: .command
                )
            )
        case .send:
            self = .send(
                paneID: try container.decode(String.self, forKey: .paneID),
                text: try container.decode(String.self, forKey: .text),
                pressEnter: try container.decode(
                    Bool.self,
                    forKey: .pressEnter
                )
            )
        case .sendKey:
            self = .sendKey(
                paneID: try container.decode(String.self, forKey: .paneID),
                key: try container.decode(String.self, forKey: .key),
                modifiers: try container.decode(
                    [String].self,
                    forKey: .modifiers
                )
            )
        case .read:
            self = .read(
                paneID: try container.decode(String.self, forKey: .paneID)
            )
        case .wait:
            self = .wait(
                paneID: try container.decode(String.self, forKey: .paneID),
                until: try container.decode(
                    ControlWaitCondition.self,
                    forKey: .until
                ),
                timeoutSeconds: try container.decode(
                    Double.self,
                    forKey: .timeoutSeconds
                )
            )
        case .closePane:
            self = .closePane(
                paneID: try container.decode(String.self, forKey: .paneID)
            )
        case .focus:
            self = .focus(
                paneID: try container.decode(String.self, forKey: .paneID)
            )
        case .setPaneStatus:
            self = .setPaneStatus(
                paneID: try container.decode(String.self, forKey: .paneID),
                status: try container.decodeIfPresent(
                    String.self,
                    forKey: .status
                )
            )
        case .events:
            self = .events(
                afterSequence: try container.decode(
                    UInt64.self,
                    forKey: .afterSequence
                ),
                timeoutSeconds: try container.decode(
                    Double.self,
                    forKey: .timeoutSeconds
                )
            )
        case .spawnAgent:
            self = .spawnAgent(
                anchorPaneID: try container.decode(
                    String.self,
                    forKey: .anchorPaneID
                ),
                direction: try container.decode(
                    ControlSplitDirection.self,
                    forKey: .direction
                ),
                provider: try container.decode(
                    AgentWorkerProvider.self,
                    forKey: .provider
                ),
                cwd: try container.decodeIfPresent(
                    String.self,
                    forKey: .cwd
                ),
                access: try container.decode(
                    AgentAccessPolicy.self,
                    forKey: .access
                ),
                model: try container.decodeIfPresent(
                    String.self,
                    forKey: .model
                ),
                task: try container.decode(String.self, forKey: .task),
                label: try container.decodeIfPresent(
                    String.self,
                    forKey: .label
                )
            )
        case .waitAgent:
            self = .waitAgent(
                jobID: try container.decode(AgentJobID.self, forKey: .jobID),
                until: try container.decode(
                    AgentWaitCondition.self,
                    forKey: .until
                ),
                timeoutSeconds: try container.decode(
                    Double.self,
                    forKey: .timeoutSeconds
                )
            )
        case .agentResult:
            self = .agentResult(
                jobID: try container.decode(AgentJobID.self, forKey: .jobID)
            )
        case .sendAgent:
            self = .sendAgent(
                jobID: try container.decode(AgentJobID.self, forKey: .jobID),
                text: try container.decode(String.self, forKey: .text),
                pressEnter: try container.decode(
                    Bool.self,
                    forKey: .pressEnter
                )
            )
        case .focusAgent:
            self = .focusAgent(
                jobID: try container.decode(AgentJobID.self, forKey: .jobID)
            )
        case .closeAgent:
            self = .closeAgent(
                jobID: try container.decode(AgentJobID.self, forKey: .jobID)
            )
        case .integrationList:
            self = .integrationList
        case .integrationEnable:
            self = .integrationEnable(
                provider: try container.decode(
                    AgentProvider.self,
                    forKey: .provider
                )
            )
        case .integrationRepair:
            self = .integrationRepair(
                provider: try container.decodeIfPresent(
                    AgentProvider.self,
                    forKey: .provider
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .list:
            try container.encode(RequestType.list, forKey: .type)
        case let .newTab(workingDirectory, command):
            try container.encode(RequestType.newTab, forKey: .type)
            try container.encodeIfPresent(
                workingDirectory,
                forKey: .workingDirectory
            )
            try container.encodeIfPresent(command, forKey: .command)
        case let .split(paneID, direction, workingDirectory, command):
            try container.encode(RequestType.split, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(direction, forKey: .direction)
            try container.encodeIfPresent(
                workingDirectory,
                forKey: .workingDirectory
            )
            try container.encodeIfPresent(command, forKey: .command)
        case let .send(paneID, text, pressEnter):
            try container.encode(RequestType.send, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(text, forKey: .text)
            try container.encode(pressEnter, forKey: .pressEnter)
        case let .sendKey(paneID, key, modifiers):
            try container.encode(RequestType.sendKey, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(key, forKey: .key)
            try container.encode(modifiers, forKey: .modifiers)
        case let .read(paneID):
            try container.encode(RequestType.read, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
        case let .wait(paneID, until, timeoutSeconds):
            try container.encode(RequestType.wait, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(until, forKey: .until)
            try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        case let .closePane(paneID):
            try container.encode(RequestType.closePane, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
        case let .focus(paneID):
            try container.encode(RequestType.focus, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
        case let .setPaneStatus(paneID, status):
            try container.encode(RequestType.setPaneStatus, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encodeIfPresent(status, forKey: .status)
        case let .events(afterSequence, timeoutSeconds):
            try container.encode(RequestType.events, forKey: .type)
            try container.encode(afterSequence, forKey: .afterSequence)
            try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        case let .spawnAgent(
            anchorPaneID, direction, provider, cwd, access, model, task, label
        ):
            try container.encode(RequestType.spawnAgent, forKey: .type)
            try container.encode(anchorPaneID, forKey: .anchorPaneID)
            try container.encode(direction, forKey: .direction)
            try container.encode(provider, forKey: .provider)
            try container.encodeIfPresent(cwd, forKey: .cwd)
            try container.encode(access, forKey: .access)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encode(task, forKey: .task)
            try container.encodeIfPresent(label, forKey: .label)
        case let .waitAgent(jobID, until, timeoutSeconds):
            try container.encode(RequestType.waitAgent, forKey: .type)
            try container.encode(jobID, forKey: .jobID)
            try container.encode(until, forKey: .until)
            try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        case let .agentResult(jobID):
            try container.encode(RequestType.agentResult, forKey: .type)
            try container.encode(jobID, forKey: .jobID)
        case let .sendAgent(jobID, text, pressEnter):
            try container.encode(RequestType.sendAgent, forKey: .type)
            try container.encode(jobID, forKey: .jobID)
            try container.encode(text, forKey: .text)
            try container.encode(pressEnter, forKey: .pressEnter)
        case let .focusAgent(jobID):
            try container.encode(RequestType.focusAgent, forKey: .type)
            try container.encode(jobID, forKey: .jobID)
        case let .closeAgent(jobID):
            try container.encode(RequestType.closeAgent, forKey: .type)
            try container.encode(jobID, forKey: .jobID)
        case .integrationList:
            try container.encode(RequestType.integrationList, forKey: .type)
        case let .integrationEnable(provider):
            try container.encode(RequestType.integrationEnable, forKey: .type)
            try container.encode(provider, forKey: .provider)
        case let .integrationRepair(provider):
            try container.encode(RequestType.integrationRepair, forKey: .type)
            try container.encodeIfPresent(provider, forKey: .provider)
        }
    }
}

extension ControlResponse: Codable {
    private enum ResponseType: String, Codable {
        case list
        case pane
        case ok
        case content
        case waitResult
        case events
        case failure
        case agentJob
        case agentWaitResult
        case agentResult
        case integrationStatuses
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case panes
        case paneID
        case content
        case state
        case timedOut
        case code
        case job
        case integrations
        case records
        case latestSequence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ResponseType.self, forKey: .type)
        switch type {
        case .list:
            self = .list(
                panes: try container.decode(
                    [ControlPaneInfo].self,
                    forKey: .panes
                )
            )
        case .pane:
            self = .pane(
                paneID: try container.decode(String.self, forKey: .paneID)
            )
        case .ok:
            self = .ok
        case .content:
            self = .content(
                try container.decode(ControlPaneContent.self, forKey: .content)
            )
        case .waitResult:
            self = .waitResult(
                state: try container.decodeIfPresent(
                    String.self,
                    forKey: .state
                ),
                timedOut: try container.decode(Bool.self, forKey: .timedOut)
            )
        case .events:
            self = .events(
                records: try container.decode(
                    [ControlAgentEventRecord].self,
                    forKey: .records
                ),
                latestSequence: try container.decode(
                    UInt64.self,
                    forKey: .latestSequence
                ),
                timedOut: try container.decode(Bool.self, forKey: .timedOut)
            )
        case .failure:
            self = .failure(
                code: try container.decode(String.self, forKey: .code)
            )
        case .agentJob:
            self = .agentJob(
                try container.decode(AgentJobSnapshot.self, forKey: .job)
            )
        case .agentWaitResult:
            self = .agentWaitResult(
                job: try container.decode(
                    AgentJobSnapshot.self,
                    forKey: .job
                ),
                timedOut: try container.decode(Bool.self, forKey: .timedOut)
            )
        case .agentResult:
            self = .agentResult(
                job: try container.decode(
                    AgentJobSnapshot.self,
                    forKey: .job
                ),
                content: try container.decode(
                    ControlPaneContent.self,
                    forKey: .content
                )
            )
        case .integrationStatuses:
            self = .integrationStatuses(
                try container.decode(
                    [ControlIntegrationInfo].self,
                    forKey: .integrations
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .list(panes):
            try container.encode(ResponseType.list, forKey: .type)
            try container.encode(panes, forKey: .panes)
        case let .pane(paneID):
            try container.encode(ResponseType.pane, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
        case .ok:
            try container.encode(ResponseType.ok, forKey: .type)
        case let .content(content):
            try container.encode(ResponseType.content, forKey: .type)
            try container.encode(content, forKey: .content)
        case let .waitResult(state, timedOut):
            try container.encode(ResponseType.waitResult, forKey: .type)
            try container.encodeIfPresent(state, forKey: .state)
            try container.encode(timedOut, forKey: .timedOut)
        case let .events(records, latestSequence, timedOut):
            try container.encode(ResponseType.events, forKey: .type)
            try container.encode(records, forKey: .records)
            try container.encode(latestSequence, forKey: .latestSequence)
            try container.encode(timedOut, forKey: .timedOut)
        case let .failure(code):
            try container.encode(ResponseType.failure, forKey: .type)
            try container.encode(code, forKey: .code)
        case let .agentJob(job):
            try container.encode(ResponseType.agentJob, forKey: .type)
            try container.encode(job, forKey: .job)
        case let .agentWaitResult(job, timedOut):
            try container.encode(ResponseType.agentWaitResult, forKey: .type)
            try container.encode(job, forKey: .job)
            try container.encode(timedOut, forKey: .timedOut)
        case let .agentResult(job, content):
            try container.encode(ResponseType.agentResult, forKey: .type)
            try container.encode(job, forKey: .job)
            try container.encode(content, forKey: .content)
        case let .integrationStatuses(integrations):
            try container.encode(
                ResponseType.integrationStatuses,
                forKey: .type
            )
            try container.encode(integrations, forKey: .integrations)
        }
    }
}

public enum ControlMessageCodec {
    public static func encode(_ request: ControlRequest) throws -> Data {
        try JSONEncoder().encode(request)
    }

    public static func decode(_ data: Data) throws -> ControlRequest {
        try JSONDecoder().decode(ControlRequest.self, from: data)
    }

    public static func encode(_ response: ControlResponse) throws -> Data {
        try JSONEncoder().encode(response)
    }

    public static func decode(_ data: Data) throws -> ControlResponse {
        try JSONDecoder().decode(ControlResponse.self, from: data)
    }
}
