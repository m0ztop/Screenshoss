import Foundation

struct ScreenshotSelectionService {
    private(set) var selectedItem: ScreenshotItem?
    private(set) var selectedIDs: Set<URL> = []
    private var anchorID: URL?

    mutating func setSingle(_ item: ScreenshotItem?) {
        selectedItem = item
        if let item {
            selectedIDs = [item.id]
            anchorID = item.id
        } else {
            selectedIDs = []
            anchorID = nil
        }
    }

    mutating func selectRange(through item: ScreenshotItem, in visibleItems: [ScreenshotItem]) {
        guard let anchorID,
              let anchorIndex = visibleItems.firstIndex(where: { $0.id == anchorID }),
              let itemIndex = visibleItems.firstIndex(where: { $0.id == item.id }) else {
            setSingle(item)
            return
        }

        let bounds = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
        selectedIDs = Set(visibleItems[bounds].map(\.id))
        selectedItem = item
    }

    mutating func toggle(_ item: ScreenshotItem, in visibleItems: [ScreenshotItem]) {
        if selectedIDs.contains(item.id), selectedIDs.count > 1 {
            selectedIDs.remove(item.id)
            if selectedItem == item {
                selectedItem = visibleItems.first { selectedIDs.contains($0.id) }
                anchorID = selectedItem?.id
            }
        } else {
            selectedIDs.insert(item.id)
            selectedItem = item
            anchorID = item.id
        }
    }

    mutating func remove(ids: Set<URL>) {
        selectedIDs.subtract(ids)
        if let selectedItem, ids.contains(selectedItem.id) {
            self.selectedItem = nil
        }
        if let anchorID, ids.contains(anchorID) {
            self.anchorID = selectedItem?.id
        }
    }

    mutating func removeItems(inFolder folderName: String, from items: [ScreenshotItem]) {
        let ids = Set(items.lazy.filter { $0.folderName == folderName }.map(\.id))
        remove(ids: ids)
    }

    func selectedItems(in visibleItems: [ScreenshotItem]) -> [ScreenshotItem] {
        let orderedItems = visibleItems.filter { selectedIDs.contains($0.id) }
        return orderedItems.isEmpty ? selectedItem.map { [$0] } ?? [] : orderedItems
    }

    mutating func restoreAfterMove(to movedURLs: [URL], visibleItems: [ScreenshotItem]) {
        let movedURLSet = Set(movedURLs)
        let visibleMovedItems = visibleItems.filter { movedURLSet.contains($0.url) }
        guard !visibleMovedItems.isEmpty else {
            setSingle(visibleItems.first)
            return
        }

        selectedIDs = Set(visibleMovedItems.map(\.id))
        selectedItem = visibleMovedItems.first
        anchorID = selectedItem?.id
    }

    mutating func reconcile(
        previousSelectedURL: URL?,
        allItems: [ScreenshotItem],
        visibleItems: [ScreenshotItem]
    ) {
        guard !allItems.isEmpty else {
            setSingle(nil)
            return
        }

        let visibleIDs = Set(visibleItems.map(\.id))
        selectedIDs.formIntersection(visibleIDs)

        if let previousSelectedURL,
           let updatedSelection = visibleItems.first(where: { $0.url == previousSelectedURL }) {
            selectedItem = updatedSelection
            if selectedIDs.isEmpty {
                selectedIDs = [updatedSelection.id]
                anchorID = updatedSelection.id
            }
            return
        }

        if let selectedItem, visibleItems.contains(selectedItem) {
            if selectedIDs.isEmpty {
                selectedIDs = [selectedItem.id]
                anchorID = selectedItem.id
            }
            return
        }

        setSingle(visibleItems.first)
    }
}
