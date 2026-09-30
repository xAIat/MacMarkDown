# ADR-004：编辑器主题使用 Swift 值类型与 INI 风格样式文件

## 状态

**已采纳** — 2026 年 9 月

## 背景

macOS 26 与 Swift 6.4 为 Apple 的开发生态开启了新纪元：SwiftUI、Observation、TextKit 2 与 Swift 并发已经成熟到足以承载一个完整的写作工具，因此 MacMarkDown 用纯 Swift 与 SwiftUI 从零写成。主题往往是写作工具偏离这条路线的地方：语法配色常被交给第三方高亮库，其调色板存放在外部文件格式中，游离于类型系统之外。

MacMarkDown 的主题覆盖三个层面：

- **编辑器源码高亮** —— 纯文本面板中的 Markdown 标记：标题、强调、加粗、代码、链接、引用、列表标记、Front Matter。编辑器由 `NSTextStorage` 支撑，因此标记颜色必须落到 AppKit 属性上。
- **预览样式** —— 渲染文档的颜色与排版（ADR-003，`Theme`）。
- **代码标记配色** —— 围栏代码块的关键字/字符串/注释/数字颜色。

设计约束：

- 主题值应为 Swift 值：`Sendable`、`Hashable`，可在 SwiftUI 中使用，并可脱离运行时解释器进行测试。
- 项目以 Swift 6 与完整严格并发构建；内置 C 高亮库会游离在这些保障之外。
- 用户应能在不重新构建应用的情况下添加调色板。一个收窄的文件格式足以承载颜色值；它不应成为唯一的事实来源。
- 编辑器面板需要 AppKit 桥接，因为其文本存储是 `NSTextStorage`。

## 决定

主题使用 Swift 值类型建模，并保留一个收窄的 INI 风格文件格式用于附加调色板。

### EditorTheme

`EditorTheme`（`MacMarkDown/Theme/EditorTheme.swift`）是一个 `Sendable`、`Hashable`、`Identifiable` 结构体，提供具名颜色角色：

- 基础 —— background、text、cursor、selection、lineHighlight
- 标记 —— title、emphasis、strong、code、link、quote、listMarker、heading、bold、italic

内置主题为 `defaultLight`、`defaultDark`、`solarizedLight`、`solarizedDark`、`night` 与 `tomorrow`。`EditorTheme.selectable` 将内置主题与文件主题合并，`EditorTheme.theme(named:)` 按名称解析已保存的主题。

### INI 风格的 `.style` 文件

`EditorTheme+StyleFile` 解析 INI 风格的 `.style` 文件：单独一行的段名对应 Markdown 元素（`H1`、`EMPH`、`STRONG`、`CODE`、`LINK`、`BLOCKQUOTE`、`LIST_BULLET`、`editor`、`editor-selection`），其后是 `key: value` 形式的十六进制颜色，段之间以空行分隔。缺少的段会回退到由该文件 `editor` 段背景/前景色派生的颜色，因此不完整的文件也能生成完整主题。内置文件位于 `MacMarkDown/Resources/Themes/`；`ResourceLoader.availableThemeNames` 负责发现，并按显示名称排序。向该目录放入另一个 `.style` 文件即可增加可选主题，无需改动 Swift 代码。

### 预览样式

预览外观是独立的关注点：`Theme`（`MacMarkDown/Theme/Theme.swift`）承载渲染文档的语义颜色与排版，`MacMarkDown/Resources/Styles/` 下对应的 CSS 文件是 `Renderer` 嵌入导出 HTML 的形式。`AttributedRenderer` 为文本表面使用同一组 `Theme` 值，因此预览与导出的 HTML 共享同一套配色。

### 代码高亮调色板

`CodeHighlightTheme`（`MacMarkDown/Theme/CodeHighlightTheme.swift`）定义四个标记颜色——keyword、string、comment、number。内置调色板为 Xcode、Solarized (Dark)、Monokai 与 Tomorrow；默认（空字符串）名称表示“跟随预览主题的代码颜色”。

### 选择与持久化

设置 → 编辑器提供基于 `EditorTheme.selectable` 的 “Editor Theme” 选择器；所选值以 `preferences.editorStyleName` 存入 `UserDefaults`，并通过 `EditorTheme.theme(named:)` 解析。预览样式表与代码调色板在设置 → 渲染中各有独立选择器。

### AppKit 桥接

