import SwiftUI
import AppKit

/// Centered "What's New" card, raised after an upgrade (auto) or from
/// Settings ▸ About (manual). Same modal language as `AgentLaunchChooser` /
/// `CommandPalette`: a solid `bgPane` card over a dim scrim, Esc / click-out /
/// "Got it" to dismiss. Content is hand-authored per version (`ReleaseNotes`),
/// already localized as data by `WorkspaceStore.whatsNewLines`.
///
/// Visual style: restrained, left-aligned, dense — Linear/Arc release-notes
/// language rather than a celebratory system-update banner.
struct WhatsNewView: View {
    @EnvironmentObject var store: WorkspaceStore
    let notes: [ReleaseNote]

    @FocusState private var focused: Bool

    /// Only stamp a per-section version caption when catching up across several
    /// versions — for a single note the header already carries the version.
    private var multiVersion: Bool { notes.count > 1 }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().overlay(Theme.overlay(0.06))
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(notes) { note in section(note) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .frame(maxHeight: 340)
                Divider().overlay(Theme.overlay(0.06))
                footer
            }
            .frame(width: 460)
            .background(
                Theme.bgPane
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.overlay(0.08), lineWidth: 0.5)
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 30, y: 12)
            .padding(.top, -40)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.escape) { store.dismissWhatsNew(); return .handled }
        // `modalOverlay` already took keys off the prior responder; just claim
        // focus so Esc / the default action land here.
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 11) {
            Image(store.appIconPreset.headerLogoAsset)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("What's New")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text1)
                // "Glint · v0.1.24" — brand + version are data, never localized.
                Text(verbatim: "Glint · \(ReleaseNotes.displayVersion(notes.first?.version ?? ""))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.text4)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 13)
    }

    private func section(_ note: ReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if multiVersion {
                Text(verbatim: ReleaseNotes.displayVersion(note.version))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(store.accent)
                    .textCase(.uppercase)
            }
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(store.whatsNewLines(note).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle()
                            .fill(store.accent.opacity(0.55))
                            .frame(width: 5, height: 5)
                            .padding(.top, 5)
                        // Note copy is data (already language-picked); verbatim.
                        Text(verbatim: line)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.text2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button { store.dismissWhatsNew() } label: {
                Text("Got it")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(store.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(store.accent.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
