import SwiftUI

struct PaneView: View {
    @EnvironmentObject var store: WorkspaceStore
    let paneID: PaneID

    var body: some View {
        // No selected workspace means there is nothing sane to key a surface
        // by. Never fall back to a synthetic ID here: a random key would mint
        // a brand-new GhosttySurfaceView (and spawn a shell) on every render.
        // The store self-heals selection (deleteWorkspace always reselects),
        // so this placeholder is at most one frame.
        if let wsID = store.selectedWorkspaceID {
            paneBody(workspaceID: wsID)
        } else {
            Theme.bgPane
        }
    }

    private func paneBody(workspaceID: UUID) -> some View {
        let isFocused = store.currentFocusedPane == paneID
        let cwd = store.currentPanes[paneID]?.workingDirectory
        return ZStack {
            Theme.bgPane
            PaneSurfaceRepresentable(
                surfaceView: store.surfaceView(workspaceID: workspaceID, paneID: paneID, cwd: cwd),
                focused: isFocused
            )
            if !isFocused {
                Theme.bgPane.opacity(0.45)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.focus(paneID) }
    }
}
