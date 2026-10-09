import SwiftUI
import UniformTypeIdentifiers

/// Root of the panel. Draws the island at top-centre; everything else in the
/// window is transparent and click-through (see `PassthroughHostingView`).
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel

    private var isOpen: Bool { viewModel.state == .open }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.all)
        .animation(.notchSpring, value: viewModel.state)
        .animation(.notchSpring, value: viewModel.islandSize)
    }

    /// Reports where the island actually landed. The window is placed by hand
    /// and the hit-test rect is derived from the same numbers, so a silent
    /// disagreement between layout and maths shows up here rather than as an
    /// unclickable strip the user has to discover.
    private var geometryProbe: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { Trace.log("layout", "island \(frame)") }
                .onChange(of: frame) { _, new in Trace.log("layout", "island \(new)") }
        }
        .allowsHitTesting(false)
    }

    /// Closed, the island wears MacBook Pro proportions. Open, it is a panel
    /// rather than a notch, so it gets its own softer radii.
    private var notchShape: NotchShape {
        isOpen
            ? NotchShape(topRadius: 12, bottomRadius: 24)
            : .macBookPro(height: viewModel.islandSize.height)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            notchShape
                .fill(.black)
                .overlay {
                    notchShape
                        .stroke(Color.white.opacity(isOpen ? 0.12 : 0), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(isOpen ? 0.55 : 0), radius: 18, y: 8)

            // Keep the contents inside the island. Without this they render
            // outside it whenever the two are momentarily out of step — which
            // is every transition — leaving tab labels and body text floating
            // on the desktop with no black behind them.
            //
            // Clipped to the island's rect, on the content alone. The obvious
            // `.clipShape(notchShape)` on the whole stack does the same job but
            // renders SF Symbols greyscale, which silently drained the tint out
            // of every status icon; and clipping the stack would eat the shape's
            // ears, which by design sit outside the frame.
            content
                .frame(
                    width: viewModel.islandSize.width,
                    height: viewModel.islandSize.height
                )
                .clipped()
        }
        .frame(width: viewModel.islandSize.width, height: viewModel.islandSize.height)
        .background { geometryProbe }
        .contentShape(Rectangle())
        // Drops are handled in AppKit by `PassthroughHostingView`, not here —
        // SwiftUI's `onDrop` rewrote the type list and dropped `public.file-url`
        // on the floor, so files never registered as a valid drag at all.
    }

    @ViewBuilder
    private var content: some View {
        if isOpen {
            ExpandedView(viewModel: viewModel)
                .transition(.opacity.combined(with: .offset(y: -8)))
        } else {
            CollapsedView(viewModel: viewModel)
                .transition(.opacity)
        }
    }
}
