//
//  MarkingText.swift
//  LibraryMerger
//

import SwiftUI

// MarkingText is what a marking conflict shows of the publication text
struct MarkingText {
    // Whether the user wants to see the text, and whether the marking has text to show
    var enabled = false
    var available = false
    // The marked paragraphs, nil while they load. They are empty if jw.org has no text of the
    // publication.
    var snippets: [MarkingSnippet]?
    // Whether the text could not be loaded, for example when offline
    var failed = false
    // How many bytes of the publication are downloaded, out of total, which is -1 if unknown
    var downloaded: Int64 = 0
    var total: Int64 = -1
    var load: () -> Void = {}
    var hide: () -> Void = {}
    // Links the scrolling text of both sides, and selects this side when the text is tapped
    var link = ScrollLink()
    var select: () -> Void = {}
    // The marked paragraphs of the other side, so both sides start at the same lines
    var otherSnippets: [MarkingSnippet]?
}

extension MarkingText {
    var loading: Bool {
        enabled && available && snippets == nil && !failed
    }

    // Trying again might help if the text could not be loaded, for example when offline
    var canRetry: Bool {
        enabled && available && failed
    }

    // unavailableReason tells why no text is shown, if the user wants to see it
    var unavailableReason: LocalizedStringKey? {
        if canRetry {
            return "Couldn't load the text from jw.org"
        } else if enabled && available && snippets?.isEmpty == true {
            return "jw.org has no text of this publication"
        }
        return nil
    }
}

// WordShapes draws the words around a marking as small shapes, so the marked words and their
// overlap with the other side are visible without the text. While the text downloads, the
// shapes darken from left to right and the marked ones pulse.
struct WordShapes: View {
    var blockRange: BlockRange
    var other: BlockRange?
    var color: Color
    var loading = false
    // How much of the text is downloaded, nil if unknown
    var progress: Double?
    @State private var width: CGFloat = 0

    var body: some View {
        TimelineView(.animation(paused: !loading)) { context in
            let pulse = loading ? 0.75 + 0.25 * cos(context.date.timeIntervalSinceReferenceDate * 4) : 1
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { token in
                            shape(token, pulse: pulse)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { width = geometry.size.width }
                .onChange(of: geometry.size.width) { width = $0 }
        })
        .accessibilityHidden(true)
    }

    private var marked: ClosedRange<Int> {
        tokenRange(blockRange)
    }

    private var otherMarked: ClosedRange<Int>? {
        guard let other = other, other.startToken.valid, other.endToken.valid else { return nil }
        return tokenRange(other)
    }

    // A backup could have the end before the start, which must not crash the conflict screen
    private func tokenRange(_ blockRange: BlockRange) -> ClosedRange<Int> {
        let start = Int(blockRange.startToken.int32), end = Int(blockRange.endToken.int32)
        return min(start, end)...max(start, end)
    }

    // A few words around both markings are shown
    private var tokens: ClosedRange<Int> {
        let start = min(marked.lowerBound, otherMarked?.lowerBound ?? marked.lowerBound)
        let end = max(marked.upperBound, otherMarked?.upperBound ?? marked.upperBound)
        return max(0, start - 6)...(end + 6)
    }

    // Word lengths are not known without the text, so the shapes vary in a fixed pattern
    private func shapeWidth(_ token: Int) -> CGFloat {
        CGFloat(14 + (token * 37) % 23)
    }

    private var rows: [[Int]] {
        var rows: [[Int]] = [[]]
        var rowWidth: CGFloat = 0
        for token in tokens {
            let shape = shapeWidth(token) + 4
            if rowWidth + shape > (width > 0 ? width : 200) && !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(token)
            rowWidth += shape
        }
        return rows
    }

    private func shape(_ token: Int, pulse: Double) -> some View {
        let reached = progress.map { Double(token - tokens.lowerBound) / Double(tokens.count) < $0 } ?? false
        let isMarked = marked.contains(token)
        return Capsule()
            .fill(isMarked ? color : Color(reached ? .systemGray3 : .systemGray5))
            .opacity(isMarked && loading && !reached ? pulse : 1)
            .frame(width: shapeWidth(token), height: 8)
            .overlay(Capsule()
                .fill(Color(.systemGray2))
                .frame(height: 2)
                .offset(y: 5)
                .opacity(otherMarked?.contains(token) ?? false ? 1 : 0),
                     alignment: .bottom)
    }
}

// ParagraphScroller shows a whole paragraph in a few lines with soft edges, centered on the
// marked text, and lets the user scroll through the rest of it. The scrollers of both sides are
// linked, so they always show the same lines.
struct ParagraphScroller: View {
    var text: NSAttributedString
    // The marked text of both sides, which the scroller starts centered on
    var marked: [NSRange]
    var link: ScrollLink
    var onTap: () -> Void
    @ScaledMetric private var maxHeight: CGFloat = 110
    @State private var textHeight: CGFloat = 0
    // Whether there is more text above or below to scroll to
    @State private var more = (above: false, below: false)

    var body: some View {
        LinkedText(text: text, marked: marked, link: link, onTap: onTap, height: $textHeight,
                   more: $more)
            .frame(height: textHeight == 0 ? maxHeight : min(textHeight, maxHeight))
            .mask(fade)
    }

