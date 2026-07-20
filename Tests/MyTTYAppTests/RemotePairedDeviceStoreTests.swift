import Foundation
import Testing

@testable import MyTTYApp

@Suite("Remote paired device store")
struct RemotePairedDeviceStoreTests {
    @Test("returns no devices before anything is stored")
    func loadsEmptyWhenFileIsMissing() throws {
        let store = try makeStore()
        #expect(try store.load().isEmpty)
    }

    @Test("persists an added device across store instances")
    func persistsAcrossInstances() throws {
        let fileURL = try makeFileURL()
        let store = RemotePairedDeviceStore(fileURL: fileURL)
        let device = RemotePairedDevice(
            id: "device-1",
            name: "iPhone",
            secretBase64: "c2VjcmV0",
            pairedAt: Date(timeIntervalSince1970: 1_000)
        )
        try store.add(device)

        let reloaded = RemotePairedDeviceStore(fileURL: fileURL)
        #expect(try reloaded.load() == [device])
    }

    @Test("stores and clears a device's push registration")
    func updatesPushRegistration() throws {
        let store = try makeStore()
        try store.add(
            RemotePairedDevice(
                id: "device-1",
                name: "iPhone",
                secretBase64: "c2VjcmV0",
                pairedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        #expect(try store.device(id: "device-1")?.pushRelayID == nil)

        try store.updatePushRegistration(
            id: "device-1",
            pushRelayID: "relay-1",
            relaySecretBase64: "c2VjcmV0"
        )
        let registered = try #require(try store.device(id: "device-1"))
        #expect(registered.pushRelayID == "relay-1")
        #expect(registered.pushRelaySecretBase64 == "c2VjcmV0")
        // Everything else about the device survives the update.
        #expect(registered.name == "iPhone")
        #expect(registered.secretBase64 == "c2VjcmV0")

        try store.updatePushRegistration(
            id: "device-1",
            pushRelayID: nil,
            relaySecretBase64: nil
        )
        #expect(try store.device(id: "device-1")?.pushRelayID == nil)
    }

    @Test("rejects a push registration for an unknown device")
    func rejectsPushRegistrationForUnknownDevice() throws {
        let store = try makeStore()
        #expect(
            throws: RemotePairedDeviceStoreError.deviceNotFound("missing")
        ) {
            try store.updatePushRegistration(
                id: "missing",
                pushRelayID: "relay-1",
                relaySecretBase64: "c2VjcmV0"
            )
        }
    }

    /// Devices paired before push existed have no such fields on disk;
    /// they must still load rather than failing the whole store.
    @Test("loads devices written before push registration existed")
    func loadsDevicesWithoutPushFields() throws {
        let fileURL = try makeFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(
            #"[{"id":"device-1","name":"iPhone","pairedAt":1000,"secretBase64":"c2VjcmV0"}]"#.utf8
        ).write(to: fileURL)

        let devices = try RemotePairedDeviceStore(fileURL: fileURL).load()
        #expect(devices.count == 1)
        #expect(devices.first?.pushRelayID == nil)
    }

    @Test("replaces a device with the same id instead of duplicating it")
    func addReplacesExistingDeviceByID() throws {
        let store = try makeStore()
        let original = RemotePairedDevice(
            id: "device-1",
            name: "iPhone",
            secretBase64: "b25l",
            pairedAt: Date(timeIntervalSince1970: 1_000)
        )
        let renamed = RemotePairedDevice(
            id: "device-1",
            name: "iPhone (renamed)",
            secretBase64: "dHdv",
            pairedAt: Date(timeIntervalSince1970: 2_000)
        )
        try store.add(original)
        try store.add(renamed)

        #expect(try store.load() == [renamed])
    }

    @Test("removes a device by id")
    func removesDeviceByID() throws {
        let store = try makeStore()
        let device = RemotePairedDevice(
            id: "device-1",
            name: "iPhone",
            secretBase64: "b25l",
            pairedAt: Date(timeIntervalSince1970: 1_000)
        )
        try store.add(device)
        try store.remove(id: "device-1")

        #expect(try store.load().isEmpty)
    }

    @Test("removing an unknown device throws")
    func removingUnknownDeviceThrows() throws {
        let store = try makeStore()
        #expect(throws: RemotePairedDeviceStoreError.deviceNotFound("missing")) {
            try store.remove(id: "missing")
        }
    }

    @Test("renames a device without changing its pairing credentials")
    func renamesDeviceByID() throws {
        let store = try makeStore()
        let device = RemotePairedDevice(
            id: "device-1",
            name: "iPhone",
            secretBase64: "b25l",
            pairedAt: Date(timeIntervalSince1970: 1_000)
        )
        try store.add(device)

        let devices = try store.rename(id: "device-1", name: "Desk iPhone")

        #expect(
            devices == [
                RemotePairedDevice(
                    id: "device-1",
                    name: "Desk iPhone",
                    secretBase64: "b25l",
                    pairedAt: Date(timeIntervalSince1970: 1_000)
                )
            ]
        )
    }

    @Test("renaming an unknown device throws")
    func renamingUnknownDeviceThrows() throws {
        let store = try makeStore()
        #expect(throws: RemotePairedDeviceStoreError.deviceNotFound("missing")) {
            try store.rename(id: "missing", name: "Desk iPhone")
        }
    }

    @Test("writes the file with owner-only permissions")
    func writesWithRestrictedPermissions() throws {
        let fileURL = try makeFileURL()
        let store = RemotePairedDeviceStore(fileURL: fileURL)
        try store.add(
            RemotePairedDevice(
                id: "device-1",
                name: "iPhone",
                secretBase64: "b25l",
                pairedAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        let permissions = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    private func makeFileURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("remote-devices.json", isDirectory: false)
    }

    private func makeStore() throws -> RemotePairedDeviceStore {
        RemotePairedDeviceStore(fileURL: try makeFileURL())
    }
}
