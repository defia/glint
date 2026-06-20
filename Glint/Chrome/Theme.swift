import SwiftUI
import AppKit

enum Theme {
    // chrome 中性色现在从「当前主题」取(见 docs/theme-system-design.md §3.1)。
    // 值由 ThemeProvider.current 提供;glint-dark 用 override 1:1 锁定下面注释里的
    // 原始色值,故接入后视觉零变化。注:computed 不被 SwiftUI 自动 observe,主题切换
    // 时由 WorkspaceStore.themeRevision 触发整树重建来刷新(第 3 步接)。
    static var current: GlintTheme { ThemeProvider.shared.current }

    // backgrounds
    static var bgWindow: Color { current.bgWindow }   // 原 #0A0B10
    static var bgPane:   Color { current.bgPane }     // 原 #0B0A14 (slight indigo)

    // vibrancy tint overlays — black-first with the faintest indigo cast
    static var sidebarTintTop:    Color { current.sidebarTintTop }     // 原 (.075,.065,.110)@.86
    static var sidebarTintBottom: Color { current.sidebarTintBottom } // 原 (.045,.038,.085)@.90
    static var toolbarTint:       Color { current.toolbarTint }       // 原 (.060,.052,.095)@.86

    // Liquid Glass tint (macOS 26): the sidebar indigo, but thin enough that
    // the glass still refracts the terminal behind it instead of reading as
    // a painted slab.
    static var glassTint:         Color { current.glassTint }         // 原 (.075,.065,.110)@.50

    // text
    static var text1: Color { current.text1 }   // 原 #ECEDF2
    static var text2: Color { current.text2 }   // 原 #B7B9C8
    static var text3: Color { current.text3 }   // 原 #7E8290
    // text4 用于 10–11pt caption;#757A91 在 bgPane 上测得 ~4.6:1,过 WCAG AA。
    static var text4: Color { current.text4 }   // 原 #757A91

    // accents
    static let accent       = Color(red: 0.369, green: 0.361, blue: 0.902) // #5E5CE6 systemIndigo
    static let accentBright = Color(red: 0.549, green: 0.549, blue: 1.000) // #8C8CFF
    static let green        = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
    static let orange       = Color(red: 1.000, green: 0.624, blue: 0.039) // #FF9F0A
    static let pink         = Color(red: 1.000, green: 0.392, blue: 0.510) // #FF6482
    static let cyan         = Color(red: 0.392, green: 0.824, blue: 1.000) // #64D2FF

    // separators
    static var divider: Color { current.divider }   // 原 white@.045
    static var border:  Color { current.border }    // 原 white@.07

    /// 明暗自适应的表面叠加色。暗色主题用白色提亮、亮色主题用黑色压暗,叠加强度
    /// (`o`)语义在两侧一致。用于 hover / 选中 / 分隔线 / 填充等不透明 chrome 表面上
    /// 的微叠加 —— 原先全写死 `Color.white.opacity(o)`,亮色主题下白叠白会失效。
    /// (玻璃材质上的物理高光不走这里,见 VisualEffectBackground。)
    static func overlay(_ o: Double) -> Color {
        current.isDark ? Color.white.opacity(o) : Color.black.opacity(o)
    }

    /// Canonical accent palette keyed by the `glint.accentName` token. Single
    /// source for the SwiftUI chrome accent (`WorkspaceStore.accent`), the
    /// Settings swatches, and the terminal cursor/selection color so the three
    /// never drift. "indigo" / unset map to `accentBright`.
    static func accent(named name: String?) -> Color {
        switch name {
        case "cyan":   return cyan
        case "pink":   return pink
        case "orange": return orange
        case "green":  return green
        default:       return accentBright
        }
    }
}

extension Color {
    /// "RRGGBB" in sRGB. Lets a chrome accent `Color` feed ghostty's text
    /// config (cursor/selection), which only accepts hex strings — so the
    /// terminal color is derived from the same `Theme` color the UI uses
    /// rather than a hand-kept parallel hex table.
    var rgbHex: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

extension Font {
    static let glintUI       = Font.system(size: 13, weight: .medium)
    static let glintUISmall  = Font.system(size: 12, weight: .medium)
    static let glintCaption  = Font.system(size: 10.5, weight: .semibold).leading(.tight)
    static let glintSection  = Font.system(size: 10.5, weight: .semibold)
    static let glintMono     = Font.system(size: 12.5, weight: .regular, design: .monospaced)
    static let glintMonoBig  = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let glintStatus   = Font.system(size: 11, weight: .medium, design: .monospaced)
}
