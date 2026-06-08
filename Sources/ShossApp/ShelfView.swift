import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var library: ScreenshotLibrary
    @State private var hoverCollapseTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            if library.isExpanded {
                ExpandedShelfView(library: library)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                        )
                    )
            } else {
                CollapsedNotchView()
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(
            .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.08),
            value: library.isExpanded
        )
        .onHover { hovering in
            hoverCollapseTask?.cancel()
            if hovering {
                library.isExpanded = true
            } else {
                let task = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(260))
                    guard !Task.isCancelled else { return }
                    library.isExpanded = false
                }
                hoverCollapseTask = task
            }
        }
    }
}

private struct NotchCornerJoinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 20
        let scaleY = rect.height / 20
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var path = Path()
        path.move(to: point(0, 0))
        path.addLine(to: point(20, 0))
        path.addCurve(
            to: point(0, 20),
            control1: point(8.954, 0),
            control2: point(0, 8.954)
        )
        path.closeSubpath()
        return path
    }
}

private struct CollapsedNotchView: View {
    private static var hasAnimatedIconEntrance = false
    @State private var iconVisible = false

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: 14,
                    bottomTrailing: 14,
                    topTrailing: 0
                ),
                style: .continuous
            )
            .fill(.black)
            .frame(width: 132, height: 34)

            HStack(spacing: 132) {
                NotchCornerJoinShape()
                    .fill(.black)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(90))

                NotchCornerJoinShape()
                    .fill(.black)
                    .frame(width: 14, height: 14)
            }
            .frame(height: 14, alignment: .top)

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 132, height: 34)
                .opacity(iconVisible ? 1 : 0)
                .scaleEffect(iconVisible ? 1 : 0.5)
        }
        .frame(width: 160, height: 34)
        .onAppear {
            if !Self.hasAnimatedIconEntrance {
                Self.hasAnimatedIconEntrance = true
                withAnimation(.easeOut(duration: 0.3).delay(0.22)) {
                    iconVisible = true
                }
            } else {
                iconVisible = true
            }
        }
    }
}

private struct ExpandedShelfView: View {
    @ObservedObject var library: ScreenshotLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeaderView(library: library)
                .zIndex(10)
            HStack(alignment: .top, spacing: 14) {
                ScreenshotGridView(library: library)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, -14)

                if library.selectedItem != nil {
                    DetailPaneView(library: library)
                        .frame(width: 240)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .background { ExpandedShelfBackground() }
        .foregroundStyle(.white)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct ExpandedShelfBackground: View {
    private let cornerRadii = RectangleCornerRadii(
        topLeading: 20,
        bottomLeading: 28,
        bottomTrailing: 28,
        topTrailing: 20
    )

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)

        ZStack {
            VisualEffectBackground(material: .hudWindow)
                .clipShape(shape)

            shape
                .fill(.black.opacity(0.76))

            shape
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear, .black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            shape
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
    }
}

private struct PanelTooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.94))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                ZStack {
                    VisualEffectBackground(material: .hudWindow)
                        .clipShape(Capsule())
                    Capsule()
                        .fill(.black.opacity(0.42))
                }
            }
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.24), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.46), radius: 10, y: 5)
            .allowsHitTesting(false)
    }
}

private struct PanelTooltipModifier: ViewModifier {
    let text: String?
    let isPresented: Bool
    let xOffset: CGFloat
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .center) {
            if isPresented, let text {
                PanelTooltipBubble(text: text)
                    .offset(x: xOffset, y: yOffset)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isPresented)
    }
}

private extension View {
    func panelTooltip(
        _ text: String?,
        isPresented: Bool,
        xOffset: CGFloat = 0,
        yOffset: CGFloat
    ) -> some View {
        modifier(
            PanelTooltipModifier(
                text: text,
                isPresented: isPresented,
                xOffset: xOffset,
                yOffset: yOffset
            )
        )
    }
}

