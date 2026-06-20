# Glint

## 多语言 / 本地化(新功能必做)

所有**面向用户的 UI 文案**都必须本地化,至少 `en`(源语言)+ `zh-Hans`。新增或修改可见文案时,**同步**在字符串目录补 `zh-Hans` 翻译;不允许留下硬编码、只有英文的可见文本。

### 机制
- 字符串目录:`Glint/Resources/Localizable.xcstrings`(`sourceLanguage = en`,`developmentRegion = en`,已含 `zh-Hans`)。英文直接用源串(key 本身)作英文值,只需补 `zh-Hans` 条目(`extractionState: "manual"`、`state: "translated"`)。
- SwiftUI 里 `Text("字面量")` 自动是 `LocalizedStringKey`,会查表本地化。
- 非 View 上下文(`NSAlert`、字符串拼接、回调、`menu` title 等)用 `String(localized: "…")`。
- 运行时跟随系统语言或应用内语言覆盖(`AppleLanguages` + `.environment(\.locale,)`,见 `GlintApp`/`WorkspaceStore.preferredLocale`),代码里无需额外处理。

### 关键陷阱(最容易漏)
- `Text(someStringVariable)`(变量类型是 `String`)走的是 **verbatim 重载,不本地化**。把字面量经 `String` 形参传进 helper(例如 `func cell(_ k: String) { Text(k) }`)会**静默丢掉本地化** —— 编译不报错、英文环境下也看不出,只有切到中文才发现没翻译。
- 因此:helper / 自定义视图里**用作 UI 标签的形参类型必须是 `LocalizedStringKey`**(不是 `String`),这样字面量调用点才会进目录。
- **数据不要翻译**:分支名、路径、文件名、用户输入、commit 标题、URL 等是数据,保持 `String`(verbatim)。只翻译 UI chrome(标题、按钮、菜单、占位、提示语)。
- 单复数:英文单复数拆成各自的 key(如 `"1 file"` / `"%lld files"`),不要在代码里手拼 `"s"`,方便其它语言独立翻译。

### 加新可见文案的流程
1. 代码里用 `Text("…")` / `String(localized: "…")`,helper 形参用 `LocalizedStringKey`。
2. 在 `Glint/Resources/Localizable.xcstrings` 给每个新 key 补 `zh-Hans` 翻译(保持 JSON 缩进 2 空格、`ensure_ascii=False`)。
3. build 后切到中文环境目检,语言中性内容(符号、数字、纯数据)确认未被误翻。
