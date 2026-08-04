import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotGridView: View {
    @ObservedObject var library: ScreenshotLibrary
    var columnCount = 4
    var topContentPadding: CGFloat = 0

    private let cardSpacing: CGFloat = 10
    private let innerHorizontalPadding: CGFloat = 4

    var body: some View {
        if library.filteredItems.isEmpty {
            EmptyShelfView(
                title: emptyTitle,
                detail: emptyDetail
            )
        } else {
            GeometryReader { geometry in
                let availableWidth = geometry.size.width - innerHorizontalPadding * 2
                let columnWidth = max(100, (availableWidth - cardSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
                let columns: [GridItem] = Array(repeating: GridItem(.fixed(columnWidth), spacing: cardSpacing), count: columnCount)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: cardSpacing) {
                        ForEach(library.filteredItems) { item in
                            let selectItem: (NSEvent.ModifierFlags) -> Void = { modifiers in
                                library.select(
                                    item,
                                    extendingSelection: modifiers.contains(.shift),
                                    togglingSelection: modifiers.contains(.command)
                                )
                            }
                            let actsOnSelection = library.shouldActOnSelection(for: item)

                            ScreenshotCardView(
                                item: item,
                                isSelected: library.isSelected(item),
                                onDelete: { library.deleteSelection(fallback: item) },
                                onToggleFavorite: { library.toggleFavorite(item) },
                                onSelect: selectItem,
                                onOpen: { library.open(item) },
                                dragURLs: { library.dragURLs(startingFrom: item) },
                                onDragMovedOutside: {
                                    library.isExpanded = false
                                },
                                onDragEnded: { endedInsidePanel in
                                    library.finishDragging(shouldCollapse: !endedInsidePanel)
                                }
                            )
                            .frame(width: columnWidth)
                            .contextMenu {
                                Button(actsOnSelection ? "Copy Selected Images" : "Copy Image") {
                                    if actsOnSelection {
                                        library.copySelection()
                                    } else {
                                        library.copy(item)
                                    }
                                }
                                Button("Open") { library.open(item) }
                                Button("Reveal in Finder") { library.reveal(item) }
                                Divider()
                                Button("Rename...") { library.rename(item) }
                                Divider()
                                Button(actsOnSelection ? "Move Selected to Trash" : "Move to Trash", role: .destructive) {
                                    library.deleteSelection(fallback: item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, innerHorizontalPadding)
                    .padding(.top, topContentPadding)
                }
            }
        }
    }

    private var emptyTitle: String {
        let query = library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return "No matching screenshots"
        }
        if library.showingFavoritesOnly {
            return "No favorite screenshots yet"
        }
        if let folderName = library.selectedFolderName {
            return "No screenshots in \(folderName)"
        }
        return "No recent screenshots yet"
    }

    private var emptyDetail: String {
        let query = library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return "Clear search to see all screenshots."
        }
        return library.desktopPath
    }
}
private struct ScreenshotCardView: View {
    let item: ScreenshotItem
    let isSelected: Bool
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onOpen: () -> Void
    let dragURLs: () -> [URL]
    let onDragMovedOutside: () -> Void
    let onDragEnded: (Bool) -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: item.url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        default:
                            Rectangle()
                                .fill(.white.opacity(0.08))
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white.opacity(0.36))
                                }
                        }
                    }
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: 28)

                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 10, weight: .medium))
                        Text(item.relativeCreatedAt)
                        Spacer()
                        Text(item.formattedFileSize)
                    }
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
                .background(.black)
                .frame(height: 100)

                Text(item.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .frame(height: 22, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.07))
            }
            .overlay {
                ScreenshotMultiDragSourceView(
                    dragURLs: dragURLs,
                    onClick: onSelect,
                    onDoubleClick: onOpen,
                    onDragMovedOutside: onDragMovedOutside,
                    onDragEnded: onDragEnded
                )
            }

            if isHovered || item.isFavorite {
                HStack {
                    if isHovered {
                        FloatingIconButton(systemName: "trash", tooltip: "Delete", accessibilityLabel: "Delete screenshot", action: onDelete)
                            .transition(.scale(scale: 0.82).combined(with: .opacity))
                    }

                    Spacer()

                    FloatingIconButton(
                        systemName: item.isFavorite ? "bookmark.fill" : "bookmark",
                        isSelected: item.isFavorite,
                        tooltip: item.isFavorite ? "Remove" : "Add Fav",
                        accessibilityLabel: item.isFavorite ? "Remove favorite" : "Favorite screenshot",
                        action: onToggleFavorite
                    )
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, -2)
            }
        }
        .frame(height: 122)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? .white.opacity(0.85) : .white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}

