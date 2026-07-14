import AppKit
import SwiftUI

struct FloatingIconButton: View {
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
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(isHovered ? 1.0 : 0.1), lineWidth: 1)
                .blur(radius: isHovered ? 0 : 2)
                .clipShape(Circle())
                .allowsHitTesting(false)
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

struct FloatingIconButtonStyle: ButtonStyle {
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

struct DetailPaneView: View {
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

struct EmptyShelfView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(20)
    }
}

struct CircleButtonStyle: ButtonStyle {
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