private struct HeaderView: View {
    @ObservedObject var library: ScreenshotLibrary
    @FocusState private var searchFocused: Bool
    @State private var searchHovered = false
    @State private var refreshRotation: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(searchFocused ? 0.65 : 0.45))
                TextField("Search screenshots", text: $library.searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .regular))
                    .focused($searchFocused)
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .frame(width: 320, height: 36)
            .background(
                colorForSearchBackground(),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(.white.opacity(searchFocused ? 0.18 : 0), lineWidth: 1)
            )
            .onHover { searchHovered = $0 }

            FolderFilterStripView(library: library)

            Spacer()

            CircleHeaderButton(
                systemName: library.showingFavoritesOnly ? "bookmark.fill" : "bookmark",
                isSelected: library.showingFavoritesOnly,
                tooltip: library.showingFavoritesOnly ? "Show All" : "Show Favs"
            ) {
                library.toggleFavoritesFilter()
            }
            .accessibilityLabel(library.showingFavoritesOnly ? "Show all screenshots" : "Show favorites")

            CircleHeaderButton(systemName: "arrow.clockwise", rotationDegrees: refreshRotation, tooltip: "Refresh folder") {
                withAnimation(.easeInOut(duration: 0.45)) {
                    refreshRotation += 360
                }
                library.refresh()
            }
            .accessibilityLabel("Refresh screenshots")

            CircleHeaderButton(systemName: "folder", tooltip: "Screenshoss folder") {
                library.openStorageFolder()
            }
            .accessibilityLabel("Open screenshots folder")

            CircleHeaderButton(systemName: "xmark", tooltip: "Hide Screenshoss") {
                library.closeAction?()
            }
            .accessibilityLabel("Hide Screenshoss")
        }
    }

    private func colorForSearchBackground() -> Color {
        if searchFocused {
            return .white.opacity(0.15)
        }
        if searchHovered {
            return .white.opacity(0.12)
        }
        return .white.opacity(0.08)
    }
}

private struct FolderFilterStripView: View {
    @ObservedObject var library: ScreenshotLibrary
    @State private var bumpedFolderName: String?
    @State private var addButtonHovered = false
    @State private var folderContentWidth: CGFloat = 1
    @State private var folderContentMinX: CGFloat = 0

    private let maxFolderScrollWidth: CGFloat = 560
    private let folderFadeWidth: CGFloat = 64
    private let scrollCoordinateSpace = "FolderFilterScroll"

    var body: some View {
        let scrollWidth = min(maxFolderScrollWidth, max(1, folderContentWidth))
        let isOverflowing = folderContentWidth > maxFolderScrollWidth
        let shouldShowLeadingFade = isOverflowing && folderContentMinX < -2
        let shouldShowTrailingFade = isOverflowing && folderContentMinX + folderContentWidth > scrollWidth + 2

        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FolderFilterPill(
                        title: "Recent",
                        count: library.count(forFolder: nil),
                        isSelected: library.selectedFolderName == nil,
                        isBumped: bumpedFolderName == recentBumpID,
                        onTap: { library.selectFolder(nil) },
                        onDrop: { handleDrop(folderName: nil) }
                    )

                    ForEach(library.folders) { folder in
                        FolderFilterPill(
                            title: folder.name,
                            count: folder.count,
                            isSelected: library.selectedFolderName == folder.name,
                            isBumped: bumpedFolderName == folder.name,
                            onTap: { library.selectFolder(folder.name) },
                            onDrop: { handleDrop(folderName: folder.name) }
                        )
                        .contextMenu {
                            Button("Rename Folder...") {
                                library.renameFolder(folder)
                            }
                            Button("Delete Folder", role: .destructive) {
                                library.deleteFolder(folder)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: FolderContentWidthKey.self, value: proxy.size.width)
                            .preference(
                                key: FolderContentMinXKey.self,
                                value: proxy.frame(in: .named(scrollCoordinateSpace)).minX
                            )
                    }
                }
            }
            .coordinateSpace(name: scrollCoordinateSpace)
            .frame(width: scrollWidth, alignment: .leading)
            .mask(
                HStack(spacing: 0) {
                    if shouldShowLeadingFade {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.34), location: 0.26),
                                .init(color: .black.opacity(0.82), location: 0.58),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: folderFadeWidth)
                    }
                    Rectangle().fill(.black)
                    if shouldShowTrailingFade {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.82), location: 0.42),
                                .init(color: .black.opacity(0.34), location: 0.74),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: folderFadeWidth)
                    }
                }
            )
            .onPreferenceChange(FolderContentWidthKey.self) { folderContentWidth = $0 }
            .onPreferenceChange(FolderContentMinXKey.self) { folderContentMinX = $0 }

            Button(action: library.createFolder) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(FolderAddButtonStyle(isHovered: addButtonHovered))
            .onHover { addButtonHovered = $0 }
            .accessibilityLabel("Create folder")
            .panelTooltip("Create folder", isPresented: addButtonHovered, yOffset: 42)
            .zIndex(addButtonHovered ? 50 : 0)
        }
        .frame(height: 42)
        .frame(width: scrollWidth + 42, alignment: .leading)
    }

    private var recentBumpID: String {
        "__recent__"
    }

    private func handleDrop(folderName: String?) -> Bool {
        let moved = library.moveDraggedItem(toFolder: folderName)
        guard moved else { return false }
        let bumpID = folderName ?? recentBumpID
        withAnimation(.spring(response: 0.22, dampingFraction: 0.46)) {
            bumpedFolderName = bumpID
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            if bumpedFolderName == bumpID {
                withAnimation(.easeOut(duration: 0.18)) {
                    bumpedFolderName = nil
                }
            }
        }
        return true
    }
}

