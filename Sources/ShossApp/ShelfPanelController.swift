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
    var pointerEvent: ((NSEvent) -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        pointerEvent?(event)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        pointerEvent?(event)
        super.mouseExited(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        pointerEvent?(event)
        super.mouseMoved(with: event)
    }
}

@MainActor
final class ShelfDisplayState: ObservableObject {
    @Published var hidesCollapsedTopNotchVisual = false
}

enum ShelfScreenGeometry {
    static let topHoverBridgeHeight: CGFloat = 8

    // CGRect.contains excludes its maximum edges. A pointer at the physical
    // top/right edge still belongs to the screen and must remain interactive.
    static func containsPointer(_ point: CGPoint, in frame: CGRect) -> Bool {
        !frame.isEmpty
            && point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }

    static func hasCameraHousing(
        safeAreaTopInset: CGFloat,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) -> Bool {
        guard safeAreaTopInset > 0 else { return false }
        guard let auxiliaryTopLeftArea, let auxiliaryTopRightArea else { return false }
        return !auxiliaryTopLeftArea.isEmpty && !auxiliaryTopRightArea.isEmpty
    }

    static func topEdgeY(
        isExpanded: Bool,
        hasCameraHousing: Bool,
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> CGFloat {
        if isExpanded, hasCameraHousing {
            return visibleFrame.maxY
        }
        return screenFrame.maxY
    }

    static func topMenuBarRetentionFrame(
        panelFrame: CGRect,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        horizontalPadding: CGFloat = 18
    ) -> CGRect {
        CGRect(
            x: panelFrame.minX - horizontalPadding,
            y: visibleFrame.maxY,
            width: panelFrame.width + horizontalPadding * 2,
            height: max(0, screenFrame.maxY - visibleFrame.maxY)
        )
    }

    static func retainsHover(
        at mouseLocation: CGPoint,
        collapsedFrame: CGRect,
        expandedFrame: CGRect,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        includesMenuBar: Bool
    ) -> Bool {
        guard containsPointer(mouseLocation, in: screenFrame) else { return false }

        if containsPointer(mouseLocation, in: collapsedFrame.insetBy(dx: -18, dy: -18))
            || containsPointer(mouseLocation, in: expandedFrame.insetBy(dx: -18, dy: -18)) {
            return true
        }

        return includesMenuBar && containsPointer(mouseLocation, in: topMenuBarRetentionFrame(
            panelFrame: expandedFrame,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        ))
    }
}

@MainActor
final class ShelfPanelController: NSObject {
    private let library: ScreenshotLibrary
    private let panel: ShelfPanel
    private let displayState = ShelfDisplayState()
    private let topCollapsedSize = CGSize(width: 160, height: 34)
    private let topExpandedSize = CGSize(width: 1_180, height: 476)
    private let sideCollapsedSize = CGSize(width: 34, height: 160)
    private let sideExpandedSize = CGSize(width: 520, height: 760)
    private let sideExpandedEdgeInset: CGFloat = 8
    private let firstLaunchHintController = FirstLaunchHintController()
    private var isHidden = false
    private var quickLookSource: QuickLookSource?
    private var selectedItemCancellable: AnyCancellable?
    private var displayChangeTask: Task<Void, Never>?
    private var hoverCollapseTask: Task<Void, Never>?
    private var pointerMonitors: [Any] = []
    private var lastPointerScreenID: CGDirectDisplayID?
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
        updateDisplayState(for: targetScreen())

        let contentView = ShelfView(library: library, displayState: displayState)
        let hostingView = TransparentHostingView(rootView: contentView)
        hostingView.pointerEvent = { [weak self] event in
            self?.handlePointerMovement(event)
        }
        panel.contentView = hostingView

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
        observePointerMovement()
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
        panel.acceptsMouseMovedEvents = true
    }

    var presentationMode: ShelfPresentationMode {
        library.presentationMode
    }

