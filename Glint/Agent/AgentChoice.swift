import Foundation

/// Which agent (if any) to auto-launch in a freshly created terminal pane.
///
/// Shared by every "new terminal" surface — the New Workspace sheet's source
/// panes, the tab bar's "+" menu, and the command palette — so picking an
/// agent works the same way everywhere, not just on the worktree path.
/// `.shell` is the no-agent escape hatch (a bare shell, the default).
enum AgentChoice: String, CaseIterable, Identifiable {
    case claude = "Claude Code", codex = "Codex", opencode = "OpenCode", devin = "Devin", shell = "Shell only"

    /// Chip / menu label. Product names stay verbatim; only "Shell only" is UI
    /// copy, so it (and only it) is routed through the string catalog.
    /// `rawValue` is a String, so `Text(choice.rawValue)` would hit the verbatim
    /// overload and never localize — read this instead.
    var displayName: String { self == .shell ? String(localized: "Shell only") : rawValue }

    var id: String { rawValue }

    /// The command typed into the new pane's shell, or nil for a bare shell.
    var command: String? {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .opencode: return "opencode"
        case .devin: return "devin"
        case .shell: return nil
        }
    }

    /// Asset-catalog brand mark, or nil for `.shell` (which uses an SF Symbol).
    var brandAsset: String? {
        switch self {
        case .claude: return "Claude"
        case .codex: return "CodexMark"
        case .opencode: return "OpenCodeMark"
        case .devin: return "DevinMark"
        case .shell: return nil
        }
    }
}

/// Which "new terminal" action the agent chooser is gating, so the overlay can
/// label itself and run the right thing once an agent is picked.
enum NewTerminalIntent {
    case tab, splitRight, splitDown, workspace
}
