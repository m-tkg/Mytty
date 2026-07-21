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

    public init(
        paneID: String,
        windowID: String,
        tabID: String,
        title: String,
        command: String,
        workingDirectory: String?,
        isActive: Bool,
        provider: String?,
        agentState: String?
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
    case newTab(workingDirectory: String?)
    case split(
        paneID: String,
        direction: ControlSplitDirection,
        workingDirectory: String?
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
}

public enum ControlResponse: Equatable, Sendable {
    case list(panes: [ControlPaneInfo])
    /// The pane ID created or split, in response to `newTab`/`split`.
    case pane(paneID: String)
    case ok
    case content(ControlPaneContent)
    case waitResult(state: String?, timedOut: Bool)
    case failure(code: String)

    case agentJob(AgentJobSnapshot)
    case agentWaitResult(job: AgentJobSnapshot, timedOut: Bool)
    case agentResult(job: AgentJobSnapshot, content: ControlPaneContent)
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
        case spawnAgent
        case waitAgent
        case agentResult
        case sendAgent
        case focusAgent
        case closeAgent
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
        case task
        case label
        case jobID
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
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .list:
            try container.encode(RequestType.list, forKey: .type)
        case let .newTab(workingDirectory):
            try container.encode(RequestType.newTab, forKey: .type)
            try container.encodeIfPresent(
                workingDirectory,
                forKey: .workingDirectory
            )
        case let .split(paneID, direction, workingDirectory):
            try container.encode(RequestType.split, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(direction, forKey: .direction)
            try container.encodeIfPresent(
                workingDirectory,
                forKey: .workingDirectory
            )
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
        case let .spawnAgent(
            anchorPaneID, direction, provider, cwd, access, task, label
        ):
            try container.encode(RequestType.spawnAgent, forKey: .type)
            try container.encode(anchorPaneID, forKey: .anchorPaneID)
            try container.encode(direction, forKey: .direction)
            try container.encode(provider, forKey: .provider)
            try container.encodeIfPresent(cwd, forKey: .cwd)
            try container.encode(access, forKey: .access)
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
        case failure
        case agentJob
        case agentWaitResult
        case agentResult
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
