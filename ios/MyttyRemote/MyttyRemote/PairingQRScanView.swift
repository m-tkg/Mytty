import AVFoundation
import MyTTYRemoteKit
import SwiftUI

/// Presents the camera QR scanner (or a permission message) and reports
/// back the first payload that parses as a valid `RemotePairingPayload`.
/// Scans that don't parse — a stray QR code, a truncated read — are
/// silently ignored so the camera keeps scanning instead of surfacing an
/// error for every non-Mytty code that drifts through frame.
struct PairingQRScanView: View {
    let onScanned: (RemotePairingPayload) -> Void
    let onCancel: () -> Void

    @State private var authorizationStatus =
        AVCaptureDevice.authorizationStatus(for: .video)
    @State private var didScan = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan QR Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch authorizationStatus {
        case .authorized:
            scannerView
        case .notDetermined:
            ProgressView("Requesting camera access…")
                .task { await requestAccess() }
        case .denied, .restricted:
            deniedMessage
        @unknown default:
            deniedMessage
        }
    }

    private var scannerView: some View {
        ZStack(alignment: .bottom) {
            QRScannerView { rawValue in
                guard !didScan,
                      let payload = RemotePairingPayload.parse(rawValue)
                else { return }
                didScan = true
                onScanned(payload)
            }
            .ignoresSafeArea()

            Text(
                "Point your camera at the QR code shown in Mytty on your Mac."
            )
            .font(.footnote)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding()
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private var deniedMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Camera Access Needed")
                .font(.headline)
            Text(
                "Mytty needs camera access to scan the pairing QR code "
                    + "shown on your Mac. Enable it in Settings."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString)
                else { return }
                UIApplication.shared.open(url)
            }
        }
        .padding()
    }

    private func requestAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = granted ? .authorized : .denied
    }
}
