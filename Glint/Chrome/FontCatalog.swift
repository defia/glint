import AppKit
import CoreText
import SwiftUI

/// 终端字体选项的来源。
///
/// 设计要点:
///
/// - `recommended*` 是手工维护的常用列表(放在下拉顶部,一眼能选),但
///   只展示**系统真的装了**的项 —— 老版本会无差别列出 Fira Code / JetBrains
///   Mono,机器上没装时用户选了也只是被 ghostty 静默回落到 Menlo,UI 上看
///   不出来。`installedRecommended*` 在 cache 构建期就过滤掉没装的。
///
/// - 系统字体枚举只跑一次,结果缓存到 `cache`。锁保护下一次性算出所有派生
///   集合(全量家族、等宽家族、已安装的推荐子集、剔除推荐后的全量,以及
///   各自的 lowercased Set),避免一边读一边算导致重入。
///
/// - 用户中途装/删字体由 `kCTFontManagerRegisteredFontsChangedNotification`
///   触发 `invalidateCache()`,下次访问按需重建。AppDelegate 启动期还会
///   `warmCache()` 在后台线程预热,避免首次打开 Settings ▸ Terminal 时
///   主线程被 200+ 次 `availableMembers(ofFontFamily:)` 卡住。
///
/// - "Current" 伪分段:绑定值不在任何列表里时(老用户手写 UserDefaults
///   的稀有字体)在最前补一行让它仍能显示成已选状态。匹配做大小写不敏感,
///   避免 "sf mono" 与 "SF Mono" 同时出现。
enum FontCatalog {
    typealias Item = (value: String, label: String)
    typealias Section = (header: LocalizedStringKey, items: [Item])

    static let recommendedMono: [String] = [
        "SF Mono", "Menlo", "Monaco", "Courier New",
        "JetBrains Mono", "Fira Code", "IBM Plex Mono",
    ]

    static let recommendedCJK: [String] = [
        "PingFang SC", "PingFang TC", "PingFang HK",
        "Hiragino Sans GB", "Heiti SC", "Songti SC", "STSong",
        "Source Han Sans CN", "Source Han Serif CN",
        "Noto Sans CJK SC", "Noto Serif CJK SC",
    ]

    // MARK: - Public accessors

    /// 推荐列表里**确实已安装**的项。未安装的不展示(避免「选了实际没生效」)。
    static var installedRecommendedMono: [String] { data.installedRecMono }
    static var installedRecommendedCJK: [String] { data.installedRecCJK }

    /// 全量等宽家族里去掉推荐过的(避免重复),用于「所有等宽字体」分段。
    static var systemMonoFamilies: [String] { data.systemMonoOnly }
    /// 全量家族里去掉推荐 CJK 的,用于 CJK 兜底的「所有系统字体」分段。
    static var systemAllFamilies: [String] { data.systemAllOnly }

    /// 字体集合变化时调用(系统通知或显式刷新)。下次访问按需重建。
    static func invalidateCache() {
        cacheLock.withLock { cache = nil }
    }

    /// 启动期后台预热,推动 cache 在主线程访问前就绪。
    static func warmCache() { _ = data }

    // MARK: - Section builders

    /// 主字体三段:Current(可选)→ Recommended(已安装)→ All installed monospaced。
    static func mainFontSections(currentSelection: String) -> [Section] {
        var sections: [Section] = []
        if let cur = currentSection(currentSelection, known: data.monoFamiliesLowered) {
            sections.append(cur)
        }
        sections.append((header: "Recommended", items: data.installedRecMono.map { ($0, $0) }))
        if !data.systemMonoOnly.isEmpty {
            sections.append((header: "All installed monospaced",
                             items: data.systemMonoOnly.map { ($0, $0) }))
        }
        return sections
    }

    /// CJK 兜底四段:System default(空)→ Current(可选)→ Recommended(已安装)→
    /// All installed fonts。CJK 多数非等宽,所以「所有系统字体」不做 fixedPitch 过滤。
    static func cjkFontSections(currentSelection: String) -> [Section] {
        var sections: [Section] = [
            (header: "Default", items: [(value: "", label: "System default")])
        ]
        if let cur = currentSection(currentSelection, known: data.allFamiliesLowered) {
            sections.append(cur)
        }
        sections.append((header: "Recommended", items: data.installedRecCJK.map { ($0, $0) }))
        if !data.systemAllOnly.isEmpty {
            sections.append((header: "All installed fonts",
                             items: data.systemAllOnly.map { ($0, $0) }))
        }
        return sections
    }

