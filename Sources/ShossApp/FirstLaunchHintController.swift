import AppKit
import SwiftUI

private final class FirstLaunchHintPanel: NSPanel {
    var dismissAction: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        dismissAction?()
    }
}

private final class FirstLaunchHintHostingView<Content: View>: NSHostingView<Content> {
    private static var cornerRadius: CGFloat { 15 }

    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        nil
    }
}

private struct FirstLaunchHintView: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(red: 0.66, green: 0.48, blue: 0.98))
                .frame(width: 8, height: 8)
                .shadow(color: Color(red: 0.66, green: 0.48, blue: 0.98).opacity(0.8), radius: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text("Screenshoss is ready")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Move the pointer to the notch to open it.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.black.opacity(0.74))
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
        }
    }
}

@MainActor
final class FirstLaunchHintController {
    private static let installationDefaultsKey = "screenshoss.firstLaunchHintInstallationID"
    private static let hintSize = CGSize(width: 292, height: 62)
    private static let notchSpacing: CGFloat = 8

    private let panel: FirstLaunchHintPanel
    private let defaults: UserDefaults
    private let installationID: String
    private var showTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        bundleURL: URL = Bundle.main.bundleURL
    ) {
        self.defaults = defaults
        installationID = Self.installationIdentifier(for: bundleURL)
        panel = FirstLaunchHintPanel(
            contentRect: CGRect(origin: .zero, size: Self.hintSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.contentView = FirstLaunchHintHostingView(rootView: FirstLaunchHintView())
        panel.dismissAction = { [weak self] in
            self?.dismiss()
        }
    }

    deinit {
        showTask?.cancel()
        dismissTask?.cancel()
    }

    func scheduleIfNeeded(
        anchorFrame: CGRect,
        mode: ShelfPresentationMode,
        screen: NSScreen?,
        delay: Duration = .milliseconds(650)
    ) {
        guard shouldShowForCurrentInstallation else { return }

        showTask?.cancel()
        showTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.show(anchorFrame: anchorFrame, mode: mode, screen: screen)
        }
    }

    func updatePlacement(
        anchorFrame: CGRect,
        mode: ShelfPresentationMode,
        screen: NSScreen?
    ) {
        guard panel.isVisible else { return }
        panel.setFrame(
            hintFrame(anchorFrame: anchorFrame, mode: mode, screen: screen),
            display: true
        )
    }

    func dismiss() {
        showTask?.cancel()
        showTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        guard panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
                panel?.alphaValue = 1
            }
        }
    }

    static func installationIdentifier(for bundleURL: URL) -> String {
        let keys: Set<URLResourceKey> = [
            .fileResourceIdentifierKey,
            .creationDateKey,
            .contentModificationDateKey,
        ]
        let values = try? bundleURL.resourceValues(forKeys: keys)

        if let data = values?.fileResourceIdentifier as? NSData {
            return data.base64EncodedString()
        }

        let creation = values?.creationDate?.timeIntervalSince1970 ?? 0
        let modification = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(bundleURL.standardizedFileURL.path)|\(creation)|\(modification)"
    }

    private var shouldShowForCurrentInstallation: Bool {
        defaults.string(forKey: Self.installationDefaultsKey) != installationID
    }

    private func show(anchorFrame: CGRect, mode: ShelfPresentationMode, screen: NSScreen?) {
        let finalFrame = hintFrame(anchorFrame: anchorFrame, mode: mode, screen: screen)
        let startFrame = finalFrame.insetBy(dx: 5, dy: 2)

        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        defaults.set(installationID, forKey: Self.installationDefaultsKey)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }

        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func hintFrame(
        anchorFrame: CGRect,
        mode: ShelfPresentationMode,
        screen: NSScreen?
    ) -> CGRect {
        let size = Self.hintSize
        let proposedOrigin: CGPoint

        switch mode {
        case .top:
            proposedOrigin = CGPoint(
                x: anchorFrame.midX - size.width / 2,
                y: anchorFrame.minY - Self.notchSpacing - size.height
            )
        case .left:
            proposedOrigin = CGPoint(
                x: anchorFrame.maxX + Self.notchSpacing,
                y: anchorFrame.midY - size.height / 2
            )
        case .right:
            proposedOrigin = CGPoint(
                x: anchorFrame.minX - Self.notchSpacing - size.width,
                y: anchorFrame.midY - size.height / 2
            )
        }

        let availableFrame = (screen?.frame ?? anchorFrame.union(CGRect(origin: proposedOrigin, size: size)))
            .insetBy(dx: 8, dy: 8)
        let x = min(max(proposedOrigin.x, availableFrame.minX), availableFrame.maxX - size.width)
        let y = min(max(proposedOrigin.y, availableFrame.minY), availableFrame.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
