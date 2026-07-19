import XCTest
@testable import Glint

final class WebRemoteProtocolTests: XCTestCase {
    func testTerminalSizeAcceptsBrowserGridWithinSafeBounds() {
        XCTAssertEqual(
            WebRemoteTerminalSize.parse(["columns": 132, "rows": 43]),
            WebRemoteTerminalSize(columns: 132, rows: 43)
        )
    }

    func testTerminalSizeRejectsMissingFractionalAndExtremeValues() {
        XCTAssertNil(WebRemoteTerminalSize.parse(["columns": 132]))
        XCTAssertNil(WebRemoteTerminalSize.parse(["columns": 132.5, "rows": 43]))
        XCTAssertNil(WebRemoteTerminalSize.parse(["columns": 19, "rows": 43]))
        XCTAssertNil(WebRemoteTerminalSize.parse(["columns": 132, "rows": 201]))
    }

    func testSnapshotUsesTerminalNewlinesBetweenLogicalRows() {
        let payload = String(
            decoding: WebRemoteSnapshotPayload.make(ansi: "first\nsecond"),
            as: UTF8.self
        )

        XCTAssertTrue(payload.hasSuffix("first\r\nsecond"))
    }

    func testSnapshotRestoresGhosttyTerminalStateAfterPaintingGrid() throws {
        let json = Data(#"""
        {
          "columns": 80,
          "rows": 24,
          "cursor": {"row": 5, "column": 7, "visible": false, "style": "bar", "blinking": true},
          "styles": [{
            "id": 0,
            "foreground": "#FFFFFF",
            "background": "#000000",
            "bold": false,
            "faint": false,
            "italic": false,
            "underline": false,
            "blink": false,
            "inverse": false,
            "invisible": false,
            "strikethrough": false,
            "overline": false
          }],
          "row_spans": [{"row": 0, "column": 0, "style_id": 0, "cell_width": 1, "text": "X"}],
          "row_wraps": [false],
          "active_screen": "alternate",
          "modes": [
            {"code": 1, "ansi": false, "on": true},
            {"code": 6, "ansi": false, "on": true},
            {"code": 2004, "ansi": false, "on": true}
          ],
          "scrolling_region": {"top": 2, "bottom": 20, "left": 3, "right": 70},
          "pty_output_seq": 41,
          "pty_stream_safe": true,
          "scrollback_rows": 0,
          "scrollback_row_wraps": [],
          "scrollback_spans": []
        }
        """#.utf8)

        let snapshot = try XCTUnwrap(
            GhosttySurfaceView.webRemoteSnapshot(fromRenderGrid: json, maxLines: 1000)
        )
        XCTAssertEqual(snapshot.outputSequence, 41)
        let text = String(decoding: snapshot.payload, as: UTF8.self)
        let paint = try XCTUnwrap(text.range(of: "X")?.lowerBound)
        let alternate = try XCTUnwrap(text.range(of: "\u{1b}[?1049h")?.lowerBound)
        let applicationCursor = try XCTUnwrap(text.range(of: "\u{1b}[?1h")?.lowerBound)
        let bracketedPaste = try XCTUnwrap(text.range(of: "\u{1b}[?2004h")?.lowerBound)
        let scrollingRegion = try XCTUnwrap(text.range(of: "\u{1b}[3;21r")?.lowerBound)
        let horizontalMargins = try XCTUnwrap(text.range(of: "\u{1b}[4;71s")?.lowerBound)
        let cursor = try XCTUnwrap(text.range(of: "\u{1b}[4;5H")?.lowerBound)

        XCTAssertLessThan(alternate, paint)
        XCTAssertLessThan(paint, applicationCursor)
        XCTAssertLessThan(applicationCursor, bracketedPaste)
        XCTAssertLessThan(bracketedPaste, scrollingRegion)
        XCTAssertLessThan(scrollingRegion, horizontalMargins)
        XCTAssertLessThan(horizontalMargins, cursor)
        XCTAssertTrue(text.hasSuffix("\u{1b}[5 q\u{1b}[?25l"))
    }

    func testSnapshotRejectsUnsafePTYParserBoundary() {
        let json = Data(#"""
        {
          "styles": [],
          "row_spans": [],
          "scrollback_spans": [],
          "scrollback_rows": 0,
          "rows": 24,
          "pty_output_seq": 41,
          "pty_stream_safe": false
        }
        """#.utf8)

        XCTAssertNil(GhosttySurfaceView.webRemoteSnapshot(fromRenderGrid: json, maxLines: 1000))
    }

    func testTerminalOutputBufferCoalescesBytesAndRejectsOverflow() {
        var buffer = WebRemoteOutputBuffer(byteLimit: 4)

        XCTAssertTrue(buffer.append(Data("ab".utf8), sequence: 1))
        XCTAssertTrue(buffer.append(Data("cd".utf8), sequence: 2))
        XCTAssertFalse(buffer.append(Data("e".utf8), sequence: 3))
        XCTAssertEqual(buffer.take(after: 0), Data("abcd".utf8))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testTerminalOutputBufferDropsChunksAlreadyIncludedInSnapshot() {
        var buffer = WebRemoteOutputBuffer(byteLimit: 32)

        XCTAssertTrue(buffer.append(Data("before".utf8), sequence: 40))
        XCTAssertTrue(buffer.append(Data("included".utf8), sequence: 41))
        XCTAssertTrue(buffer.append(Data("after".utf8), sequence: 42))

        XCTAssertEqual(buffer.take(after: 41), Data("after".utf8))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testTerminalOutputBufferPreservesSequenceBoundariesWhenCoalescingBatches() {
        var ingress = WebRemoteOutputBuffer(byteLimit: 32)
        XCTAssertTrue(ingress.append(Data("included".utf8), sequence: 41))
        XCTAssertTrue(ingress.append(Data("after".utf8), sequence: 42))

        var pendingSelection = WebRemoteOutputBuffer(byteLimit: 32)
        XCTAssertTrue(pendingSelection.append(contentsOf: ingress))

        XCTAssertEqual(pendingSelection.take(after: 41), Data("after".utf8))
    }

    func testOutboundBufferKeepsSnapshotBeforeBufferedTerminalOutput() {
        let snapshot = Data("snapshot".utf8)
        var buffer = WebRemoteOutboundBuffer(maxQueuedOutputBytes: 4)

        buffer.enqueueMessage(snapshot)
        XCTAssertTrue(buffer.enqueueTerminalOutput(Data("ab".utf8), pane: "pane-1"))
        XCTAssertTrue(buffer.enqueueTerminalOutput(Data("cd".utf8), pane: "pane-1"))
        XCTAssertFalse(buffer.enqueueTerminalOutput(Data("e".utf8), pane: "pane-1"))

        guard case let .message(message)? = buffer.next() else {
            return XCTFail("Snapshot message must be sent first")
        }
        XCTAssertEqual(message, snapshot)
        guard case let .terminalOutput(pane, output)? = buffer.next() else {
            return XCTFail("Buffered terminal output must follow the snapshot")
        }
        XCTAssertEqual(pane, "pane-1")
        XCTAssertEqual(output, Data("abcd".utf8))
        XCTAssertNil(buffer.next())
    }

    func testAccessTokenIsRandomHexAndConstantTimeMatcherChecksWholeValue() {
        let token = WebRemoteAccessToken.generate()

        XCTAssertEqual(token.count, 64)
        XCTAssertNotNil(UInt64(token.prefix(16), radix: 16))
        XCTAssertTrue(WebRemoteAccessToken.matches(token, expected: token))
        XCTAssertFalse(WebRemoteAccessToken.matches(nil, expected: token))
        XCTAssertFalse(WebRemoteAccessToken.matches(token + "0", expected: token))
        XCTAssertFalse(WebRemoteAccessToken.matches(String(token.dropLast()) + "0", expected: token))
    }

    func testAccessKeyPersistsUntilExplicitReset() {
        let suite = "WebRemoteAccessKeyStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = WebRemoteAccessKeyStore.loadOrCreate(defaults: defaults)
        XCTAssertEqual(WebRemoteAccessKeyStore.loadOrCreate(defaults: defaults), first)

        let reset = WebRemoteAccessKeyStore.reset(defaults: defaults)
        XCTAssertNotEqual(reset, first)
        XCTAssertEqual(WebRemoteAccessKeyStore.loadOrCreate(defaults: defaults), reset)
    }

    func testAccessKeyCanBeCopiedSeparatelyFromSessionURL() {
        let value = "http://192.168.1.20:43871/#token=abc123"

        XCTAssertEqual(WebRemoteAccessURL.token(from: value), "abc123")
        XCTAssertNil(WebRemoteAccessURL.token(from: "http://192.168.1.20:43871/"))
    }

    func testHTTPRequestParsesGetAndStripsQuery() {
        let data = Data("GET /app.js?v=1 HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)

        XCTAssertEqual(
            WebRemoteHTTPRequest.parse(data),
            WebRemoteHTTPRequest(method: .get, path: "/app.js")
        )
    }

    func testHTTPRequestRejectsUnsupportedMethodAndMalformedTarget() {
        XCTAssertNil(WebRemoteHTTPRequest.parse(Data("POST / HTTP/1.1\r\n\r\n".utf8)))
        XCTAssertNil(WebRemoteHTTPRequest.parse(Data("GET relative HTTP/1.1\r\n\r\n".utf8)))
        XCTAssertNil(WebRemoteHTTPRequest.parse(Data("not-http".utf8)))
    }

    func testAssetsOnlyExposeBundledAllowlist() {
        XCTAssertEqual(WebRemoteAssets.asset(for: "/")?.resource, "web-remote-index")
        XCTAssertEqual(WebRemoteAssets.asset(for: "/xterm.mjs")?.contentType, "text/javascript; charset=utf-8")
        XCTAssertEqual(WebRemoteAssets.asset(for: "/symbols-nerd-font-mono.ttf")?.contentType, "font/ttf")
        XCTAssertNil(WebRemoteAssets.asset(for: "/../state.json"))
        XCTAssertNil(WebRemoteAssets.asset(for: "/favicon.ico"))
    }

    func testHeadResponseKeepsContentLengthWithoutBody() {
        let body = Data("hello".utf8)
        let response = WebRemoteHTTPResponse.make(
            status: 200,
            reason: "OK",
            contentType: "text/plain",
            body: body,
            includeBody: false
        )
        let text = String(decoding: response, as: UTF8.self)

        XCTAssertTrue(text.contains("Content-Length: 5\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n"))
        XCTAssertFalse(text.hasSuffix("hello"))
    }

    func testProjectPathOnlyAcceptsExistingDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glint-web-remote-tests-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("file.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(WebRemoteProjectPath.resolveExistingDirectory(root.path), root.path)
        XCTAssertNil(WebRemoteProjectPath.resolveExistingDirectory(file.path))
        XCTAssertNil(WebRemoteProjectPath.resolveExistingDirectory(root.appendingPathComponent("missing").path))
        XCTAssertNil(WebRemoteProjectPath.resolveExistingDirectory("relative/path"))
    }

    @MainActor
    func testRemoteCloseTargetsRequestedPaneAndRequiresConfirmationForBusyProcess() {
        let workspaceID = UUID()
        let closingPane = PaneID(value: 0)
        let survivingPane = PaneID(value: 1)
        let tab = WorkspaceTab(
            id: TabID(value: 0),
            name: nil,
            root: .split(
                direction: .horizontal,
                ratio: 0.5,
                a: .leaf(closingPane),
                b: .leaf(survivingPane)
            ),
            focusedPane: survivingPane
        )
        let workspace = Workspace(
            id: workspaceID,
            name: "Remote Close",
            userNamed: true,
            accentHex: "5E5CE6",
            symbol: "R",
            tabs: [tab],
            selectedTabID: tab.id,
            nextTabSeq: 1,
            panes: [
                closingPane: Pane(id: closingPane, title: "vim"),
                survivingPane: Pane(id: survivingPane, title: "zsh"),
            ],
            nextPaneSeq: 2
        )
        let store = WorkspaceStore(activity: PaneActivityStore())
        store.workspaces = [workspace]
        store.selectedWorkspaceID = workspaceID
        store.paneProcesses[
            WorkspaceStore.WorkspacePaneKey(workspace: workspaceID, pane: closingPane)
        ] = "vim"
        let handle = "\(workspaceID.uuidString):\(closingPane.value)"

        XCTAssertEqual(
            store.webRemoteCloseTerminal(pane: handle, confirmed: false),
            .confirmationRequired
        )
        XCTAssertNotNil(store.workspaces[0].panes[closingPane])

        XCTAssertEqual(
            store.webRemoteCloseTerminal(pane: handle, confirmed: true),
            .success
        )
        XCTAssertNil(store.workspaces[0].panes[closingPane])
        XCTAssertNotNil(store.workspaces[0].panes[survivingPane])
        XCTAssertEqual(store.workspaces[0].tabs[0].root.leaves, [survivingPane])
        XCTAssertEqual(store.workspaces[0].tabs[0].focusedPane, survivingPane)
    }

    @MainActor
    func testRemoteCloseRejectsWorkspaceLastTerminal() {
        let workspace = Workspace.fresh(name: "Only", accentHex: "5E5CE6", symbol: "O")
        let pane = try! XCTUnwrap(workspace.selectedTab?.focusedPane)
        let store = WorkspaceStore(activity: PaneActivityStore())
        store.workspaces = [workspace]
        store.selectedWorkspaceID = workspace.id

        XCTAssertEqual(
            store.webRemoteCloseTerminal(
                pane: "\(workspace.id.uuidString):\(pane.value)",
                confirmed: true
            ),
            .failure("last-terminal")
        )
        XCTAssertNotNil(store.workspaces[0].panes[pane])
    }
}
