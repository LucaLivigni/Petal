import Foundation

/// Crop-rectangle maths for the photo editor, in normalised (0…1) coordinates with a top-left origin.
nonisolated enum CropGeometry {
    enum Handle: CaseIterable {
        case move, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var movesLeft: Bool { [.left, .topLeft, .bottomLeft].contains(self) }
        var movesRight: Bool { [.right, .topRight, .bottomRight].contains(self) }
        var movesTop: Bool { [.top, .topLeft, .topRight].contains(self) }
        var movesBottom: Bool { [.bottom, .bottomLeft, .bottomRight].contains(self) }
        var isCorner: Bool { [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(self) }
    }

    static let minimumSize = 0.04

    /// Which part of `crop` (in view points) is under `point`: a handle, the inside, or nothing.
    static func hit(_ point: CGPoint, crop: CGRect, tolerance: CGFloat = 16) -> Handle? {
        let nearLeft = abs(point.x - crop.minX) <= tolerance, nearRight = abs(point.x - crop.maxX) <= tolerance
        let nearTop = abs(point.y - crop.minY) <= tolerance, nearBottom = abs(point.y - crop.maxY) <= tolerance
        let withinX = point.x >= crop.minX - tolerance && point.x <= crop.maxX + tolerance
        let withinY = point.y >= crop.minY - tolerance && point.y <= crop.maxY + tolerance
        guard withinX && withinY else { return nil }
        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        default: return crop.contains(point) ? .move : nil
        }
    }

    /// The crop after dragging `handle` by (dx, dy), both normalised. `ratio` is the locked width ÷ height *in normalised units*.
    static func dragged(_ start: CGRect, handle: Handle, dx: Double, dy: Double, ratio: Double?) -> CGRect {
        if handle == .move {
            let x = min(max(0, start.minX + dx), 1 - start.width)
            let y = min(max(0, start.minY + dy), 1 - start.height)
            return CGRect(x: x, y: y, width: start.width, height: start.height)
        }

        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        if handle.movesLeft { minX = min(max(0, minX + dx), maxX - minimumSize) }
        if handle.movesRight { maxX = max(min(1, maxX + dx), minX + minimumSize) }
        if handle.movesTop { minY = min(max(0, minY + dy), maxY - minimumSize) }
        if handle.movesBottom { maxY = max(min(1, maxY + dy), minY + minimumSize) }
        let free = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard let ratio, ratio > 0 else { return free }

        if handle.isCorner {
            // The opposite corner stays put; the rectangle grows towards the pointer at the locked ratio.
            let anchorX = handle.movesLeft ? start.maxX : start.minX
            let anchorY = handle.movesTop ? start.maxY : start.minY
            let availableW = handle.movesLeft ? anchorX : 1 - anchorX
            let availableH = handle.movesTop ? anchorY : 1 - anchorY
            var w = max(free.width, free.height * ratio)
            w = min(w, availableW, availableH * ratio)
            w = max(w, minimumSize)
            let h = w / ratio
            return CGRect(x: handle.movesLeft ? anchorX - w : anchorX, y: handle.movesTop ? anchorY - h : anchorY, width: w, height: h)
        }

        let midX = start.midX, midY = start.midY
        if handle == .top || handle == .bottom {
            let availableH = handle == .top ? start.maxY : 1 - start.minY
            var h = min(free.height, availableH, 2 * min(midX, 1 - midX) / ratio)
            h = max(h, minimumSize / ratio)
            let w = h * ratio
            return CGRect(x: midX - w / 2, y: handle == .top ? start.maxY - h : start.minY, width: w, height: h)
        }
        let availableW = handle == .left ? start.maxX : 1 - start.minX
        var w = min(free.width, availableW, 2 * min(midY, 1 - midY) * ratio)
        w = max(w, minimumSize)
        let h = w / ratio
        return CGRect(x: handle == .left ? start.maxX - w : start.minX, y: midY - h / 2, width: w, height: h)
    }
}
