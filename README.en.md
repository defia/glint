# Glint

English · [中文](README.md)

A polished macOS terminal made for AI agents. SwiftUI + AppKit, with [Ghostty](https://ghostty.org) under the hood.

![Glint screenshot](docs/screenshot.png)

![Workspace state overview](docs/screenshot-sidebar.png)

## Install

### Homebrew (recommended)

```bash
brew tap chenbstack/glint
brew install --cask glint
```

### Manual download

Grab the latest `Glint-x.y.z.dmg` from the [Releases](https://github.com/chenbstack/glint/releases) page, mount it, and drag `Glint.app` into `/Applications`.

If macOS refuses to open it with "developer cannot be verified", run once:

```bash
xattr -dr com.apple.quarantine /Applications/Glint.app
```

The Homebrew Cask does this automatically.

## External control CLI

In Settings → Terminal → External control, **Install CLI** creates `~/.local/bin/glint`. Add `~/.local/bin` to `PATH` if needed. The native CLI ships with Glint and requires no Node.js, Python, or MCP. **Copy Agent instructions** includes the full executable path and works without installing the link.

Settings shows the installed state and disables repeat installation. Use **Uninstall** or `glint uninstall` to remove its command link. Uninstalling preserves the bundled CLI and the control preference.

Installing the CLI does not grant control. **Allow external control** must be enabled for reads, input, and focus. Turning it off revokes access immediately; old connections and tokens remain invalid after re-enabling it. The CLI never launches Glint or enables control automatically.

```sh
glint --help
glint panes list
glint pane read '<pane-id>' --scrollback --max-lines 1000
glint pane send '<pane-id>' --text 'pwd' --enter
glint pane key '<pane-id>' down enter
```

Use the full pane handle from the list. Reads and input preserve local workspace selection; only explicit `glint pane focus '<pane-id>'` switches focus. Reads return plain text unless `--json` is supplied; other commands return JSON. Use `glint --debug …` for a development build. You can also run `/Applications/Glint.app/Contents/Helpers/glint` directly, or use its `install` subcommand to install the link.

## Upgrade & uninstall

```bash
brew upgrade --cask glint
brew uninstall --cask glint
```

## License

MIT — see [LICENSE](LICENSE).
