import SwiftUI

// Measure each card at its actual column width, then place it in the shortest
// column. Expansion, Dynamic Type and window resizing all trigger a new layout.
struct WaterfallLayout: Layout {
    var minimumWidth: CGFloat
    var spacing: CGFloat

    private func arrangement(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let width = max(1, width)
        let count = max(1, Int((width + spacing) / (minimumWidth + spacing)))
        let columnWidth = max(1, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        var bottoms = Array(repeating: CGFloat.zero, count: count)
        let frames = subviews.map { view in
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let height = view.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            let frame = CGRect(x: CGFloat(column) * (columnWidth + spacing), y: bottoms[column], width: columnWidth, height: height)
            bottoms[column] += height + spacing
            return frame
        }
        return (frames, max(0, (bottoms.max() ?? 0) - spacing))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minimumWidth
        return CGSize(width: width, height: arrangement(width: width, subviews: subviews).height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(width: bounds.width, subviews: subviews)
        for (view, frame) in zip(subviews, layout.frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}

struct WaterfallGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    var minimumWidth: CGFloat = 300
    var spacing: CGFloat = 24
    @ViewBuilder let card: (Item) -> Card
    @State private var visibleCount = 60

    var body: some View {
        // Bound the initial measurement work for large libraries. The next batch
        // is appended when its lazy footer comes into view, preserving card IDs.
        LazyVStack(spacing: spacing) {
            WaterfallLayout(minimumWidth: minimumWidth, spacing: spacing) {
                ForEach(items.prefix(visibleCount)) { card($0) }
            }
            if visibleCount < items.count {
                Button("继续浏览书签") { visibleCount += 60 }
                    .font(.caption).padding()
                    .onAppear { visibleCount += 60 }
            }
        }
    }
}
