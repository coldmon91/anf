import AppKit
import Quartz

/// Hosts one reusable `QLPreviewView`. Quick Look computes the document zoom
/// when the item (re)loads — if that happens while our frame is still zero (a
/// SwiftUI representable mounts before layout) or the inspector is later
/// resized, wide pages (docx) render cropped. So: pin the preview's frame in
/// layout() and refresh the item (debounced) whenever the width changes, which
/// makes QL re-fit the page to the current width — always.
final class QLPreviewWrapper: NSView {
    private let preview = QLPreviewView(frame: .zero, style: .normal)!
    private var currentURL: URL?
    private var lastFitWidth: CGFloat = 0
    private var refreshWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        preview.shouldCloseWithWindow = false
        addSubview(preview)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        preview.frame = bounds
        guard currentURL != nil, bounds.width > 1,
              abs(bounds.width - lastFitWidth) > 0.5 else { return }
        lastFitWidth = bounds.width
        // Debounced: a divider drag fires layout per frame; refresh once settled.
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.preview.refreshPreviewItem() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func setURL(_ url: URL?) {
        guard url != currentURL else { return }
        currentURL = url
        lastFitWidth = bounds.width   // the load computes fit for the CURRENT width
        if let url {
            preview.previewItem = url as NSURL
        } else {
            preview.previewItem = nil
        }
    }

    deinit {
        refreshWork?.cancel()
        preview.close()
    }
}
