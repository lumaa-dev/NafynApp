// Made by Lumaa

import SwiftUI

/// A minimal wrapping horizontal layout (subviews flow onto new lines once they'd overflow the
/// available width) — used to lay out per-word/per-syllable lyric segments without pulling in a
/// third-party wrapping-stack dependency.
struct FlowLayout: Layout {
	var alignment: HorizontalAlignment = .leading
	var spacing: CGFloat = 6
	var lineSpacing: CGFloat = 4

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let maxWidth = proposal.width ?? .infinity
		let rows = self.rows(for: subviews, maxWidth: maxWidth)

		var height: CGFloat = 0
		var width: CGFloat = 0
		for row in rows {
			height += row.height + (height > 0 ? self.lineSpacing : 0)
			width = max(width, row.width)
		}
		return CGSize(width: maxWidth.isFinite ? maxWidth : width, height: height)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		let rows = self.rows(for: subviews, maxWidth: bounds.width)

		var y = bounds.minY
		for row in rows {
			var x = self.alignment == .trailing ? bounds.maxX - row.width : bounds.minX
			for index in row.indices {
				let size = subviews[index].sizeThatFits(.unspecified)
				subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
				x += size.width + self.spacing
			}
			y += row.height + self.lineSpacing
		}
	}

	private struct Row {
		var indices: [Int] = []
		var width: CGFloat = 0
		var height: CGFloat = 0
	}

	private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
		var rows: [Row] = [Row()]

		for index in subviews.indices {
			let size = subviews[index].sizeThatFits(.unspecified)
			var current = rows[rows.count - 1]
			let projectedWidth = current.width + (current.indices.isEmpty ? 0 : self.spacing) + size.width

			if projectedWidth > maxWidth, !current.indices.isEmpty {
				rows.append(Row())
				current = Row()
			}

			current.indices.append(index)
			current.width += (current.indices.count > 1 ? self.spacing : 0) + size.width
			current.height = max(current.height, size.height)
			rows[rows.count - 1] = current
		}

		return rows
	}
}
