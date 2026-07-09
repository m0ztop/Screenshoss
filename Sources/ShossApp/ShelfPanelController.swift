import AppKit
import Combine
import SwiftUI
import QuickLookUI

private final class QuickLookSource: NSObject, QLPreviewPanelDataSource {
    var url: URL?

    init(url: URL) {
        self.url = url
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard let url else { return nil }
        return url as NSURL
    }
}

private final class ShelfPanel: NSPanel {
    var quickLookAction: (() -> Void)?
    var copySelectionAction: (() -> Bool)?
    var deleteSelectionAction: (() -> Bool)?

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
        if isTextInputActive {
            super.keyDown(with: event)
            return
        }

        if isCommandCopy(event) {
            if copySelectionAction?() == true {
                return
            }
        }

        if isDeleteKey(event) {
            if deleteSelectionAction?() == true {
                return
            }
        }

        if event.keyCode == 49 {
            quickLookAction?()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if !isTextInputActive, isCommandCopy(event), copySelectionAction?() == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private var isTextInputActive: Bool {
        firstResponder is NSTextView
    }

    private func isCommandCopy(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else {
            return false
        }
        return event.charactersIgnoringModifiers?.lowercased() == "c"
    }

    private func isDeleteKey(_ event: NSEvent) -> Bool {
        event.keyCode == 51 || event.keyCode == 117
    }

    private func resignTextInputFocusIfNeeded() {
        guard isTextInputActive else { return }
        makeFirstResponder(nil)
    }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class ShelfPanelController: NSObject {
    private let library: ScreenshotLibrary
    private let panel: ShelfPanel
    private let topCollapsedSize = CGSize(width: 160, height: 34)
    private let topExpandedSize = CGSize(width: 1_180, height: 476)
    private let sideCollapsedSize = CGSize(width: 34, height: 160)
    private let sideExpandedSize = CGSize(width: 520, height: 760)
    private let sideExpandedEdgeInset: CGFloat = 8
    private var isHidden = false
    private var quickLookSource: QuickLookSource?
    private var selectedItemCancellable: AnyCancellable?
    private var displayChangeTask: Task<Void, Never>?
    private var notificationObservers: [NSObjectProtocol] = []
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

        configureFloatingPanel(panel)

        let contentView = ShelfView(library: library)
        panel.contentView = TransparentHostingView(rootView: contentView)

        library.expansionDidChange = { [weak self] isExpanded in
            Task { @MainActor in
                self?.setExpanded(isExpanded)
            }
        }

        library.shouldCollapseAfterHoverExit = { [weak self] in
            self?.shouldCollapseAfterHoverExit() ?? true
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

        panel.copySelectionAction = { [weak self] in
            self?.library.copySelection() ?? false
        }

        panel.deleteSelectionAction = { [weak self] in
            self?.library.deleteSelection() ?? false
        }

        selectedItemCancellable = library.$selectedItem
            .dropFirst()
            .sink { [weak self] item in
                Task { @MainActor in
                    self?.updateQuickLookSelection(item)
                }
            }

        observeDisplayChanges()
    }

    private func configureFloatingPanel(_ panel: ShelfPanel) {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
    }

    var presentationMode: ShelfPresentationMode {
        library.presentationMode
    }

    func show() {
        isHidden = false
        if !Self.hasPerformedEntranceAnimation {
            Self.hasPerformedEntranceAnimation = true
            let finalFrame = targetFrame(for: false)
            let startFrame = entranceFrame(for: finalFrame)
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
        isHidden = true
        library.isExpanded = false
        closeQuickLook()
        panel.orderOut(nil)
    }

    func bringToFront() {
        panel.orderFrontRegardless()
    }

    func setPresentationMode(_ mode: ShelfPresentationMode) {
        isHidden = false
        library.isExpanded = false
        closeQuickLook()
        library.setPresentationMode(mode)
        panel.alphaValue = 1
        panel.setFrame(targetFrame(for: false), display: true)
        panel.orderFrontRegardless()
    }

    func cyclePresentationMode() {
        isHidden = false
        library.isExpanded = false
        closeQuickLook()
        library.cyclePresentationMode()
        panel.alphaValue = 1
        panel.setFrame(targetFrame(for: false), display: true)
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
            ql.reloadData()
            ql.makeKeyAndOrderFront(nil)
        }
    }

    private func updateQuickLookSelection(_ item: ScreenshotItem?) {
        guard let ql = QLPreviewPanel.shared(), ql.isVisible else { return }
        guard let url = item?.url else {
            ql.orderOut(nil)
            return
        }

        let source = quickLookSource ?? QuickLookSource(url: url)
        source.url = url
        quickLookSource = source
        ql.dataSource = source
        ql.currentPreviewItemIndex = 0
        ql.reloadData()
        ql.refreshCurrentPreviewItem()
    }

    private func closeQuickLook() {
        guard let ql = QLPreviewPanel.shared(), ql.isVisible else { return }
        ql.orderOut(nil)
    }

    private func setExpanded(_ isExpanded: Bool, animated: Bool = true) {
        guard !isHidden else {
            panel.orderOut(nil)
            return
        }
        let frame = targetFrame(for: isExpanded)

        if animated, !isExpanded {
            panel.resignKey()
        }

        if animated {
            if isExpanded {
                panel.setFrame(targetFrame(for: false), display: false)
            }
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = isExpanded ? 0.34 : 0.24
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
        let screen = targetScreen()
        let screenFrame = screen?.frame ?? .init(x: 0, y: 0, width: 1_440, height: 900)
        let visibleFrame = screen?.visibleFrame ?? screenFrame

        switch library.presentationMode {
        case .top:
            let size = isExpanded ? constrainedTopExpandedSize(in: screenFrame) : topCollapsedSize
            let x = screenFrame.midX - size.width / 2
            let y = topEdgeY(for: screen) - size.height
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        case .left:
            let size = isExpanded ? constrainedSideExpandedSize(in: visibleFrame) : sideCollapsedSize
            let y = centeredSideY(for: size, in: visibleFrame)
            let x = isExpanded ? screenFrame.minX + sideExpandedEdgeInset : screenFrame.minX
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        case .right:
            let size = isExpanded ? constrainedSideExpandedSize(in: visibleFrame) : sideCollapsedSize
            let y = centeredSideY(for: size, in: visibleFrame)
            let x = isExpanded
                ? screenFrame.maxX - size.width - sideExpandedEdgeInset
                : screenFrame.maxX - size.width
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        }
    }

    private func entranceFrame(for finalFrame: CGRect) -> CGRect {
        switch library.presentationMode {
        case .top:
            return CGRect(
                x: finalFrame.midX - 44,
                y: finalFrame.maxY - 18,
                width: 88,
                height: 20
            )
        case .left:
            return CGRect(
                x: finalFrame.minX,
                y: finalFrame.midY - 44,
                width: 20,
                height: 88
            )
        case .right:
            return CGRect(
                x: finalFrame.maxX - 20,
                y: finalFrame.midY - 44,
                width: 20,
                height: 88
            )
        }
    }

    private func centeredSideY(for size: CGSize, in frame: CGRect) -> CGFloat {
        min(
            max(frame.minY + 16, frame.midY - size.height / 2),
            frame.maxY - size.height - 16
        )
    }

    private func shouldCollapseAfterHoverExit() -> Bool {
        guard library.isExpanded else {
            return true
        }

        let hoverFrame = panel.frame.insetBy(dx: -18, dy: -18)
        return !hoverFrame.contains(NSEvent.mouseLocation)
    }

    private func targetScreen() -> NSScreen? {
        if let screen = NSScreen.main { return screen }

        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }

        return NSScreen.screens.first
    }

    private func topEdgeY(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return 900 }
        if shouldAvoidBuiltInCameraArea(on: screen) {
            return screen.visibleFrame.maxY
        }
        return screen.frame.maxY
    }

    private func shouldAvoidBuiltInCameraArea(on screen: NSScreen) -> Bool {
        let menuBarInset = screen.frame.maxY - screen.visibleFrame.maxY
        guard menuBarInset > 0 else { return false }

        let screenName = screen.localizedName.lowercased()
        let looksBuiltIn = screenName.contains("built-in")
            || screenName.contains("retina")
            || screenName.contains("color lcd")
            || screenName.contains("liquid")

        let size = screen.frame.size
        let looksLaptopSized = max(size.width, size.height) <= 1_800 && min(size.width, size.height) <= 1_200
        return looksBuiltIn || looksLaptopSized
    }

    private func constrainedTopExpandedSize(in screenFrame: CGRect) -> CGSize {
        CGSize(
            width: min(topExpandedSize.width, max(420, screenFrame.width - 160)),
            height: min(topExpandedSize.height, max(280, screenFrame.height * 0.62))
        )
    }

    private func constrainedSideExpandedSize(in visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: min(sideExpandedSize.width, max(340, visibleFrame.width - 120)),
            height: min(sideExpandedSize.height, max(440, visibleFrame.height - 72))
        )
    }

    private func observeDisplayChanges() {
        let displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleDisplayReposition()
            }
        }
        notificationObservers.append(displayObserver)
    }

    private func scheduleDisplayReposition() {
        displayChangeTask?.cancel()
        displayChangeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            repositionForCurrentDisplay()
        }
    }

    private func repositionForCurrentDisplay() {
        guard panel.isVisible else { return }
        panel.setFrame(targetFrame(for: library.isExpanded), display: true)
        panel.orderFrontRegardless()
        if library.isExpanded {
            panel.makeKey()
        }
    }
}
