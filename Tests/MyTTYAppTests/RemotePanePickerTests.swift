import MyTTYRemoteKit
import Testing

@testable import MyTTYApp

@Suite("Remote pane picker")
struct RemotePanePickerTests {
    private func mac(_ id: String) -> PairedMac {
        PairedMac(
            deviceID: id,
            deviceSecretBase64: "",
            macName: "\(id)-service",
            displayName: id
        )
    }

    @Test("a preselected Mac wins over the default first host")
    func preselectedHostWins() {
        let hosts = [mac("desktop"), mac("studio")]
        #expect(
            RemotePanePickerModel.initialHostID(
                preselected: "studio",
                hosts: hosts
            ) == "studio"
        )
    }

    @Test("no preselection falls back to the first host")
    func fallsBackToFirstHost() {
        let hosts = [mac("desktop"), mac("studio")]
        #expect(
            RemotePanePickerModel.initialHostID(
                preselected: nil,
                hosts: hosts
            ) == "desktop"
        )
    }

    @Test("a stale preselection is ignored, not selected blindly")
    func ignoresUnknownPreselection() {
        let hosts = [mac("desktop")]
        #expect(
            RemotePanePickerModel.initialHostID(
                preselected: "unpaired",
                hosts: hosts
            ) == "desktop"
        )
        #expect(
            RemotePanePickerModel.initialHostID(
                preselected: "unpaired",
                hosts: []
            ) == nil
        )
    }
}
