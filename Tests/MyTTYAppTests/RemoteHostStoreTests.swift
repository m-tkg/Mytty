import Foundation
import MyTTYRemoteKit
import Testing

@testable import MyTTYApp

@Suite("Remote host store")
struct RemoteHostStoreTests {
    private func makeStore() -> (RemoteHostStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("remote-hosts.json")
        return (RemoteHostStore(fileURL: url), url)
    }

    private func host(
        id: String,
        name: String = "Studio"
    ) -> PairedMac {
        PairedMac(
            deviceID: id,
            deviceSecretBase64: Data("secret".utf8).base64EncodedString(),
            macName: "studio._mytty._tcp",
            displayName: name
        )
    }

    @Test("a missing file reads as no hosts rather than an error")
    func missingFileLoadsEmpty() throws {
        let (store, _) = makeStore()
        #expect(try store.load().isEmpty)
    }

    @Test("adds and reads back a host")
    func addAndLoad() throws {
        let (store, _) = makeStore()
        try store.add(host(id: "a"))
        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].deviceID == "a")
        #expect(loaded[0].displayName == "Studio")
    }

    @Test("re-adding the same host replaces it instead of duplicating")
    func addReplacesByID() throws {
        let (store, _) = makeStore()
        try store.add(host(id: "a", name: "Old"))
        try store.add(host(id: "a", name: "New"))
        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].displayName == "New")
    }

    @Test("removes a host and rejects an unknown id")
    func remove() throws {
        let (store, _) = makeStore()
        try store.add(host(id: "a"))
        try store.add(host(id: "b"))
        let remaining = try store.remove(id: "a")
        #expect(remaining.map(\.deviceID) == ["b"])
        #expect(throws: RemoteHostStoreError.hostNotFound("zz")) {
            try store.remove(id: "zz")
        }
    }

    @Test("renames a host and rejects an unknown id")
    func rename() throws {
        let (store, _) = makeStore()
        try store.add(host(id: "a", name: "Old"))
        let renamed = try store.rename(id: "a", name: "Desk")
        #expect(renamed[0].displayName == "Desk")
        #expect(try store.host(id: "a")?.displayName == "Desk")
        #expect(throws: RemoteHostStoreError.hostNotFound("zz")) {
            try store.rename(id: "zz", name: "x")
        }
    }

    @Test("writes owner-only so pairing secrets are not world-readable")
    func filePermissions() throws {
        let (store, url) = makeStore()
        try store.add(host(id: "a"))
        let attributes = try FileManager.default
            .attributesOfItem(atPath: url.path)
        let permissions = try #require(
            attributes[.posixPermissions] as? NSNumber
        )
        #expect(permissions.int16Value == 0o600)
    }

    @Test("an empty file reads as no hosts")
    func emptyFileLoadsEmpty() throws {
        let (store, url) = makeStore()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url)
        #expect(try store.load().isEmpty)
    }
}
