import SwiftUI

/// The island outline: square against the top screen edge, rounded at the
/// bottom, with concave "ears" that flare outward so the black shape melts into
/// the menu bar instead of sitting on top of it.
///
/// Every corner is a true circular fillet built with `addArc(tangent1End:…)`,
/// which is tangent to both edges by construction. The earlier version used
/// quadratic curves with the control point parked on the corner; that is close
/// to a circle but not one, and it read as slightly soft and inflated next to
/// the real thing.
///
/// The ears are drawn *outside* the shape's rect (by `topRadius` on each side),
/// which keeps the caller's layout maths about the island body only.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    init(topRadius: CGFloat = 5, bottomRadius: CGFloat = 8) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    /// Corner radii proportioned like the MacBook Pro camera housing.
    ///
    /// Measured off the real notch: it is ~37 pt tall with roughly a 10 pt
    /// bottom radius and a 5–6 pt top fillet, so the bottom corner is about a
    /// quarter of the height and the ear about a sixth. Those ratios are what
    /// make it read as a notch rather than as a floating pill — the shape is
    /// squarer than it looks from memory.
    static func macBookPro(height: CGFloat) -> NotchShape {
        NotchShape(
            topRadius: (height * 0.15).rounded(),
            bottomRadius: (height * 0.26).rounded()
        )
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.height))
        let bottom = max(0, min(bottomRadius, min(rect.width / 2, rect.height)))

        var path = Path()

        // Start out on the menu bar, left of the island, level with the screen
        // edge. This is the tangent point of the left ear.
        path.move(to: CGPoint(x: rect.minX - top, y: rect.minY))

        // Concave ear: filleted around the top-left corner of the body, so it
        // curves down out of the menu bar into the island's left edge.
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
            radius: top
        )

        // Bottom-left corner.
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
            radius: bottom
        )

        // Bottom-right corner.
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
            radius: bottom
        )

        // Concave ear on the right, back out onto the menu bar.
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX + top, y: rect.minY),
            radius: top
        )

        // Close along the top edge, flush against the bezel.
        path.closeSubpath()

        return path
    }
}

#Preview {
    VStack(spacing: 40) {
        ForEach([30.0, 37.0], id: \.self) { height in
            ZStack(alignment: .top) {
                Color.gray
                NotchShape.macBookPro(height: height)
                    .fill(.black)
                    .frame(width: 210, height: height)
            }
            .frame(width: 460, height: 90)
        }
    }
    .padding()
}