`EditorTheme+AppKit` 将每个颜色角色映射为 `NSColor`。`MarkdownEditorView` 将背景、光标、选区与文字颜色应用到编辑器的文本视图，并对文本存储运行 `MarkdownSyntaxHighlighter(theme:)`。高亮器按顺序处理：先把围栏代码作为整体着色，再逐行识别块级与行内标记，并记录已占用范围，因此后续处理不会覆盖先前标记内部的颜色。

## 备选方案

### 1. 内置带自有主题格式的第三方 C 高亮库

**已否决。** C 库与纯 Swift 构建相冲突，其调色板游离在 Swift 类型系统之外，没有编译期校验，主题属性仅限标记颜色，应用还需依赖运行时解析器来决定自身外观。

### 2. 以 JSON 或 YAML 作为主题的主要格式

**作为主要模型已否决。** 需要运行时解析与校验，拼写错误会静默回退，作者需要了解模式而非 Swift 类型。本项目支持的 `.style` 格式刻意更窄：它只为 Swift 中已有的角色提供颜色，不能定义新角色或行为。

### 3. 基于 plist 的主题（类似 Xcode）

**已否决。** Xcode 的主题模型覆盖编辑器、控制台与调试器多层；采用 plist 会增加运行时解析与错误处理，同时同样失去类型安全。

### 4. 仅使用 SwiftUI `.tint()` / 强调色

**已否决。** 内置颜色系统只提供强调色与色调，无法提供 Markdown 编辑器需要的编辑器外观、列表/引用/代码背景与标记颜色。

## 影响

### 积极影响

- **值语义。** `EditorTheme` 是 `Sendable`、`Hashable` 且 `Identifiable`；可做相等比较（主题输入未变化时预览跳过渲染），也可跨并发域传递。
- **类型安全。** 内置主题是 Swift 代码；缺少或拼错的角色会导致编译失败，而不是运行时回退。
- **可发现性。** 角色以 `.headingColor`、`.selectionColor` 等形式呈现，IDE 可自动补全；`#Preview` 无需启动应用即可渲染调色板。
- **用户可扩展调色板。** `.style` 文件在启动时增加主题，无需重新构建；不完整的文件会由派生默认值补全。
- **一套配色，多个消费者。** 编辑器通过 `EditorTheme+AppKit` 应用 `EditorTheme`，预览使用自己的 `Theme` 值与 CSS；两者可独立演进。
- **自包含。** 主题、样式表与高亮器随应用一同分发；运行时无需下载任何内容。

### 消极影响

- **颜色固定。** 一个主题就是一套调色板。要跟随系统的浅色/深色外观，需要选择匹配的主题（例如 `defaultLight`/`defaultDark` 或 `solarizedLight`/`solarizedDark`），而不是在运行时派生。
- **文件格式仅限颜色。** `.style` 文件可为已知角色设置颜色，不能增加新角色、字体或布局属性；这些需要修改 Swift 代码。
- **宽容解析。** 缺失或格式错误的条目会回退到派生默认值，这保证了可用性，但可能掩盖用户编辑文件中的拼写错误。
- **二进制与源码成本。** 每个内置主题都是代码；成本可忽略（每个主题的调色板值仅数百字节）。

### 风险

- **主题数量增长。** 内置主题过多会使内置文件臃肿。缓解措施：将内置主题拆分到扩展文件（如 `EditorTheme+Builtin.swift`），让 `EditorTheme` 只保留模型与解析逻辑。
- **用户文件中的静默回退。** 缓解措施：保持解析器精简并由 `EditorThemeStyleFileTests` 覆盖，同时记录可识别的段，便于用户了解文件支持的范围。
- **用户调色板可读性不足。** 手工编辑可能产生低对比度颜色。缓解措施：随应用提供经过测试的调色板，并保持解析的增量性，使缺失值不会移除合理的默认值。

## 参考

- `EditorTheme` — MacMarkDown/Theme/EditorTheme.swift
- 样式文件解析器 — MacMarkDown/Theme/EditorTheme+StyleFile.swift
- AppKit 桥接 — MacMarkDown/Theme/EditorTheme+AppKit.swift
- 编辑器高亮器 — MacMarkDown/Services/Editor/MarkdownSyntaxHighlighter.swift
- 预览主题与样式表 — MacMarkDown/Theme/Theme.swift、MacMarkDown/Resources/Styles/
- 代码高亮调色板 — MacMarkDown/Theme/CodeHighlightTheme.swift
- 设置选择器 — MacMarkDown/UI/Shared/Settings/SettingsView.swift
- Apple SwiftUI Color — https://developer.apple.com/documentation/swiftui/color
- Apple NSColor — https://developer.apple.com/documentation/appkit/nscolor
