import SwiftUI

/// Right-click menu for a file/folder. Mirrors the keyboard actions.
struct FileContextMenu: View {
    @Bindable var model: BrowserModel
    let item: FileItem

    var body: some View {
        Button("열기") { ensureSelected(); model.open(item) }

        if item.isBrowsableContainer {
            Button("여기서 터미널 열기") { FileOperations.openInTerminal(item.url) }
        }

        Divider()

        if model.selection.count > 1 {
            Button("\(model.selection.count)개 항목 이름 변경…") { model.batchRename() }
        } else {
            Button("이름 변경") { ensureSelected(); model.beginRename() }
        }
        Button("복제") { ensureSelected(); model.duplicateSelection() }

        Divider()

        if item.ext == "zip" && model.selection.count <= 1 {
            Button("압축 풀기") {
                ArchiveService.extract(item) { model.reload() }
            }
        } else {
            Button(model.selection.count > 1 ? "\(model.selection.count)개 항목 압축" : "압축") {
                ensureSelected()
                ArchiveService.compress(model.selectedItems) { model.reload() }
            }
        }

        Divider()

        Button("복사") { ensureSelected(); model.copySelectionToPasteboard() }
        Button("경로 복사") { ensureSelected(); model.copyPathToPasteboard() }
        Button("붙여넣기") { model.pasteFromPasteboard() }
        Button("Finder에서 보기") { ensureSelected(); model.revealSelection() }

        Divider()

        Button("휴지통으로 이동", role: .destructive) { ensureSelected(); model.trashSelection() }
    }

    private func ensureSelected() {
        if !model.selection.contains(item.id) { model.selection = [item.id] }
    }
}