    /// 「当前值」伪分段的统一构造。绑定值若是空白 / 已被任一已知集合命中(大
    /// 小写不敏感),就不需要 Current 行。trim 在两条路径上一致 —— 主字体路径
    /// 之前漏 trim,会让 " SF Mono " 这种 UserDefaults 残留同时触发 Recommended
    /// 行(干净的 "SF Mono")和 Current 行(带空格的拷贝),下拉里同一字体出现
    /// 两次、选中态对不上。
    private static func currentSection(_ raw: String, known: Set<String>) -> Section? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !known.contains(trimmed.lowercased()) else { return nil }
        return (header: "Current", items: [(value: trimmed, label: trimmed)])
    }

    // MARK: - Cache

    private struct CacheData {
        let installedRecMono: [String]
        let installedRecCJK: [String]
        let systemMonoOnly: [String]
        let systemAllOnly: [String]
        /// 等宽家族的小写集合(含推荐与非推荐),用于 mainFontSections 的「未知」判定。
        let monoFamiliesLowered: Set<String>
        /// 所有家族的小写集合,用于 cjkFontSections 的「未知」判定。
        let allFamiliesLowered: Set<String>
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: CacheData?

    /// Double-checked:**build 跑在锁外**,以免 warmCache 后台线程持锁 200+ 次
    /// `availableMembers(ofFontFamily:)` 时,用户打开 Settings ▸ Terminal 让
    /// 主线程在 `cacheLock.lock()` 上一直阻塞 —— warm 的本意正是避免这个,
    /// 旧版本把 build 包在锁里等于 warm 没生效。
    /// 代价是并发首次访问时可能各自算一遍(few×100ms),但只发生在 cache 空
    /// 的瞬间,且结果一致,最后一次 set 胜出。
    private static var data: CacheData {
        if let snapshot = cacheLock.withLock({ cache }) {
            return snapshot
        }
        let built = Self.build()
        cacheLock.withLock {
            if cache == nil { cache = built }
        }
        return cacheLock.withLock { cache! }
    }

    private static func build() -> CacheData {
        let fm = NSFontManager.shared
        let allFamilies = fm.availableFontFamilies
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let mask = NSFontTraitMask.fixedPitchFontMask.rawValue
        let monoFamilies = allFamilies.filter { family in
            guard let members = fm.availableMembers(ofFontFamily: family) else { return false }
            return members.contains { member in
                guard member.count >= 4, let traits = member[3] as? NSNumber else { return false }
                return traits.uintValue & mask != 0
            }
        }
        let monoLowered = Set(monoFamilies.map { $0.lowercased() })
        let allLowered = Set(allFamilies.map { $0.lowercased() })
        let recMonoLowered = Set(recommendedMono.map { $0.lowercased() })
        let recCJKLowered = Set(recommendedCJK.map { $0.lowercased() })

        // 「已安装的推荐」:推荐里**实际能解析**出字体的家族。
        // 用 `NSFont(name:size:)` 当探针,**比 enumeration 更宽松**:
        // Apple 自家的 SF Mono / Menlo 等系统字体长期不被
        // `NSFontManager.availableFontFamilies` 列出,但 `NSFont(name:)` 能
        // 拿到 —— 之前用 enumeration 过滤会把 SF Mono 从推荐里抹掉,然后
        // 又被「未知值」分支当 Current 显示,看起来像 bug。
        let installedRecMono = recommendedMono.filter { isFamilyInstalled($0, allLowered: allLowered) }
        let installedRecCJK = recommendedCJK.filter { isFamilyInstalled($0, allLowered: allLowered) }

        // 全量列表里去掉推荐(对应分段已显示),保持下拉无重复。
        let systemMonoOnly = monoFamilies.filter { !recMonoLowered.contains($0.lowercased()) }
        let systemAllOnly = allFamilies.filter { !recCJKLowered.contains($0.lowercased()) }

        // 「已知」集合 = enumeration ∪ probe-found recommended。后者补 SF Mono
        // 这类系统字体,避免 Current 分段在它们身上误触发。
        let probedRecMonoLowered = Set(installedRecMono.map { $0.lowercased() })
        let probedRecCJKLowered = Set(installedRecCJK.map { $0.lowercased() })
        let monoKnownLowered = monoLowered.union(probedRecMonoLowered)
        let allKnownLowered = allLowered.union(probedRecMonoLowered).union(probedRecCJKLowered)

        return CacheData(installedRecMono: installedRecMono,
                         installedRecCJK: installedRecCJK,
                         systemMonoOnly: systemMonoOnly,
                         systemAllOnly: systemAllOnly,
                         monoFamiliesLowered: monoKnownLowered,
                         allFamiliesLowered: allKnownLowered)
    }

    /// 字体家族是否已安装。优先看 `availableFontFamilies` 枚举;漏掉的(SF Mono
    /// 等 Apple 系统字体)再用 `NSFont(name:size:)` 探一下 —— 后者对系统字体
    /// 更可靠。`allLowered` 由调用方传入,避免重复构 Set。
    private static func isFamilyInstalled(_ family: String, allLowered: Set<String>) -> Bool {
        if allLowered.contains(family.lowercased()) { return true }
        return NSFont(name: family, size: 12) != nil
    }
}