    // An edge only fades out when there is more text beyond it
    private var fade: LinearGradient {
        LinearGradient(gradient: Gradient(stops: [.init(color: .black.opacity(more.above ? 0 : 1), location: 0),
                                                  .init(color: .black, location: 0.2),
                                                  .init(color: .black, location: 0.8),
                                                  .init(color: .black.opacity(more.below ? 0 : 1), location: 1)]),
                       startPoint: .top, endPoint: .bottom)
    }
}

// ScrollLink moves the linked scrollers along with the one the user scrolls, including its bounce
// past the edges
final class ScrollLink {
    private let views = NSHashTable<UIScrollView>.weakObjects()
    private weak var active: UIScrollView?

    func add(_ view: UIScrollView) {
        views.add(view)
    }

    func begin(_ view: UIScrollView) {
        active = view
        // A linked scroller that is still moving stops, so the two don't move against each other
        for other in views.allObjects where other !== view && other.tag == view.tag {
            other.setContentOffset(other.contentOffset, animated: false)
        }
    }

    func follow(_ view: UIScrollView) {
        guard view === active else { return }
        for other in views.allObjects where other !== view && other.tag == view.tag {
            other.contentOffset = view.contentOffset
        }
    }
}

// LinkedText is the UIKit text view behind ParagraphScroller, because SwiftUI on iOS 15 can
// neither read nor set a scroll position
struct LinkedText: UIViewRepresentable {
    var text: NSAttributedString
    var marked: [NSRange]
    var link: ScrollLink
    var onTap: () -> Void
    @Binding var height: CGFloat
    @Binding var more: (above: Bool, below: Bool)

    func makeUIView(context: Context) -> CenteringTextView {
        let view = CenteringTextView()
        view.isEditable = false
        view.isSelectable = false
        view.backgroundColor = .clear
        view.showsVerticalScrollIndicator = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.layoutManager.allowsNonContiguousLayout = false
        view.delegate = context.coordinator
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator,
                                                         action: #selector(Coordinator.tap)))
        link.add(view)
        return view
    }

    func updateUIView(_ view: CenteringTextView, context: Context) {
        context.coordinator.parent = self
        // Only scrollers showing the same paragraph are linked
        view.tag = text.string.hashValue
        view.marked = marked
        view.onHeight = { newHeight in
            DispatchQueue.main.async {
                if height != newHeight {
                    height = newHeight
                }
            }
        }
        // Setting the text centers it again, so it is only set when the words or markings change
        let shown = context.coordinator.shown
        if shown?.text != text.string || shown?.marked != marked {
            context.coordinator.shown = (text.string, marked)
            view.attributedText = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: LinkedText
        var shown: (text: String, marked: [NSRange])?

        init(parent: LinkedText) {
            self.parent = parent
        }

        @objc func tap() {
            parent.onTap()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.link.begin(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.link.follow(scrollView)
            let offset = scrollView.contentOffset.y
            let more = (above: offset > 0.5,
                        below: offset + scrollView.bounds.height < scrollView.contentSize.height - 0.5)
            if more != parent.more {
                DispatchQueue.main.async { self.parent.more = more }
            }
        }
    }
}

// CenteringTextView reports the height of its text and centers the marked text when the text or
// its size changes, like after a rotation. While the user scrolls, it stays where it is.
final class CenteringTextView: UITextView {
    var marked: [NSRange] = []
    var onHeight: (CGFloat) -> Void = { _ in }
    private var centeredSize = CGSize.zero
    private var needsCentering = true

    override var attributedText: NSAttributedString! {
        didSet { needsCentering = true }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != centeredSize {
            needsCentering = true
        }
        guard needsCentering, bounds.width > 0 else { return }
        needsCentering = false
        centeredSize = bounds.size
        // Lay out all the text at once, so its size doesn't change while scrolling
        layoutManager.ensureLayout(for: textContainer)
        onHeight(sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)
        let rects = marked.map { range in
            layoutManager.boundingRect(forGlyphRange: layoutManager.glyphRange(forCharacterRange: range,
                                                                               actualCharacterRange: nil),
                                       in: textContainer)
        }
        let middle = ((rects.map(\.minY).min() ?? 0) + (rects.map(\.maxY).max() ?? 0)) / 2
        let maxOffset = max(0, contentSize.height - bounds.height)
        contentOffset.y = min(max(0, middle - bounds.height / 2), maxOffset)
        // The edges fade depending on the position, also when centering didn't move the text
        delegate?.scrollViewDidScroll?(self)
    }
}

// MarkingTextInfo explains, before the text is loaded the first time, where it comes from
struct MarkingTextInfo: View {
    var showText: () -> Void
    var notNow: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "quote.opening")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(14)
            Text("Show the marked text?")
                .font(.headline)
            Text("markingText.info")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: showText, label: {
                Text("Show Text")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            })
            .accessibilityIdentifier("show-marking-text")
            Button("Not Now", action: notNow)
        }
        .padding(24)
        .modifier(CompactSheet())
    }
}

// CompactSheet shows a sheet only as high as needed, where iOS supports it
struct CompactSheet: ViewModifier {
    func body(content: Content) -> some View {
        // Large text sizes don't fit, so the content scrolls then
        if #available(iOS 16.0, *) {
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }
            .presentationDetents([.height(340)])
        } else {
            ScrollView { content }
        }
    }
}