    func show() {
        isHidden = false
        updateDisplayState(for: targetScreen())
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
            scheduleFirstLaunchHint(anchorFrame: finalFrame)
        } else {
            setExpanded(false, animated: false)
            panel.orderFrontRegardless()
            library.start()
            scheduleFirstLaunchHint(anchorFrame: panel.frame)
        }
    }

    func hide() {
        isHidden = true
        cancelHoverCollapse()
        library.isExpanded = false
        closeQuickLook()
        firstLaunchHintController.dismiss()
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
        updateDisplayState(for: targetScreen())
        panel.alphaValue = 1
        panel.setFrame(targetFrame(for: false), display: true)
        panel.orderFrontRegardless()
        updateFirstLaunchHintPlacement()
        scheduleFirstLaunchHint(anchorFrame: panel.frame)
    }

    func cyclePresentationMode() {
        isHidden = false
        library.isExpanded = false
        closeQuickLook()
        library.cyclePresentationMode()
        updateDisplayState(for: targetScreen())
        panel.alphaValue = 1
        panel.setFrame(targetFrame(for: false), display: true)
        panel.orderFrontRegardless()
        updateFirstLaunchHintPlacement()
        scheduleFirstLaunchHint(anchorFrame: panel.frame)
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
        let screen = targetScreen()
        updateDisplayState(for: screen)
        let frame = targetFrame(for: isExpanded, on: screen)

        if isExpanded {
            firstLaunchHintController.dismiss()
        }

        if animated, !isExpanded {
            panel.resignKey()
        }

        if animated {
            if isExpanded {
                panel.setFrame(targetFrame(for: false, on: screen), display: false)
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

    private func targetFrame(for isExpanded: Bool, on screen: NSScreen? = nil) -> CGRect {
        let screen = screen ?? targetScreen()
        let screenFrame = screen?.frame ?? .init(x: 0, y: 0, width: 1_440, height: 900)
        let visibleFrame = screen?.visibleFrame ?? screenFrame

        switch library.presentationMode {
        case .top:
            let contentSize = isExpanded ? constrainedTopExpandedSize(in: screenFrame) : topCollapsedSize
            let x = screenFrame.midX - contentSize.width / 2
            let hasCameraHousing = screen.map(hasNativeCameraHousing) ?? false
            let hoverBridgeHeight = isExpanded && hasCameraHousing
                ? ShelfScreenGeometry.topHoverBridgeHeight
                : 0
            let size = CGSize(
                width: contentSize.width,
                height: contentSize.height + hoverBridgeHeight
            )
            let topEdgeY = ShelfScreenGeometry.topEdgeY(
                isExpanded: isExpanded,
                hasCameraHousing: hasCameraHousing,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            ) + hoverBridgeHeight
            let y = topEdgeY - size.height
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

    private func shouldCollapseForCurrentPointer() -> Bool {
        guard library.isExpanded else {
            return true
        }

        // The open panel stays on its display until it closes.
        guard let screen = panel.screen ?? targetScreen() else { return true }
        return !ShelfScreenGeometry.retainsHover(
            at: NSEvent.mouseLocation,
            collapsedFrame: targetFrame(for: false, on: screen),
            expandedFrame: targetFrame(for: true, on: screen),
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            includesMenuBar: library.presentationMode == .top
        )
    }

    /// The shelf belongs on the display the user is actually working on, so
    /// the pointer's screen wins. `NSScreen.main` is only a fallback: for a
    /// menu bar app it resolves to the screen owning the menu bar (or the
    /// shelf itself once expanded), which pins the shelf to one display on a
    /// multi-monitor desk.
    private func targetScreen() -> NSScreen? {
        if let screen = pointerScreen() {
            return screen
        }

        if let screen = NSScreen.main { return screen }

        return NSScreen.screens.first
    }

    /// Owns hover outside SwiftUI so replacing the collapsed view with the
    /// expanded view cannot create a false exit and a second open animation.
    private func observePointerMovement() {
        lastPointerScreenID = currentPointerScreenID()

        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handlePointerMovement(event)
        }

        pointerMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler),
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
                handler(event)
                return event
            }
        ].compactMap { $0 }
    }

    private func handlePointerMovement(_ event: NSEvent) {
        let id = currentPointerScreenID()
        if id != lastPointerScreenID {
            lastPointerScreenID = id
            if !library.isExpanded {
                scheduleDisplayReposition(onlyWhenCollapsed: true)
            }
        }

        guard !isHidden, panel.isVisible else { return }

        if library.isExpanded {
            if shouldCollapseForCurrentPointer() {
                scheduleHoverCollapse()
            } else {
                cancelHoverCollapse()
            }
            return
        }

        cancelHoverCollapse()
        guard event.type == .mouseMoved || event.type == .mouseEntered else { return }
        guard let screen = targetScreen() else { return }
        guard ShelfScreenGeometry.containsPointer(
            NSEvent.mouseLocation, in: targetFrame(for: false, on: screen)
        ) else { return }
        library.isExpanded = true
    }

    private func scheduleHoverCollapse() {
        guard hoverCollapseTask == nil else { return }
        hoverCollapseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(260))
            } catch {
                return
            }

            guard let self else { return }
            self.hoverCollapseTask = nil
            guard self.library.isExpanded, self.shouldCollapseForCurrentPointer() else { return }
            self.library.isExpanded = false
        }
    }

    private func cancelHoverCollapse() {
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil
    }

    private func currentPointerScreenID() -> CGDirectDisplayID? {
        pointerScreen()?.displayID
    }

    private func pointerScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        // Prefer the display containing the point before considering an exact
        // outer edge, so a shared boundary still has one consistent owner.
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.screens.first {
                ShelfScreenGeometry.containsPointer(mouseLocation, in: $0.frame)
            }
    }

    private func hasNativeCameraHousing(_ screen: NSScreen) -> Bool {
        ShelfScreenGeometry.hasCameraHousing(
            safeAreaTopInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }

    private func updateDisplayState(for screen: NSScreen?) {
        displayState.hidesCollapsedTopNotchVisual = screen.map(hasNativeCameraHousing) ?? false
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

    private func scheduleDisplayReposition(onlyWhenCollapsed: Bool = false) {
        displayChangeTask?.cancel()
        displayChangeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            // The shelf can open while a pointer move is waiting.
            guard !onlyWhenCollapsed || !library.isExpanded else { return }
            repositionForCurrentDisplay()
        }
    }

    private func repositionForCurrentDisplay() {
        guard panel.isVisible else { return }
        updateDisplayState(for: targetScreen())
        panel.setFrame(targetFrame(for: library.isExpanded), display: true)
        panel.orderFrontRegardless()
        updateFirstLaunchHintPlacement()
        if !library.isExpanded {
            scheduleFirstLaunchHint(anchorFrame: panel.frame)
        }
        if library.isExpanded {
            panel.makeKey()
        }
    }

    private func scheduleFirstLaunchHint(anchorFrame: CGRect) {
        firstLaunchHintController.scheduleIfNeeded(
            anchorFrame: anchorFrame,
            mode: library.presentationMode,
            screen: targetScreen()
        )
    }

    private func updateFirstLaunchHintPlacement() {
        firstLaunchHintController.updatePlacement(
            anchorFrame: panel.frame,
            mode: library.presentationMode,
            screen: targetScreen()
        )
    }
}

private extension NSScreen {
    /// Stable identity for a display, so "did the pointer change screen?" is a
    /// cheap comparison that survives a screen's frame moving.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
