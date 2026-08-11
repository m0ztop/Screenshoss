import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var library: ScreenshotLibrary
    @State private var hoverCollapseTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch library.presentationMode {
            case .top:
                TopNotchShelfView(library: library)
            case .left, .right:
                SideNotchShelfView(library: library, side: library.presentationMode)
            }
        }
        .animation(
            .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.08),
            value: library.isExpanded
        )
        .animation(
            .spring(response: 0.32, dampingFraction: 0.9, blendDuration: 0.08),
            value: library.presentationMode
        )
        .onHover { hovering in
            hoverCollapseTask?.cancel()
            if hovering {
                library.isExpanded = true
            } else {
                scheduleHoverCollapseCheck()
            }
        }
    }

    private func scheduleHoverCollapseCheck() {
        hoverCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            if library.shouldCollapseAfterHoverExit?() ?? true {
                library.isExpanded = false
            } else {
                scheduleHoverCollapseCheck()
            }
        }
    }
}

private struct TrashUndoOverlay: View {
    @ObservedObject var library: ScreenshotLibrary

    var body: some View {
        if let notice = library.trashUndoNotice {
            TrashUndoBar(notice: notice) {
                library.undoLastTrash()
            }
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(200)
        }
    }
}

private struct TrashUndoBar: View {
    let notice: TrashUndoNotice
    let undoAction: () -> Void
    @State private var isUndoHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            Text(notice.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            Button("Undo", action: undoAction)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    .white.opacity(isUndoHovered ? 0.2 : 0.12),
                    in: Capsule()
                )
                .onHover { isUndoHovered = $0 }
                .accessibilityLabel("Undo moving screenshots to Trash")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background {
            ZStack {
                VisualEffectBackground(material: .hudWindow)
                    .clipShape(Capsule())
                Capsule()
                    .fill(.black.opacity(0.78))
            }
        }
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }
}
private struct TopNotchShelfView: View {
    @ObservedObject var library: ScreenshotLibrary

    var body: some View {
        ZStack(alignment: .top) {
            if library.isExpanded {
                ExpandedShelfView(library: library)
                    .zIndex(2)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                        )
                    )
            } else {
                CollapsedNotchView()
                    .zIndex(1)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SideNotchShelfView: View {
    @ObservedObject var library: ScreenshotLibrary
    let side: ShelfPresentationMode

    var body: some View {
        ZStack(alignment: alignment) {
            if library.isExpanded {
                SideExpandedShelfView(library: library)
                    .zIndex(2)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.96, anchor: transitionAnchor).combined(with: .opacity),
                            removal: .scale(scale: 0.98, anchor: transitionAnchor).combined(with: .opacity)
                        )
                    )
            } else {
                CollapsedSideNotchView(side: side)
                    .zIndex(1)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.98, anchor: transitionAnchor).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var alignment: Alignment {
        side == .left ? .leading : .trailing
    }

    private var transitionAnchor: UnitPoint {
        side == .left ? .leading : .trailing
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
        ZStack {
            CollapsedNotchSilhouette()

            ScreenshossIconView()
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

private struct CollapsedNotchSilhouette: View {
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
        }
        .frame(width: 160, height: 34)
    }
}

private struct CollapsedSideNotchView: View {
    private static var hasAnimatedIconEntrance = false
    let side: ShelfPresentationMode
    @State private var iconVisible = false

    var body: some View {
        ZStack {
            CollapsedNotchSilhouette()
                .rotationEffect(.degrees(side == .left ? -90 : 90))
                .frame(width: 34, height: 160)

            ScreenshossIconView()
                .opacity(iconVisible ? 1 : 0)
                .scaleEffect(iconVisible ? 1 : 0.5)
        }
        .frame(width: 34, height: 160)
        .onAppear {
            if !Self.hasAnimatedIconEntrance {
                Self.hasAnimatedIconEntrance = true
                withAnimation(.easeOut(duration: 0.3).delay(0.16)) {
                    iconVisible = true
                }
            } else {
                iconVisible = true
            }
        }
    }
}

private struct SideExpandedShelfView: View {
    @ObservedObject var library: ScreenshotLibrary

    var body: some View {
        SideShelfContentView(library: library)
            .padding(.top, 14)
            .padding(.horizontal, 14)
            .background { SideExpandedShelfBackground() }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .bottom) {
                TrashUndoOverlay(library: library)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: library.trashUndoNotice)
    }
}

private struct SideExpandedShelfBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        ZStack {
            VisualEffectBackground(material: .hudWindow)
                .clipShape(shape)

            shape
                .fill(.black.opacity(0.78))

            shape
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear, .black.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shape
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ShelfContentView: View {
    @ObservedObject var library: ScreenshotLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeaderView(library: library)
                .zIndex(10)
            HStack(alignment: .top, spacing: 14) {
                ScreenshotGridView(library: library, topContentPadding: 6)
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
        .foregroundStyle(.white)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SideShelfContentView: View {
    @ObservedObject var library: ScreenshotLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SideHeaderView(library: library)
                .zIndex(10)

            ScreenshotGridView(library: library, columnCount: 2, topContentPadding: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct ExpandedShelfView: View {
    @ObservedObject var library: ScreenshotLibrary

    var body: some View {
        ShelfContentView(library: library)
        .padding(14)
        .background { ExpandedShelfBackground() }
        .overlay(alignment: .bottom) {
            TrashUndoOverlay(library: library)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: library.trashUndoNotice)
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
                        .fill(.black.opacity(0.82))
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

enum PanelTooltipPlacement {
    case below
    case leading
}

private struct PanelTooltipModifier: ViewModifier {
    let text: String?
    let isPresented: Bool
    let placement: PanelTooltipPlacement
    let xOffset: CGFloat
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: placement == .leading ? .trailing : .center) {
            if isPresented, let text {
                tooltip(text)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isPresented)
    }

    @ViewBuilder
    private func tooltip(_ text: String) -> some View {
        switch placement {
        case .below:
            PanelTooltipBubble(text: text)
                .offset(x: xOffset, y: yOffset)
        case .leading:
            HStack(spacing: 8) {
                PanelTooltipBubble(text: text)
                Color.clear
                    .frame(width: 32, height: 1)
            }
            .fixedSize()
            .offset(x: xOffset, y: yOffset)
        }
    }
}

extension View {
    func panelTooltip(
        _ text: String?,
        isPresented: Bool,
        placement: PanelTooltipPlacement = .below,
        xOffset: CGFloat = 0,
        yOffset: CGFloat
    ) -> some View {
        modifier(
            PanelTooltipModifier(
                text: text,
                isPresented: isPresented,
                placement: placement,
                xOffset: xOffset,
                yOffset: yOffset
            )
        )
    }
}
