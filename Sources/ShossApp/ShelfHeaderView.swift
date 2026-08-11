import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HeaderView: View {
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
struct SideHeaderView: View {
    @ObservedObject var library: ScreenshotLibrary
    @FocusState private var searchFocused: Bool
    @State private var searchHovered = false
    @State private var refreshRotation: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
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
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .background(
                    colorForSearchBackground(),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(searchFocused ? 0.18 : 0), lineWidth: 1)
                )
                .onHover { searchHovered = $0 }

                CircleHeaderButton(
                    systemName: library.showingFavoritesOnly ? "bookmark.fill" : "bookmark",
                    isSelected: library.showingFavoritesOnly,
                    tooltip: library.showingFavoritesOnly ? "Show All" : "Show Favs",
                    tooltipPlacement: .leading
                ) {
                    library.toggleFavoritesFilter()
                }
                .accessibilityLabel(library.showingFavoritesOnly ? "Show all screenshots" : "Show favorites")

                CircleHeaderButton(systemName: "xmark", tooltip: "Hide Screenshoss", tooltipPlacement: .leading) {
                    library.closeAction?()
                }
                .accessibilityLabel("Hide Screenshoss")
            }

            HStack(spacing: 8) {
                FolderFilterStripView(library: library, maxFolderScrollWidth: 356, showsAddButton: false)

                FolderAddButton(library: library, tooltipPlacement: .leading)

                CircleHeaderButton(
                    systemName: "arrow.clockwise",
                    rotationDegrees: refreshRotation,
                    tooltip: "Refresh folder",
                    tooltipPlacement: .leading
                ) {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        refreshRotation += 360
                    }
                    library.refresh()
                }
                .accessibilityLabel("Refresh screenshots")

                CircleHeaderButton(systemName: "folder", tooltip: "Screenshoss folder", tooltipPlacement: .leading) {
                    library.openStorageFolder()
                }
                .accessibilityLabel("Open screenshots folder")
            }
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
    var maxFolderScrollWidth: CGFloat = 560
    var showsAddButton = true
    @State private var bumpedFolderName: String?
    @State private var folderContentWidth: CGFloat = 1
    @State private var folderScrollOffset: CGFloat = 0
    @State private var folderMaximumScrollOffset: CGFloat = 0

    private let folderFadeWidth: CGFloat = 64

    var body: some View {
        let scrollWidth = min(maxFolderScrollWidth, max(1, folderContentWidth))
        let isOverflowing = folderContentWidth > maxFolderScrollWidth
        let shouldShowLeadingFade = isOverflowing && folderScrollOffset > 2
        let shouldShowTrailingFade = isOverflowing && folderScrollOffset < folderMaximumScrollOffset - 2

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
                    ZStack {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: FolderContentWidthKey.self, value: proxy.size.width)
                        }

                        FolderScrollPositionReader { offset, maximumOffset in
                            folderScrollOffset = offset
                            folderMaximumScrollOffset = maximumOffset
                        }
                    }
                }
            }
            .frame(width: scrollWidth, alignment: .leading)
            .mask(
                LinearGradient(
                    stops: folderMaskStops(
                        showsLeadingFade: shouldShowLeadingFade,
                        showsTrailingFade: shouldShowTrailingFade,
                        width: scrollWidth
                    ),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onPreferenceChange(FolderContentWidthKey.self) { folderContentWidth = $0 }

            if showsAddButton {
                FolderAddButton(library: library)
            }
        }
        .frame(height: 42)
        .frame(width: scrollWidth + (showsAddButton ? 42 : 0), alignment: .leading)
    }

    private var recentBumpID: String {
        "__recent__"
    }

    private func folderMaskStops(
        showsLeadingFade: Bool,
        showsTrailingFade: Bool,
        width: CGFloat
    ) -> [Gradient.Stop] {
        let fadeFraction = min(0.45, folderFadeWidth / max(width, 1))
        var stops: [Gradient.Stop] = []

        if showsLeadingFade {
            stops.append(contentsOf: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.34), location: fadeFraction * 0.26),
                .init(color: .black.opacity(0.82), location: fadeFraction * 0.58),
                .init(color: .black, location: fadeFraction)
            ])
        } else {
            stops.append(.init(color: .black, location: 0))
        }

        if showsTrailingFade {
            stops.append(contentsOf: [
                .init(color: .black, location: 1 - fadeFraction),
                .init(color: .black.opacity(0.82), location: 1 - fadeFraction * 0.58),
                .init(color: .black.opacity(0.34), location: 1 - fadeFraction * 0.26),
                .init(color: .clear, location: 1)
            ])
        } else {
            stops.append(.init(color: .black, location: 1))
        }

        return stops
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

private struct FolderScrollPositionReader: NSViewRepresentable {
    let onChange: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> FolderScrollObserverView {
        let view = FolderScrollObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: FolderScrollObserverView, context: Context) {
        view.onChange = onChange
        view.attachAndPublish()
    }

    static func dismantleNSView(_ view: FolderScrollObserverView, coordinator: Void) {
        view.detach()
    }
}

private final class FolderScrollObserverView: NSView {
    var onChange: ((CGFloat, CGFloat) -> Void)?
    private weak var observedScrollView: NSScrollView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachAndPublish()
    }

    func attachAndPublish() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let scrollView = enclosingScrollView else { return }

            if observedScrollView !== scrollView {
                detach()
                observedScrollView = scrollView
                scrollView.contentView.postsBoundsChangedNotifications = true
                scrollView.documentView?.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(scrollMetricsDidChange),
                    name: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView
                )
                if let documentView = scrollView.documentView {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(scrollMetricsDidChange),
                        name: NSView.frameDidChangeNotification,
                        object: documentView
                    )
                }
            }

            publishScrollMetrics()
        }
    }

    func detach() {
        NotificationCenter.default.removeObserver(self)
        observedScrollView = nil
    }

    @objc private func scrollMetricsDidChange() {
        publishScrollMetrics()
    }

    private func publishScrollMetrics() {
        guard let scrollView = observedScrollView else { return }
        let visibleRect = scrollView.contentView.bounds
        let documentWidth = scrollView.documentView?.frame.width ?? visibleRect.width
        let maximumOffset = max(0, documentWidth - visibleRect.width)
        let offset = min(max(0, visibleRect.minX), maximumOffset)
        onChange?(offset, maximumOffset)
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

private struct FolderAddButton: View {
    @ObservedObject var library: ScreenshotLibrary
    var tooltipPlacement: PanelTooltipPlacement = .below
    @State private var isHovered = false

    var body: some View {
        Button(action: library.createFolder) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(FolderAddButtonStyle(isHovered: isHovered))
        .onHover { isHovered = $0 }
        .accessibilityLabel("Create folder")
        .panelTooltip(
            "Create folder",
            isPresented: isHovered,
            placement: tooltipPlacement,
            yOffset: tooltipPlacement == .below ? 42 : 0
        )
        .zIndex(isHovered ? 50 : 0)
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
    var tooltipPlacement: PanelTooltipPlacement = .below
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .rotationEffect(.degrees(rotationDegrees))
        }
        .buttonStyle(CircleButtonStyle(isHovered: isHovered, isSelected: isSelected))
        .onHover { isHovered = $0 }
        .panelTooltip(
            tooltip,
            isPresented: isHovered,
            placement: tooltipPlacement,
            yOffset: tooltipPlacement == .below ? 42 : 0
        )
        .zIndex(isHovered ? 50 : 0)
    }
}
