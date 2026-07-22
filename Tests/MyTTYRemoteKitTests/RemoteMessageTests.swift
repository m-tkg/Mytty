import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite
struct RemoteMessageTests {
    @Test
    func encodesAndDecodesScrollPane() throws {
        let message = RemoteMessage.scrollPane(paneID: "pane-1", deltaY: -3)
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func registerPushRelayRoundTrips() throws {
        let message = RemoteMessage.registerPushRelay(
            pushID: UUID().uuidString,
            relaySecretBase64: Data(repeating: 7, count: 32)
                .base64EncodedString()
        )
        let data = try RemoteMessageCodec.encode(message)
        #expect(try RemoteMessageCodec.decode(data) == message)
    }

    /// Protocol-2 clients still send this. Decoding must keep working or
    /// the server drops their connection on every push registration.
    @Test
    func registerPushTokenFromOlderClientsStillDecodes() throws {
        let message = RemoteMessage.registerPushToken(
            token: String(repeating: "ab", count: 32),
            bundleID: "com.example.MyttyRemote",
            environment: "sandbox"
        )
        let data = try RemoteMessageCodec.encode(message)
        #expect(try RemoteMessageCodec.decode(data) == message)
    }

    /// Clients decide whether to send `registerPushToken` from the version
    /// the snapshot reports, so a snapshot from a server predating the
    /// field must still decode — as nil, not as a failure.
    @Test
    func snapshotFromOlderServersDecodesWithoutProtocolVersion() throws {
        let data = Data(#"{"windows":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(
            RemoteSessionSnapshot.self,
            from: data
        )
        #expect(snapshot.serverProtocolVersion == nil)
    }

    @Test
    func paneContentRoundTripsAltScreen() throws {
        let message = RemoteMessage.paneContent(
            paneID: "pane-1",
            text: "hello",
            cursorRow: 0,
            cursorColumn: 1,
            styledLines: nil,
            altScreen: true
        )
        let data = try RemoteMessageCodec.encode(message)
        #expect(try RemoteMessageCodec.decode(data) == message)
    }

    @Test
    func paneContentFromOlderServersDecodesWithoutAltScreen() throws {
        let json = Data(
            #"{"type":"paneContent","paneID":"pane-1","text":"hi"}"#.utf8
        )
        let decoded = try RemoteMessageCodec.decode(json)
        #expect(
            decoded == .paneContent(
                paneID: "pane-1",
                text: "hi",
                cursorRow: nil,
                cursorColumn: nil,
                styledLines: nil,
                altScreen: nil
            )
        )
    }