private struct FolderContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FolderContentMinXKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FolderFilterPill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let isBumped: Bool
    let onTap: () -> Void
    let onDrop: () -> Bool
    @State private var isDropTargeted = false
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .black.opacity(0.55) : .white.opacity(0.62))
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minWidth: title == "Recent" ? 98 : 78, maxWidth: 136)
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(FolderPillButtonStyle(isSelected: isSelected, isHovered: isHovered, isTargeted: isDropTargeted))
        .scaleEffect(isBumped ? 1.08 : isDropTargeted ? 1.04 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isBumped)
        .animation(.easeOut(duration: 0.14), value: isDropTargeted)
        .onHover { isHovered = $0 }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { _ in
            onDrop()
        }
    }
}

private struct FolderPillButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool
    let isTargeted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? .black.opacity(configuration.isPressed ? 0.6 : 0.95) : .white.opacity(configuration.isPressed ? 0.62 : 0.84))
            .background(backgroundColor(configuration: configuration), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(isTargeted ? 0.42 : 0), lineWidth: 1)
            )
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if isSelected {
            return .white.opacity(configuration.isPressed ? 0.78 : 0.96)
        }
        if isTargeted {
            return .white.opacity(0.34)
        }
        if isHovered {
            return .white.opacity(0.2)
        }
        return .white.opacity(0.14)
    }
}

private struct FolderAddButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.58 : 0.82))
            .background(backgroundColor(configuration: configuration), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.96 : isHovered ? 1.04 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if configuration.isPressed {
            return .white.opacity(0.12)
        }
        if isHovered {
            return .white.opacity(0.24)
        }
        return .white.opacity(0.16)
    }
}

private struct CircleHeaderButton: View {
    let systemName: String
    var isSelected = false
    var rotationDegrees: Double = 0
    var tooltip: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .rotationEffect(.degrees(rotationDegrees))
        }
        .buttonStyle(CircleButtonStyle(isHovered: isHovered, isSelected: isSelected))
        .onHover { isHovered = $0 }
        .panelTooltip(tooltip, isPresented: isHovered, yOffset: 42)
        .zIndex(isHovered ? 50 : 0)
    }
}

private struct ScreenshotGridView: View {
    @ObservedObject var library: ScreenshotLibrary

    private let columnCount = 4
    private let cardSpacing: CGFloat = 10
    private let innerHorizontalPadding: CGFloat = 4

    var body: some View {
        if library.filteredItems.isEmpty {
            EmptyShelfView(desktopPath: library.desktopPath)
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
                                dragURLs: { library.dragURLs(startingFrom: item) }
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
                }
            }
        }
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
                    onDoubleClick: onOpen
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
                .padding(6)
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

    func makeNSView(context: Context) -> ScreenshotMultiDragSourceNSView {
        let view = ScreenshotMultiDragSourceNSView()
        view.dragURLs = dragURLs
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ view: ScreenshotMultiDragSourceNSView, context: Context) {
        view.dragURLs = dragURLs
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
    }
}

private final class ScreenshotMultiDragSourceNSView: NSView, NSDraggingSource {
    var dragURLs: (() -> [URL])?
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onDoubleClick: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false
    private let dragStartThreshold: CGFloat = 4

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
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
        context == .outsideApplication ? .copy : [.copy, .move]
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
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

private struct FloatingIconButton: View {
    let systemName: String
    var isSelected = false
    let tooltip: String
    let accessibilityLabel: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                Button(action: action) {
                    iconLabel
                }
                .buttonStyle(.glass)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(isHovered || isSelected ? 0.42 : 0.28), lineWidth: 1.0)
                )
                .shadow(color: .black.opacity(0.46), radius: 8, y: 4)
                .scaleEffect(isHovered ? 1.05 : 1)
                .animation(.easeOut(duration: 0.12), value: isHovered)
            } else {
                Button(action: action) {
                    iconLabel
                }
                .buttonStyle(FloatingIconButtonStyle(isHovered: isHovered, isSelected: isSelected))
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
        .panelTooltip(tooltip, isPresented: isHovered, yOffset: 34)
        .zIndex(isHovered ? 50 : 0)
    }

    private var iconLabel: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
    }
}

