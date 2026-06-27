import Foundation
import Combine

struct CodexHome: Codable, Identifiable, Hashable {
    var id: UUID
    var label: String?
    var path: String
    var isEnabled: Bool

    init(id: UUID = UUID(), label: String? = nil, path: String, isEnabled: Bool = true) {
        self.id = id
        self.label = label
        self.path = path
        self.isEnabled = isEnabled
    }

    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static var `default`: CodexHome {
        CodexHome(id: defaultID, label: "Default", path: "~/.codex")
    }

    var resolvedURL: URL {
        URL(
            fileURLWithPath: (path as NSString).expandingTildeInPath,
            isDirectory: true
        ).standardizedFileURL
    }
}

enum CodexHookStatus: Hashable {
    case installed
    case notInstalled
    case error(String)
}

enum CodexAuthStatus: Hashable {
    case found
    case missing
    case invalid(String)
}

enum CodexQuotaStatus: Hashable {
    case available(AgentQuota)
    case unavailable(String)
    case loading

    static func placeholder(isHomeEnabled: Bool, isUsageEnabled: Bool) -> CodexQuotaStatus {
        if !isHomeEnabled { return .unavailable(String(localized: "Disabled")) }
        return isUsageEnabled ? .loading : .unavailable(String(localized: "Usage off"))
    }
}

struct CodexHomeStatus: Identifiable, Hashable {
    var id: UUID { home.id }
    var home: CodexHome
    var resolvedURL: URL
    var hookStatus: CodexHookStatus
    var authStatus: CodexAuthStatus
    var quotaStatus: CodexQuotaStatus
}

enum CodexHomeAddResult: Equatable {
    case added
    case emptyPath
    case relativePath
    case duplicate
}

@MainActor
final class CodexHomeStore: ObservableObject {
    @Published private(set) var homes: [CodexHome]

    nonisolated static let storageKey = "glint.codexHomes"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homes = Self.configuredHomes(defaults: defaults)
    }

    /// Read the configured Codex homes straight from `defaults`: decode,
    /// dedupe by resolved URL, fall back to `[.default]`. The single source
    /// of this read shape — `init`, `UsageStore`, and `AgentHookInstaller`
    /// all go through here so the three can't drift (one applying a
    /// normalization the others miss). `nonisolated`: touches only `defaults`
    /// and a pure decode.
    nonisolated static func configuredHomes(defaults: UserDefaults = .standard) -> [CodexHome] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CodexHome].self, from: data),
              !decoded.isEmpty else { return [.default] }
        return Self.deduplicated(decoded)
    }

    var enabledHomes: [CodexHome] {
        homes.filter(\.isEnabled)
    }

    func add(path: String, label: String? = nil) -> CodexHomeAddResult {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyPath }
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") else { return .relativePath }
        let home = CodexHome(label: label?.nilIfBlank, path: trimmed)
        guard !contains(resolvedURL: home.resolvedURL) else { return .duplicate }
        homes.append(home)
        save()
        return .added
    }

    func update(_ home: CodexHome) -> Bool {
        guard let index = homes.firstIndex(where: { $0.id == home.id }) else { return false }
        guard !homes.enumerated().contains(where: { offset, existing in
            offset != index && existing.resolvedURL == home.resolvedURL
        }) else { return false }
        homes[index] = home
        save()
        return true
    }

    func setEnabled(_ isEnabled: Bool, for id: UUID) {
        guard let index = homes.firstIndex(where: { $0.id == id }),
              homes[index].isEnabled != isEnabled else { return }
        homes[index].isEnabled = isEnabled
        save()
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        guard let home = homes.first(where: { $0.id == id }),
              home.resolvedURL != CodexHome.default.resolvedURL else { return false }
        homes.removeAll { $0.id == id }
        save()
        return true
    }

    func isDefault(_ home: CodexHome) -> Bool {
        home.resolvedURL == CodexHome.default.resolvedURL
    }

    private func contains(resolvedURL: URL) -> Bool {
        homes.contains { $0.resolvedURL == resolvedURL }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(homes) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    nonisolated private static func deduplicated(_ homes: [CodexHome]) -> [CodexHome] {
        var seen = Set<URL>()
        return homes.filter { seen.insert($0.resolvedURL).inserted }
    }
}

@MainActor
enum CodexHomeRemoval {
    /// Removing Glint's configuration must not depend on an external
    /// `hooks.json` being readable. Return the cleanup error for UI reporting,
    /// but always remove the non-default home from the store.
    static func remove(
        _ home: CodexHome,
        from store: CodexHomeStore,
        cleanup: (URL) throws -> Void
    ) -> String? {
        var cleanupError: String?
        do {
            try cleanup(home.resolvedURL)
        } catch {
            cleanupError = error.localizedDescription
        }
        _ = store.remove(id: home.id)
        return cleanupError
    }
}

extension String {
    /// Trim 首尾空白后,空串返回 nil,否则返回 trimmed 值。给「这条路径下空字符
    /// 串和缺省语义等价」的字段做集中规范化(CodexHome label、ghostty 字体
    /// fallback 等)。
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
