import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Renders a pairing payload URL as a scannable QR code so the iOS app's
/// camera scanner (see `ios/MyttyRemote/MyttyRemote/PairingView.swift`) can
/// read the high-entropy pairing token without the user typing anything.
/// Kept as its own view so `RemoteAccessSettingsView` doesn't have to own
/// CoreImage plumbing directly.
struct RemotePairingQRCodeView: View {
    let payload: String

    private static let context = CIContext()

    var body: some View {
        if let nsImage = Self.renderQRCode(for: payload) {
            Image(nsImage: nsImage)
                .interpolation(.none)
                .resizable()
                .frame(width: 200, height: 200)
                .accessibilityLabel(Text("Pairing QR code"))
        } else {
            // CoreImage failing on the short URL this carries is
            // effectively unreachable, but degrade to raw text rather than
            // showing nothing pairable at all.
            Text(payload)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private static func renderQRCode(for string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        // The generator emits a 1-point-per-module image; scale up so it
        // renders crisply rather than being upsampled by SwiftUI.
        let scale: CGFloat = 8
        let scaled = outputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent)
        else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: scaled.extent.width, height: scaled.extent.height)
        )
    }
}