    @Test
    func encodesAndDecodesPairRequest() throws {
        let message = RemoteMessage.pairRequest(
            deviceName: "iPhone",
            code: "123456"
        )
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesHelloWithoutLeakingASecret() throws {
        let message = RemoteMessage.hello(
            deviceID: "device-1",
            protocolVersion: RemoteMessageCodec.protocolVersion
        )
        let data = try RemoteMessageCodec.encode(message)
        #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesSnapshot() throws {
        let snapshot = RemoteSessionSnapshot(windows: [
            RemoteWindow(
                id: "window-1",
                tabs: [
                    RemoteTab(
                        id: "tab-1",
                        title: "zsh",
                        panes: [
                            RemotePane(
                                id: "pane-1",
                                title: "zsh",
                                command: "zsh",
                                location: "/Users/masaki",
                                kind: .terminal,
                                isActive: true
                            ),
                        ]
                    ),
                ]
            ),
        ])
        let message = RemoteMessage.snapshot(snapshot)
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesSendInput() throws {
        let message = RemoteMessage.sendInput(
            paneID: "pane-1",
            text: "ls -la",
            pressEnter: true
        )
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesPaneContentWithAndWithoutCursor() throws {
        let withCursor = RemoteMessage.paneContent(
            paneID: "pane-1",
            text: "hello",
            cursorRow: 3,
            cursorColumn: 7,
            styledLines: nil,
            altScreen: nil
        )
        let decodedWithCursor = try RemoteMessageCodec.decode(
            try RemoteMessageCodec.encode(withCursor)
        )
        #expect(decodedWithCursor == withCursor)

        let withoutCursor = RemoteMessage.paneContent(
            paneID: "pane-1",
            text: "hello",
            cursorRow: nil,
            cursorColumn: nil,
            styledLines: nil,
            altScreen: nil
        )
        let decodedWithoutCursor = try RemoteMessageCodec.decode(
            try RemoteMessageCodec.encode(withoutCursor)
        )
        #expect(decodedWithoutCursor == withoutCursor)
    }

    @Test
    func encodesAndDecodesPaneContentWithStyledLines() throws {
        let message = RemoteMessage.paneContent(
            paneID: "pane-1",
            text: "AB",
            cursorRow: 0,
            cursorColumn: 1,
            styledLines: [
                RemoteStyledLine(spans: [
                    RemoteTextSpan(
                        text: "A",
                        foreground: 0xFF0000,
                        bold: true
                    ),
                    RemoteTextSpan(
                        text: "B",
                        background: 0x00FF00,
                        inverse: true
                    ),
                ]),
                RemoteStyledLine(spans: []),
            ],
            altScreen: nil
        )
        let decoded = try RemoteMessageCodec.decode(
            try RemoteMessageCodec.encode(message)
        )
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesSendKey() throws {
        let message = RemoteMessage.sendKey(
            paneID: "pane-1",
            key: "escape",
            modifiers: ["control", "shift"]
        )
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesNewTab() throws {
        let message = RemoteMessage.newTab(windowID: "window-1")
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesListPaneSchedules() throws {
        let message = RemoteMessage.listPaneSchedules(paneID: "pane-1")
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesPaneSchedulesWithEmptyList() throws {
        let message = RemoteMessage.paneSchedules(
            paneID: "pane-1",
            schedules: []
        )
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesPaneSchedulesWithNonIntegerDate() throws {
        let message = RemoteMessage.paneSchedules(
            paneID: "pane-1",
            schedules: [
                RemotePaneSchedule(
                    id: UUID().uuidString,
                    fireAt: Date(timeIntervalSince1970: 1_700_000_000.5),
                    text: "echo hi",
                    pressEnter: true
                ),
            ]
        )
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesCreatePaneSchedule() throws {
        let message = RemoteMessage.createPaneSchedule(
            paneID: "pane-1",
            schedule: RemotePaneSchedule(
                id: UUID().uuidString,
                fireAt: Date(timeIntervalSince1970: 1_700_000_100),
                text: "ls -la",
                pressEnter: false
            )
        )
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func encodesAndDecodesDeletePaneSchedule() throws {
        let message = RemoteMessage.deletePaneSchedule(
            paneID: "pane-1",
            scheduleID: UUID().uuidString
        )
        let data = try RemoteMessageCodec.encode(message)
        let decoded = try RemoteMessageCodec.decode(data)
        #expect(decoded == message)
    }

    @Test
    func decodingUnknownTypeThrows() {
        let json = Data(#"{"type":"unknown"}"#.utf8)
        #expect(throws: (any Error).self) {
            try RemoteMessageCodec.decode(json)
        }
    }
}

@Suite
struct RemoteFrameReaderTests {
    @Test
    func splitsSingleFrameDeliveredInOneChunk() throws {
        var reader = RemoteFrameReader()
        let message = RemoteMessage.watchPane(paneID: "pane-1")
        let payload = try RemoteMessageCodec.encode(message)
        let frame = RemoteFrameCodec.encode(payload)

        let frames = try reader.append(frame)
        #expect(frames.count == 1)
        #expect(try RemoteMessageCodec.decode(frames[0]) == message)
    }

    @Test
    func splitsMultipleFramesDeliveredInOneChunk() throws {
        var reader = RemoteFrameReader()
        let first = RemoteMessage.watchPane(paneID: "pane-1")
        let second = RemoteMessage.unwatchPane(paneID: "pane-1")
        var combined = RemoteFrameCodec.encode(try RemoteMessageCodec.encode(first))
        combined.append(RemoteFrameCodec.encode(try RemoteMessageCodec.encode(second)))

        let frames = try reader.append(combined)
        #expect(frames.count == 2)
        #expect(try RemoteMessageCodec.decode(frames[0]) == first)
        #expect(try RemoteMessageCodec.decode(frames[1]) == second)
    }

    @Test
    func buffersPartialFrameUntilLengthIsSatisfied() throws {
        var reader = RemoteFrameReader()
        let message = RemoteMessage.failure(code: "unauthorized")
        let frame = RemoteFrameCodec.encode(try RemoteMessageCodec.encode(message))
        let splitPoint = frame.count / 2

        let firstChunk = frame.prefix(splitPoint)
        let secondChunk = frame.suffix(from: splitPoint)

        let firstFrames = try reader.append(Data(firstChunk))
        #expect(firstFrames.isEmpty)

        let secondFrames = try reader.append(Data(secondChunk))
        #expect(secondFrames.count == 1)
        #expect(try RemoteMessageCodec.decode(secondFrames[0]) == message)
    }

    @Test
    func buffersEvenWhenLengthPrefixItselfArrivesInPieces() throws {
        var reader = RemoteFrameReader()
        let message = RemoteMessage.watchPane(paneID: "pane-1")
        let frame = RemoteFrameCodec.encode(try RemoteMessageCodec.encode(message))

        var frames: [Data] = []
        for byte in frame {
            frames += try reader.append(Data([byte]))
        }
        #expect(frames.count == 1)
        #expect(try RemoteMessageCodec.decode(frames[0]) == message)
    }

    @Test
    func rejectsFramesLargerThanTheLimit() throws {
        var reader = RemoteFrameReader()
        let oversizedLength = UInt32(RemoteFrameCodec.maximumFrameSize + 1)
        let prefix = Data([
            UInt8((oversizedLength >> 24) & 0xFF),
            UInt8((oversizedLength >> 16) & 0xFF),
            UInt8((oversizedLength >> 8) & 0xFF),
            UInt8(oversizedLength & 0xFF),
        ])
        #expect(throws: RemoteFrameError.frameTooLarge) {
            _ = try reader.append(prefix)
        }
    }
}
