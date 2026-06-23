import SwiftUI
import AppKit

/// Shared modal-overlay language: a dim click-out scrim plus a centered content
/// view with the app's standard spring entrance, and — crucially — first
/// responder save/restore. On present we stash whoever held keyboard focus and
/// hand focus to the modal; on dismiss we hand it back, so closing the card
/// returns keys to the terminal surface instead of stranding focus on nothing.
///
/// `CommandPalette` and `AgentLaunchChooser` predate this and keep their own
/// hand-rolled scrim/focus handling (the palette has text-field-editor focus
/// quirks). They can migrate here later; new modals should use this.
extension View {
    func modalOverlay<OverlayContent: View>(
        isPresented: Bool,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> OverlayContent
    ) -> some View {
        modifier(ModalOverlay(isPresented: isPresented,
                              onDismiss: onDismiss,
                              overlayContent: content))
    }
}

private struct ModalOverlay<OverlayContent: View>: ViewModifier {
    let isPresented: Bool
    let onDismiss: () -> Void
    @ViewBuilder var overlayContent: () -> OverlayContent

    /// Whoever held keyboard focus when the modal opened, restored on dismiss.
    @State private var priorResponder: NSResponder?

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { onDismiss() }
                        .transition(.opacity)
                }
            }
            .overlay {
                if isPresented {
                    overlayContent()
                        .transition(.asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.97))
                                .combined(with: .offset(y: -8)),
                            removal: .opacity
                        ))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isPresented)
            .onChange(of: isPresented) { _, shown in
                if shown {
                    // Remember the focused view, then take keys off it so the
                    // modal (Esc / default action) receives them.
                    priorResponder = NSApp.keyWindow?.firstResponder
                    NSApp.keyWindow?.makeFirstResponder(nil)
                } else {
                    let target = priorResponder
                    priorResponder = nil
                    DispatchQueue.main.async {
                        guard let window = NSApp.keyWindow, let target,
                              window.firstResponder !== target else { return }
                        window.makeFirstResponder(target)
                    }
                }
            }
    }
}
