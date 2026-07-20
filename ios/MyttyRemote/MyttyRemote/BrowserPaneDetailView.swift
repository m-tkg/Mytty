import MyTTYRemoteKit
import SafariServices
import SwiftUI
import UIKit

/// Detail view for a browser pane. Browser panes have no terminal buffer to
/// mirror (the Mac only serves `paneContent` for Ghostty surfaces), so this
/// view never watches the pane; it shows the pane's title and live URL from
/// the session snapshot and lets the user open the same page on the phone
/// or copy the URL.
struct BrowserPaneDetailView: View {
    let pane: RemotePane
    @ObservedObject var client: RemoteClient

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var safariURL: SafariURL?

    private struct SafariURL: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// Snapshot pushes replace `client.snapshot` whenever the Mac's browser
    /// navigates (`updateBrowserURL` rebroadcasts), so re-resolve this pane
    /// by ID to keep the URL live instead of showing the value captured
    /// when the view was pushed.
    private var currentPane: RemotePane {
        client.snapshot?.pane(withID: pane.id) ?? pane
    }

    private var url: URL? {
        URL(string: currentPane.location)
    }

    /// SFSafariViewController traps on anything but http/https.
    private var isWebURL: Bool {
        let scheme = url?.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !client.isConnected {
                disconnectedBanner
            }

            VStack(spacing: 16) {
                Image(systemName: "safari")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                Text(currentPane.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(currentPane.location)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)

                VStack(spacing: 10) {
                    Button {
                        guard let url else { return }
                        if isWebURL {
                            safariURL = SafariURL(url: url)
                        } else {
                            openURL(url)
                        }
                    } label: {
                        Label("Open on iPhone", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(url == nil)

                    Button {
                        UIPasteboard.general.string = currentPane.location
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentPane.location.isEmpty)
                }
                .frame(maxWidth: 320)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The pane closed on the Mac: pop back to the pane list. Only judged
        // against a snapshot from a live connection — a reconnect clears
        // `snapshot`, and that must not be read as "the pane is gone".
        .onChange(of: client.snapshot) {
            guard client.isConnected, let snapshot = client.snapshot else {
                return
            }
            if snapshot.pane(withID: pane.id) == nil { dismiss() }
        }
        .navigationTitle(currentPane.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $safariURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }

    private var disconnectedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
            VStack(alignment: .leading, spacing: 2) {
                Text(disconnectedTitle)
                    .font(.subheadline.weight(.semibold))
                Text("The URL shown may be out of date.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            if client.state == .connecting {
                ProgressView()
                    .tint(.white)
            } else {
                Button("Reconnect") { client.reconnect() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.25))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.9))
    }

    private var disconnectedTitle: String {
        switch client.state {
        case .connecting: "Reconnecting…"
        case let .failed(message): "Disconnected — \(message)"
        default: "Disconnected"
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(
        _ controller: SFSafariViewController,
        context: Context
    ) {}
}
