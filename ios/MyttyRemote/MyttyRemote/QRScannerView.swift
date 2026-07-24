import AVFoundation
import SwiftUI

/// Camera-based QR scanner used to read the Mac's pairing QR code. Wraps
/// `AVCaptureSession` + `AVCaptureMetadataOutput` (`.qr`) directly rather
/// than a higher-level scanning API, since all this needs is "read one QR
/// code and report its raw string back".
struct QRScannerView: UIViewControllerRepresentable {
    /// Called on the main thread with the raw string payload of every QR
    /// code the camera recognizes (the caller decides what, if anything,
    /// to do with a given scan — invalid payloads are expected to be
    /// ignored so the camera keeps scanning).
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(
        _ uiViewController: ScannerViewController,
        context: Context
    ) {}
}

// `AVCaptureMetadataOutputObjectsDelegate` predates Swift concurrency
// isolation annotations, so its requirement isn't statically known to run
// on the main actor even though `configureSession` pins the callback queue
// to `.main`; `@preconcurrency` tells the compiler to trust that instead
// of rejecting the conformance outright.
final class ScannerViewController: UIViewController,
    @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !session.isRunning else { return }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard session.isRunning else { return }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // Restricted to QR after being added to the session: the output's
        // supported types are only known once it's attached.
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  readable.type == .qr,
                  let value = readable.stringValue
            else { continue }
            onScan?(value)
        }
    }
}
