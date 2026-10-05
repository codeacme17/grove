import AppKit
import SwiftUI

struct DiffTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(width: 10_000_000, height: 10_000_000)
        textView.textContainer?.containerSize = textView.maxSize
        textView.textContainer?.widthTracksTextView = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.setAccessibilityLabel("Git diff")
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        let styled = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ])
        let source = text as NSString
        var offset = 0
        while offset < source.length {
            let range = source.lineRange(for: NSRange(location: offset, length: 0))
            let line = source.substring(with: range)
            let color: NSColor?
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") {
                color = .secondaryLabelColor
            } else if line.hasPrefix("+") { color = .systemGreen }
            else if line.hasPrefix("-") { color = .systemRed }
            else if line.hasPrefix("@@") { color = .systemBlue }
            else { color = nil }
            if let color { styled.addAttribute(.foregroundColor, value: color, range: range) }
            offset = NSMaxRange(range)
        }
        let scrollPosition = scrollView.contentView.bounds.origin
        let selection = textView.selectedRange()
        textView.textStorage?.setAttributedString(styled)
        let start = min(selection.location, source.length)
        textView.setSelectedRange(NSRange(location: start, length: min(selection.length, source.length - start)))
        scrollView.contentView.scroll(to: scrollPosition)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
