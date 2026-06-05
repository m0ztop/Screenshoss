import AppKit
import SwiftUI
import QuickLookUI

private final class QuickLookSource: NSObject, QLPreviewPanelDataSource {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL
    }
}

private final class ShelfPanel: NSPanel {
    var quickLookAction: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        resignTextInputFocusIfNeeded()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        resignTextInputFocusIfNeeded()
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            quickLookAction?()
            return
        }
        super.keyDown(with: event)
    }

    private func resignTextInputFocusIfNeeded() {
        guard firstResponder is NSTextView else { return }
        makeFirstResponder(nil)
    }
}

@MainActor
final class ShelfPanelController: NSObject {
    private let library: ScreenshotLibrary
    private let panel: ShelfPanel
    private let collapsedSize = CGSize(width: 160, height: 34)
    private let expandedSize = CGSize(width: 1_180, height: 476)
    private var quickLookSource: QuickLookSource?
    private static var hasPerformedEntranceAnimation = false

    init(library: ScreenshotLibrary) {
        self.library = library

        panel = ShelfPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false

        let contentView = ShelfView(library: library)
        panel.contentView = NSHostingView(rootView: contentView)

        library.expansionDidChange = { [weak self] isExpanded in
            Task { @MainActor in
                self?.setExpanded(isExpanded)
            }
        }

        library.closeAction = { [weak self] in
            Task { @MainActor in
                self?.hide()
            }
        }

        library.modalWillOpen = { [weak self] in
            self?.panel.orderOut(nil)
        }

        library.modalDidClose = { [weak self] in
            guard let self else { return }
            self.panel.level = .statusBar
            self.panel.orderFrontRegardless()
            if self.library.isExpanded {
                self.panel.makeKey()
            }
        }

        panel.quickLookAction = { [weak self] in
            self?.toggleQuickLook()
        }
    }

    func show() {
        if !Self.hasPerformedEntranceAnimation {
            Self.hasPerformedEntranceAnimation = true
            let finalFrame = targetFrame(for: false)
            let startFrame = CGRect(
                x: finalFrame.midX - 44,
                y: finalFrame.maxY - 18,
                width: 88,
                height: 20
            )
            panel.setFrame(startFrame, display: false)
            panel.alphaValue = 0.86
            panel.orderFrontRegardless()

            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.46
            NSAnimationContext.current.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1.0
            NSAnimationContext.endGrouping()

            library.start()
        } else {
            setExpanded(false, animated: false)
            panel.orderFrontRegardless()
            library.start()
        }
    }

    func hide() {
        library.isExpanded = false
        closeQuickLook()
        panel.orderOut(nil)
    }

    func bringToFront() {
        panel.orderFrontRegardless()
    }

    private func toggleQuickLook() {
        guard let ql = QLPreviewPanel.shared() else { return }
        if ql.isVisible {
            ql.orderOut(nil)
        } else {
            guard let url = library.selectedItem?.url else { return }
            let source = QuickLookSource(url: url)
            quickLookSource = source
            ql.dataSource = source
            ql.makeKeyAndOrderFront(nil)
        }
    }

    private func closeQuickLook() {
        guard let ql = QLPreviewPanel.shared(), ql.isVisible else { return }
        ql.orderOut(nil)
    }

    private func setExpanded(_ isExpanded: Bool, animated: Bool = true) {
        let frame = targetFrame(for: isExpanded)

        if animated, !isExpanded {
            panel.resignKey()
        }

        if animated {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = isExpanded ? 0.38 : 0.24
            NSAnimationContext.current.timingFunction = isExpanded
                ? CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                : CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            NSAnimationContext.current.completionHandler = { [weak self] in
                guard let self else { return }
                if isExpanded {
                    self.panel.makeKey()
                }
            }
            panel.animator().setFrame(frame, display: true)
            NSAnimationContext.endGrouping()
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func targetFrame(for isExpanded: Bool) -> CGRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1_440, height: 900)
        let size = isExpanded ? constrainedExpandedSize(in: screenFrame) : collapsedSize
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func constrainedExpandedSize(in screenFrame: CGRect) -> CGSize {
        CGSize(
            width: min(expandedSize.width, max(420, screenFrame.width - 160)),
            height: min(expandedSize.height, max(280, screenFrame.height * 0.62))
        )
    }
}