private struct ScreenshotMultiDragSourceView: NSViewRepresentable {
    let dragURLs: () -> [URL]
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void
    let onDragMovedOutside: () -> Void
    let onDragEnded: (Bool) -> Void

    func makeNSView(context: Context) -> ScreenshotMultiDragSourceNSView {
        let view = ScreenshotMultiDragSourceNSView()
        view.dragURLs = dragURLs
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onDragMovedOutside = onDragMovedOutside
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: ScreenshotMultiDragSourceNSView, context: Context) {
        view.dragURLs = dragURLs
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onDragMovedOutside = onDragMovedOutside
        view.onDragEnded = onDragEnded
    }
}

private final class ScreenshotMultiDragSourceNSView: NSView, NSDraggingSource {
    var dragURLs: (() -> [URL])?
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragMovedOutside: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false
    private var didCollapseForExternalDrag = false
    private var dragPanelFrame: NSRect?
    private let dragStartThreshold: CGFloat = 4
    private let panelExitTolerance: CGFloat = 18

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
        didCollapseForExternalDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag else { return }
        guard hasMovedPastDragThreshold(event) else { return }

        let urls = dragURLs?() ?? []
        guard !urls.isEmpty else { return }

        didStartDrag = true
        beginDraggingSession(
            with: draggingItems(for: urls),
            event: mouseDownEvent ?? event,
            source: self
        )
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownEvent = nil
            didStartDrag = false
        }

        guard !didStartDrag else { return }
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onClick?(mouseDownEvent?.modifierFlags ?? event.modifierFlags)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        if context == .outsideApplication {
            return .copy
        }
        return [.copy, .move]
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        didCollapseForExternalDrag = false
        dragPanelFrame = window?.frame
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard !didCollapseForExternalDrag else { return }
        guard !isPointInsidePanel(screenPoint, tolerance: panelExitTolerance) else { return }

        collapseForExternalDragIfNeeded()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let endedInsidePanel = isPointInsidePanel(screenPoint) && !didCollapseForExternalDrag
        dragPanelFrame = nil
        onDragEnded?(endedInsidePanel)
    }

    private func isPointInsidePanel(_ screenPoint: NSPoint, tolerance: CGFloat = 0) -> Bool {
        guard let frame = dragPanelFrame ?? window?.frame else { return false }
        return frame.insetBy(dx: -tolerance, dy: -tolerance).contains(screenPoint)
    }

    private func collapseForExternalDragIfNeeded() {
        guard !didCollapseForExternalDrag else { return }
        didCollapseForExternalDrag = true
        DispatchQueue.main.async { [weak self] in
            self?.onDragMovedOutside?()
        }
    }

    private func hasMovedPastDragThreshold(_ event: NSEvent) -> Bool {
        guard let mouseDownEvent else { return true }
        let deltaX = event.locationInWindow.x - mouseDownEvent.locationInWindow.x
        let deltaY = event.locationInWindow.y - mouseDownEvent.locationInWindow.y
        return hypot(deltaX, deltaY) >= dragStartThreshold
    }

    private func draggingItems(for urls: [URL]) -> [NSDraggingItem] {
        let previewSize = NSSize(width: min(max(bounds.width, 72), 112), height: 70)
        return urls.enumerated().map { index, url in
            let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = min(CGFloat(index) * 3, 18)
            let frame = NSRect(
                x: max(0, (bounds.width - previewSize.width) / 2) + offset,
                y: max(0, (bounds.height - previewSize.height) / 2) + offset,
                width: previewSize.width,
                height: previewSize.height
            )
            draggingItem.setDraggingFrame(
                frame,
                contents: dragPreviewImage(for: url, count: urls.count, isPrimary: index == 0)
            )
            return draggingItem
        }
    }

    private func dragPreviewImage(for url: URL, count: Int, isPrimary: Bool) -> NSImage {
        let size = NSSize(width: 112, height: 70)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 12, yRadius: 12).fill()

        if let screenshot = NSImage(contentsOf: url) {
            screenshot.draw(
                in: aspectFitRect(for: screenshot.size, inside: NSRect(x: 0, y: 0, width: size.width, height: size.height)),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        if isPrimary, count > 1 {
            drawCountBadge(count, in: size)
        }

        image.unlockFocus()
        return image
    }

    private func aspectFitRect(for imageSize: NSSize, inside bounds: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return NSRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func drawCountBadge(_ count: Int, in size: NSSize) {
        let text = "\(count)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let textSize = text.size(withAttributes: attributes)
        let badgeRect = NSRect(
            x: size.width - textSize.width - 17,
            y: 7,
            width: textSize.width + 12,
            height: 20
        )
        NSColor.white.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 10, yRadius: 10).fill()
        text.draw(
            in: NSRect(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            ),
            withAttributes: attributes
        )
    }
}
