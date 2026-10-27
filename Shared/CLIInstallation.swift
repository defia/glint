import Foundation

enum CLIInstallation {
    enum State { case notInstalled, installed, repairable, conflict }

    static func state(executable: URL, directory: URL) -> State {
        let fm = FileManager.default
        let destination = directory.appendingPathComponent("glint")
        if let existing = try? fm.destinationOfSymbolicLink(atPath: destination.path) {
            let target = URL(fileURLWithPath: existing, relativeTo: directory)
                .standardizedFileURL.resolvingSymlinksInPath()
            if target == executable.standardizedFileURL.resolvingSymlinksInPath() { return .installed }
            // Recognize only Glint's helper layout; foreign dangling links stay protected.
            return target.path.hasSuffix("/Glint.app/Contents/Helpers/glint") ? .repairable : .conflict
        }
        return fm.fileExists(atPath: destination.path) ? .conflict : .notInstalled
    }

    static func install(executable: URL, directory: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: executable.path) else {
            throw NSError(domain: "GlintCLI", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "The bundled CLI is missing. Reinstall Glint.")])
        }
        switch state(executable: executable, directory: directory) {
        case .installed:
            throw NSError(domain: "GlintCLI", code: 3, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "CLI is already installed.")])
        case .conflict: throw occupiedPathError()
        case .notInstalled: break
        case .repairable:
            try fm.removeItem(at: directory.appendingPathComponent("glint"))
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("glint")
        try fm.createSymbolicLink(at: destination, withDestinationURL: executable)
        return destination
    }

    static func uninstall(executable: URL, directory: URL) throws {
        switch state(executable: executable, directory: directory) {
        case .installed, .repairable:
            // Remove only the verified link, never the executable or another tool.
            try FileManager.default.removeItem(at: directory.appendingPathComponent("glint"))
        case .conflict: throw occupiedPathError()
        case .notInstalled:
            throw NSError(domain: "GlintCLI", code: 4, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "CLI is not installed.")])
        }
    }

    private static func occupiedPathError() -> NSError {
        NSError(domain: "GlintCLI", code: 2, userInfo: [NSLocalizedDescriptionKey:
            String(localized: "The destination already contains another command. It was left unchanged.")])
    }
}
