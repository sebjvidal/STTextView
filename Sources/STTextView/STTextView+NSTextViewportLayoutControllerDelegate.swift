//  Created by Marcin Krzyzanowski
//  https://github.com/krzyzanowskim/STTextView/blob/main/LICENSE.md

import AppKit
import STTextKitPlus

extension STTextView: NSTextViewportLayoutControllerDelegate {

    public func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
        let overdrawRect = preparedContentRect
        let minY: CGFloat
        let maxY: CGFloat
        let minX: CGFloat
        let maxX: CGFloat

        if !overdrawRect.isEmpty, overdrawRect.intersects(visibleRect) {
            // Use preparedContentRect for vertical overdraw and ensure visibleRect is included at the minimum,
            // the width is always bounds width for proper line wrapping.
            minX = min(overdrawRect.minX, max(visibleRect.minX, bounds.minX))
            minY = min(overdrawRect.minY, max(visibleRect.minY, bounds.minY))
            maxX = max(overdrawRect.maxX, visibleRect.maxX)
            maxY = max(overdrawRect.maxY, visibleRect.maxY)
        } else {
            // We use visible rect directly if preparedContentRect does not intersect.
            // This can happen if overdraw has not caught up with scrolling yet, such as before the first layout.
            minX = visibleRect.minX
            minY = visibleRect.minY
            maxX = visibleRect.maxX
            maxY = visibleRect.maxY
        }
        return CGRect(x: minX, y: minY, width: maxX, height: maxY - minY)
    }

    public func textViewportLayoutControllerWillLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        // TODO: update difference, not all layers
        contentView.subviews.removeAll {
            type(of: $0) != insertionPointViewClass
        }
    }

    public func textViewportLayoutController(_ textViewportLayoutController: NSTextViewportLayoutController, configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment) {
        let fragmentView = fragmentViewMap.object(forKey: textLayoutFragment) ?? TextLayoutFragmentView(layoutFragment: textLayoutFragment, frame: .zero)
        // Adjust position
        let oldFrame = fragmentView.frame
        fragmentView.frame = textLayoutFragment.layoutFragmentFrame.pixelAligned
        if !oldFrame.isAlmostEqual(to: fragmentView.frame)  {
            fragmentView.needsLayout = true
            fragmentView.needsDisplay = true
        }

        if let textLayoutFragment = textLayoutFragment as? STTextLayoutFragment {
            textLayoutFragment.showsInvisibleCharacters = showsInvisibleCharacters
        }

        contentView.addSubview(fragmentView)
        fragmentViewMap.setObject(fragmentView, forKey: textLayoutFragment)
    }

    public func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        updateFrameSizeIfNeeded()
        updateSelectionHighlights()
        adjustViewportOffsetIfNeeded()
        scrollView?.verticalRulerView?.invalidateHashMarks()

        for events in plugins.events {
            events.didLayoutViewportHandler?(textViewportLayoutController.viewportRange!)
        }
    }

    private func adjustViewportOffsetIfNeeded() {
        guard let clipView = scrollView?.contentView else {
            return
        }

        func adjustViewportOffset() {
            let viewportLayoutController = textLayoutManager.textViewportLayoutController
            var layoutYPoint: CGFloat = 0
            textLayoutManager.enumerateTextLayoutFragments(from: viewportLayoutController.viewportRange!.location, options: [.reverse, .ensuresLayout]) { layoutFragment in
                layoutYPoint = layoutFragment.layoutFragmentFrame.origin.y
                return true // NOTE: should break early (return false)?
            }

            if !layoutYPoint.isZero {
                let adjustmentDelta = bounds.minY - layoutYPoint
                viewportLayoutController.adjustViewport(byVerticalOffset: adjustmentDelta)
                scroll(CGPoint(x: clipView.bounds.minX, y: clipView.bounds.minY + adjustmentDelta))
                reflectScrolledClipView(clipView)
            }
        }

        let viewportLayoutController = textLayoutManager.textViewportLayoutController
        let contentOffset = clipView.bounds.minY
        if contentOffset < clipView.bounds.height, let viewportRange = viewportLayoutController.viewportRange,
            viewportRange.location > textLayoutManager.documentRange.location
        {
            // Nearing top, see if we need to adjust and make room above.
            adjustViewportOffset()
        } else if let viewportRange = viewportLayoutController.viewportRange, viewportRange.location == textLayoutManager.documentRange.location {
            // At top, see if we need to adjust and reduce space above.
            adjustViewportOffset()
        }
    }
}
