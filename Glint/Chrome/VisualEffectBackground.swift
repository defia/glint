import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State
    /// When false the area refuses to initiate window-dragging on mouseDown.
    /// Default is false so sidebars / panes don't grab the window by accident;
    /// the toolbar opts in explicitly.
    let allowsWindowDrag: Bool

    init(material: NSVisualEffectView.Material = .sidebar,
         blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
         state: NSVisualEffectView.State = .followsWindowActiveState,
         allowsWindowDrag: Bool = false) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.allowsWindowDrag = allowsWindowDrag
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v: NSVisualEffectView = allowsWindowDrag
            ? NSVisualEffectView()
            : NoDragVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

private final class NoDragVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Invisible NSView whose only job is titlebar-style window dragging.
/// The header's Liquid Glass band draws via `.glassEffect` (no NSView of
/// ours), so this restores the drag behavior the NSVisualEffectView used
/// to provide.
struct WindowDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

// MARK: - Liquid Glass (macOS 26)

/// Whether the OS can render Liquid Glass at all. Call sites that keep a
/// separate flat style for the same state (e.g. a chip's fill) combine this
/// with the user's glass toggle so the two looks never stack.
var liquidGlassAvailable: Bool {
    if #available(macOS 26.0, *) { return true }
    return false
}

/// Puts macOS 26 Liquid Glass behind the content when the OS supports it and
/// the user's glass toggle is on; otherwise renders the supplied fallback as
/// a plain background. Centralizing the `#available` branch keeps call sites
/// to a single modifier — they describe both looks in one place instead of
/// forking their whole view chain.
struct LiquidGlassSurface<Fallback: View>: ViewModifier {
    let enabled: Bool
    let cornerRadius: CGFloat
    var tint: Color?
    var interactive: Bool
    @ViewBuilder let fallback: () -> Fallback

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), enabled {
            content.glassEffect(
                glass,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.background(fallback())
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var g: Glass = .regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

extension View {
    /// Liquid Glass with no fallback — for accents (chips, button wells)
    /// whose pre-26 look is already painted by the call site.
    func liquidGlass(enabled: Bool,
                     cornerRadius: CGFloat,
                     tint: Color? = nil,
                     interactive: Bool = false) -> some View {
        modifier(LiquidGlassSurface(enabled: enabled,
                                    cornerRadius: cornerRadius,
                                    tint: tint,
                                    interactive: interactive,
                                    fallback: { EmptyView() }))
    }

    /// Liquid Glass that replaces an entire background — the fallback is
    /// what pre-26 systems (or glass-off users) get instead.
    func liquidGlass<F: View>(enabled: Bool,
                              cornerRadius: CGFloat,
                              tint: Color? = nil,
                              interactive: Bool = false,
                              @ViewBuilder fallback: @escaping () -> F) -> some View {
        modifier(LiquidGlassSurface(enabled: enabled,
                                    cornerRadius: cornerRadius,
                                    tint: tint,
                                    interactive: interactive,
                                    fallback: fallback))
    }
}