private struct FloatingIconButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor(configuration: configuration))
            .background {
                Circle()
                    .fill(.black.opacity(configuration.isPressed ? 0.54 : isHovered ? 0.48 : 0.42))
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.06 : isSelected ? 0.16 : 0.1))
            }
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(isHovered || isSelected ? 0.4 : 0.3), lineWidth: 1.0)
            }
            .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.94 : isHovered ? 1.05 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func foregroundColor(configuration: Configuration) -> Color {
        if isSelected {
            return .white.opacity(configuration.isPressed ? 0.72 : 1.0)
        }
        return .white.opacity(configuration.isPressed ? 0.58 : isHovered ? 1.0 : 0.82)
    }
}

private struct DetailPaneView: View {
    @ObservedObject var library: ScreenshotLibrary
    @State private var justCopiedItemID: URL?

    var body: some View {
        if let item = library.selectedItem {
            VStack(alignment: .leading, spacing: 10) {
                AsyncImage(url: item.url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Rectangle().fill(.white.opacity(0.08))
                    }
                }
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 10) {
                        DetailRow(label: "Created", value: item.formattedCreatedAt)
                        DetailRow(label: "Dimensions", value: item.dimensionsText)
                        DetailRow(label: "Details", value: item.formattedFileSize)
                    }

                    Spacer()

                    FloatingIconButton(
                        systemName: item.isFavorite ? "bookmark.fill" : "bookmark",
                        isSelected: item.isFavorite,
                        tooltip: item.isFavorite ? "Remove" : "Add Fav",
                        accessibilityLabel: item.isFavorite ? "Remove favorite" : "Favorite screenshot"
                    ) {
                        library.toggleFavorite(item)
                    }
                    .padding(.top, 2)
                }

                Spacer()

                HStack(spacing: 6) {
                    Group {
                        if justCopiedItemID == item.id {
                            CopiedIndicatorView()
                        } else {
                            DetailActionButton(title: "Copy", icon: "doc.on.doc") {
                                if library.copySelection() {
                                    justCopiedItemID = item.id
                                    let capturedID = item.id
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(1))
                                        if justCopiedItemID == capturedID {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                justCopiedItemID = nil
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    DetailActionButton(title: "Open", icon: "arrow.up.right.square") {
                        library.open(item)
                    }
                }
                HStack(spacing: 6) {
                    DetailActionButton(title: "Finder", icon: "folder") {
                        library.reveal(item)
                    }
                    DetailActionButton(title: "Trash", icon: "trash") {
                        library.deleteSelection(fallback: item)
                    }
                }
            }
            .padding(10)
            .frame(maxHeight: .infinity)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.easeInOut(duration: 0.2), value: justCopiedItemID)
        }
    }
}

private struct CopiedIndicatorView: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
            Text("Copied")
                .font(.system(size: 10, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .foregroundStyle(.green)
        .background(.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct DetailActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(DetailButtonStyle(isHovered: isHovered))
        .onHover { isHovered = $0 }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
            Text(value)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct EmptyShelfView: View {
    let desktopPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
            Text("No Desktop screenshots yet")
                .font(.system(size: 14, weight: .semibold))
            Text(desktopPath)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(20)
    }
}

private struct CircleButtonStyle: ButtonStyle {
    var isHovered: Bool = false
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foregroundColor(configuration: configuration))
            .frame(width: 32, height: 32)
            .background(backgroundColor(configuration: configuration), in: Circle())
            .overlay(
                Circle()
                    .stroke(.white.opacity(isSelected ? 0.24 : isHovered ? 0.18 : 0.08), lineWidth: 0.8)
            )
    }

    private func foregroundColor(configuration: Configuration) -> Color {
        if isSelected {
            return .white.opacity(configuration.isPressed ? 0.72 : 1.0)
        }
        return .white.opacity(configuration.isPressed ? 0.55 : isHovered ? 1.0 : 0.82)
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if configuration.isPressed {
            return .white.opacity(isSelected ? 0.24 : 0.08)
        }
        if isSelected {
            return .white.opacity(0.24)
        }
        if isHovered {
            return .white.opacity(0.18)
        }
        return .white.opacity(0.12)
    }
}

private struct DetailButtonStyle: ButtonStyle {
    var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black.opacity(configuration.isPressed ? 0.65 : 1))
            .background(
                { () -> Color in
                    if configuration.isPressed {
                        return .white.opacity(0.62)
                    }
                    if isHovered {
                        return .white.opacity(0.92)
                    }
                    return .white
                }(),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}
