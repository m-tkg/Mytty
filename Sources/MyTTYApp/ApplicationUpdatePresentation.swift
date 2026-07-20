import AppKit
import SwiftUI

struct ApplicationUpdateControlsView: View {
    @ObservedObject var model: ApplicationUpdateModel
    let localizer: MyTTYLocalizer
    var updatesEnabled = ApplicationIdentity.supportsSelfUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent(localizer[.currentVersion]) {
                Text(
                    verbatim: "\(ApplicationIdentity.displayName) "
                        + model.currentVersion.description
                )
                    .foregroundStyle(.secondary)
            }

            if let statusText {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(statusText)
                        .foregroundStyle(statusColor)
                }
            }

            HStack(spacing: 10) {
                Button {
                    let includePrereleases = NSEvent.modifierFlags
                        .contains(.option)
                    Task {
                        await model.checkForUpdates(
                            includePrereleases: includePrereleases
                        )
                    }
                } label: {
                    Label(
                        localizer[.checkForUpdates],
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(!updatesEnabled || !model.canCheck)
                .help(localizer[.checkForUpdatesPrereleaseHint])

                if updatesEnabled && model.canUpdate {
                    Button {
                        Task { await model.installAvailableUpdate() }
                    } label: {
                        Label(
                            localizer[.update],
                            systemImage: "arrow.down.app"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var isBusy: Bool {
        switch model.phase {
        case .checking, .installing:
            true
        default:
            false
        }
    }

    private var statusText: String? {
        switch model.phase {
        case .idle:
            nil
        case .checking:
            localizer[.checkingForUpdates]
        case .upToDate:
            localizer[.upToDate]
        case let .available(release):
            String(
                format: localizer[.updateAvailableFormat],
                release.version.description
            )
        case .installing:
            localizer[.installingUpdate]
        case .installed:
            localizer[.updateInstalled]
        case let .failed(failure):
            switch failure {
            case .check:
                localizer[.updateCheckFailed]
            case .installation:
                localizer[.updateInstallFailed]
            }
        }
    }

    private var statusColor: Color {
        if case .failed = model.phase {
            return .red
        }
        return .secondary
    }
}

struct UpdatesSettingsView: View {
    @ObservedObject var model: ApplicationUpdateModel
    let localizer: MyTTYLocalizer

    var body: some View {
        Form {
            Section(localizer[.updates]) {
                ApplicationUpdateControlsView(
                    model: model,
                    localizer: localizer
                )
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

struct ApplicationAboutView: View {
    @ObservedObject var model: ApplicationUpdateModel
    let localizer: MyTTYLocalizer

    var body: some View {
        VStack(spacing: 18) {
            if let icon = ApplicationIcon.image {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
            }

            VStack(spacing: 4) {
                Text(ApplicationIdentity.displayName)
                    .font(.system(size: 24, weight: .semibold))
                Text(
                    verbatim: localizer[.currentVersion] + " "
                        + model.currentVersion.description
                )
                    .foregroundStyle(.secondary)
            }

            Divider()

            ApplicationUpdateControlsView(
                model: model,
                localizer: localizer
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .frame(width: 440)
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    private let model: ApplicationUpdateModel
    private let hostingController: NSHostingController<ApplicationAboutView>

    init(model: ApplicationUpdateModel, localizer: MyTTYLocalizer) {
        self.model = model
        hostingController = NSHostingController(
            rootView: ApplicationAboutView(
                model: model,
                localizer: localizer
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localizer[.aboutMyTTY]
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        // Excluded from macOS's automatic window-state restoration so a
        // frame saved from a previous launch never overrides present()'s
        // centering.
        window.isRestorable = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        // NSHostingController resolves its window's content size
        // asynchronously after the window is shown, which left center()
        // computing against the window's initial (effectively zero) size.
        // Asking SwiftUI for the fitting size up front keeps window.center()
        // accurate on every presentation.
        let idealSize = hostingController.sizeThatFits(
            in: CGSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        )
        window?.setContentSize(idealSize)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if ApplicationIdentity.supportsSelfUpdate {
            let automation = ApplicationUpdateAutomation(model: model)
            Task {
                await automation.check(trigger: .about)
            }
        }
    }

    func updateLocalization(_ localizer: MyTTYLocalizer) {
        window?.title = localizer[.aboutMyTTY]
        hostingController.rootView = ApplicationAboutView(
            model: model,
            localizer: localizer
        )
    }
}
