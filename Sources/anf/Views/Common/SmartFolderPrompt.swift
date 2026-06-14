import AppKit

/// Modal editor for a saved search (smart folder). Collects a name plus the rule
/// fields (filename contains, kinds, recency). Returns `(name, rule)` or nil if
/// cancelled. The caller supplies the search scope.
@MainActor
enum SmartFolderPrompt {
    /// Recency options shown in the popup, paired with their day count (nil = any).
    private static let recency: [(String, Int?)] = [
        (L("Any time", "전체 기간"), nil),
        (L("Past 7 days", "최근 7일"), 7),
        (L("Past 30 days", "최근 30일"), 30),
        (L("Past year", "최근 1년"), 365),
    ]

    static func run(scopeName: String,
                    existing: (name: String, rule: SmartRule)? = nil) -> (name: String, rule: SmartRule)? {
        let alert = NSAlert()
        alert.messageText = existing == nil ? L("New Smart Folder", "새 스마트 폴더")
                                            : L("Edit Smart Folder", "스마트 폴더 편집")
        alert.informativeText = L("Lists files under “\(scopeName)” that match these rules.",
                                  "“\(scopeName)” 이하에서 아래 조건에 맞는 파일을 모아 보여줍니다.")
        alert.addButton(withTitle: existing == nil ? L("Create", "만들기") : L("Save", "저장"))
        alert.addButton(withTitle: L("Cancel", "취소"))

        let width: CGFloat = 320
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 132))

        func field(_ y: CGFloat, _ placeholder: String, _ value: String = "") -> NSTextField {
            let f = NSTextField(frame: NSRect(x: 0, y: y, width: width, height: 22))
            f.placeholderString = placeholder
            f.stringValue = value
            container.addSubview(f)
            return f
        }

        let nameField = field(110, L("Name", "이름"), existing?.name ?? "")
        let containsField = field(80, L("File name contains", "파일명 포함"), existing?.rule.nameContains ?? "")
        let kindsField = field(50, L("Kinds, e.g. pdf, docx", "종류, 예: pdf, docx"),
                               existing?.rule.kindExtensions.joined(separator: ", ") ?? "")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 16, width: width, height: 24))
        popup.addItems(withTitles: recency.map(\.0))
        if let days = existing?.rule.modifiedWithinDays,
           let idx = recency.firstIndex(where: { $0.1 == days }) {
            popup.selectItem(at: idx)
        }
        container.addSubview(popup)

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let kinds = kindsField.stringValue
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
        let rule = SmartRule(
            nameContains: containsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            kindExtensions: kinds,
            modifiedWithinDays: recency[popup.indexOfSelectedItem].1)
        return (name, rule)
    }
}
