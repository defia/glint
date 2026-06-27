import XCTest
@testable import Glint

/// Tests for the root-vs-current-directory scoping logic behind
/// `reviewAtRepoRoot` / `revealAtRepoRoot`. `subdirPath` is the one piece of
/// real logic (normalization + prefix drop); `paneSubdir` wires it to the
/// focused pane's cwd. The Review/Reveal methods themselves depend on a live
/// GitService + surfaces, so they're covered manually instead — these tests
/// lock the path math that decides what "current directory" means.
final class ReviewScopeTests: XCTestCase {

    private func makeTmpDir(_ leaf: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-review-scope-\(leaf)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: subdirPath

    func testSubdirPathOneLevel() throws {
        let root = try makeTmpDir("root")
        let src = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        XCTAssertEqual(WorkspaceStore.subdirPath(root: root.path, cwd: src.path), "src")
    }

    func testSubdirPathNested() throws {
        let root = try makeTmpDir("root")
        let nested = root.appendingPathComponent("src/main/resources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertEqual(WorkspaceStore.subdirPath(root: root.path, cwd: nested.path),
                       "src/main/resources")
    }

    func testSubdirPathCwdIsRootReturnsNil() throws {
        let root = try makeTmpDir("root")
        // cwd exactly the root → whole repo, no subdir filter.
        XCTAssertNil(WorkspaceStore.subdirPath(root: root.path, cwd: root.path))
    }

    func testSubdirPathCwdOutsideRootReturnsNil() throws {
        let root = try makeTmpDir("root")
        let elsewhere = try makeTmpDir("other")
        // A cwd that isn't under the repo (e.g. the pane cd'd into another
        // project) must not produce a filter — fall back to whole repo.
        XCTAssertNil(WorkspaceStore.subdirPath(root: root.path, cwd: elsewhere.path))
    }

    func testSubdirPathResolvesSymlinkedRootAndCwd() throws {
        // macOS symlinks /tmp → /private/tmp. A root expressed via /private/tmp
        // and a cwd via /tmp (the same physical dir) must still match after
        // resolvingSymlinksInPath — this is the exact mismatch shape that a
        // pane cwd (shell-reported, often /tmp/…) vs a git toplevel
        // (--show-toplevel, /private/tmp/…) would hit.
        let name = "glint-symlink-\(UUID().uuidString)"
        let rootViaPrivate = "/private/tmp/\(name)"
        let cwdViaTmp = "/tmp/\(name)/src"
        try FileManager.default.createDirectory(
            atPath: rootViaPrivate + "/src", withIntermediateDirectories: true)
        XCTAssertEqual(WorkspaceStore.subdirPath(root: rootViaPrivate, cwd: cwdViaTmp), "src")
    }

    func testSubdirPathStandardizesDotDot() throws {
        let root = try makeTmpDir("root")
        let src = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        // A cwd with a redundant ".." segment still collapses to the same
        // normalized path, so the prefix drop is stable.
        let cwdWithDot = root.appendingPathComponent("src/../src").path
        XCTAssertEqual(WorkspaceStore.subdirPath(root: root.path, cwd: cwdWithDot), "src")
    }

    // MARK: paneSubdir

    func testPaneSubdirReturnsFocusedPaneCwdRelativeToRoot() throws {
        let root = try makeTmpDir("root")
        let src = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        var ws = Workspace.fresh(name: "T", accentHex: "5E5CE6", symbol: "•")
        ws.panes[PaneID(value: 0)]?.workingDirectory = src.path
        XCTAssertEqual(WorkspaceStore.paneSubdir(for: ws, root: root.path), "src")
    }

    func testPaneSubdirNilWhenNoCwd() {
        // A pane that hasn't reported a cwd yet (just launched, no OSC 7) →
        // no subdir → Review falls back to the whole root.
        var ws = Workspace.fresh(name: "T", accentHex: "5E5CE6", symbol: "•")
        ws.panes[PaneID(value: 0)]?.workingDirectory = nil
        XCTAssertNil(WorkspaceStore.paneSubdir(for: ws, root: "/tmp/anything"))
    }

    func testPaneSubdirNilWhenCwdIsRoot() throws {
        let root = try makeTmpDir("root")
        var ws = Workspace.fresh(name: "T", accentHex: "5E5CE6", symbol: "•")
        ws.panes[PaneID(value: 0)]?.workingDirectory = root.path
        XCTAssertNil(WorkspaceStore.paneSubdir(for: ws, root: root.path))
    }

    func testPaneSubdirNilWhenCwdOutsideRoot() throws {
        let root = try makeTmpDir("root")
        let elsewhere = try makeTmpDir("other")
        var ws = Workspace.fresh(name: "T", accentHex: "5E5CE6", symbol: "•")
        ws.panes[PaneID(value: 0)]?.workingDirectory = elsewhere.path
        XCTAssertNil(WorkspaceStore.paneSubdir(for: ws, root: root.path))
    }
}
