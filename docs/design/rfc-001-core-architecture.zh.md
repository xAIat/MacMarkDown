# RFC-001：核心架构

- **状态**：提议
- **日期**：2026-09-15
- **作者**：架构团队
- **读者**：工程、产品
- **关联**：[RFC-002 渲染管线](rfc-002-rendering-pipeline.zh.md)、[业务总览](../business/overview.zh.md)

---

## 1. 摘要

macOS 26 与 Swift 6.4 为 Apple 的开发生态开启了新纪元：SwiftUI、Observation、TextKit 2 与 Swift 并发已经成熟到足以承载一个完整的写作工具，因此 MacMarkDown 用纯 Swift 与 SwiftUI 从零写成。

本 RFC 定义 MacMarkDown 的核心架构：分层设计、关键组件、编辑器与预览之间的数据流，以及 Swift 6.4 严格并发下的并发策略。XcodeGen 工程（`project.yml`）产出四个目标：

| 目标 | 源码根目录 | 职责 |
|------|-----------|------|
| `MacMarkDown` | `MacMarkDown/Application` | SwiftUI 应用：`WindowGroup`、`Settings` 场景、菜单命令、应用代理 |
| `MacMarkDownKit` | `MacMarkDown/` | 框架：文档模型、Markdown 管线、服务、存储、主题、UI |
| `macmarkdown-cli` | `CLI/` | `macmarkdown` 命令行伴侣 |
| `MacMarkDownTests` | `MacMarkDown/Tests` | 解析器、渲染器、文档、编辑器与滚动同步的单元测试 |

## 2. 目标 / 非目标

### 2.1 目标

- **唯一事实源**：`MarkdownDocument` 拥有文本；编辑器、预览、脚本桥与导出器都从它读取。
- **唯一 Markdown 路径**：单个 `MarkdownParser` 产出一棵元素树，原生预览与 HTML 导出器共同消费（见 RFC-002）。
- **原生预览**：TextKit 2 与 SwiftUI 在进程内渲染文档；仅对确实需要 WebKit 的块（表格、MathJax）使用 WebView。
- **编译期数据竞争安全**：`SWIFT_STRICT_CONCURRENCY = complete` 让 actor 隔离保持机械、可审查。
- **小巧且可脚本化的接口**：AppleScript、CLI 与 Finder 打开都汇入同一个文档会话。

### 2.2 非目标

- v1 不做增量解析；每次渲染都重新分析整个文档。
- 不做跨平台目标；代码库按设计仅面向 macOS。
- 不引入第三方 Markdown 引擎；Apple 的 `swift-markdown` 是唯一解析器。
- 不使用 XIB/NIB 文件或视图控制器驱动的 UI；SwiftUI 是唯一的 UI 栈。

## 3. 系统结构图

```
┌──────────────────────────────────────────────────────────────────────┐
│                           应用层（APP LAYER）                         │
│  ┌───────────────────┐        ┌───────────────────────────────────┐  │
│  │ MacMarkDownApp    │───────▶│ Settings 场景 → SettingsView      │  │
│  │ （@main, SwiftUI）│        │ 通用 · Markdown · 编辑器 ·        │  │
│  │ WindowGroup       │        │ HTML · 终端                        │  │
│  │ 命令 / 菜单        │        └───────────────────────────────────┘  │
│  └─────────┬─────────┘                                               │
│            │ 创建                                                     │
│            ▼                                                         │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                      视图层（VIEW LAYER）                     │    │
│  │  ┌───────────────────────────────┐  ┌──────────────────────┐ │    │
│  │  │ DocumentView                  │  │ ToolbarView          │ │    │
│  │  │ 分屏 · 查找栏 · 字数统计 ·     │◀─│ 格式化操作 ·         │ │    │
│  │  │ 滚动同步协调                   │  │ 列表 · 引用          │ │    │
│  │  ├───────────────┬───────────────┤  └──────────────────────┘ │    │
│  │  │ Markdown      │ PreviewPane   │      ┌───────────────┐     │    │
│  │  │ EditorView    │ MarkdownPreview│     │ WordCountBar  │     │    │
│  │  │ （TextKit 2） │ Surface + 网页 │      └───────────────┘     │    │
│  │  │               │ 块            │                            │    │
│  │  └───────────────┴───────────────┘                            │    │
│  └───────────────────────┬──────────────────────────────────────┘    │
│                          │ 观察 / 命令                               │
│                          ▼                                           │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                     文档层（DOCUMENT LAYER）                  │    │
│  │  MarkdownDocument · DocumentSession · DocumentOpenQueue      │    │
│  │  RecentDocumentsStore · ScriptableDocument                   │    │
│  │  UnsavedChangesGuard · FrontMatter                           │    │
│  └──────────────────────────┬───────────────────────────────────┘    │
│                             ▼                                        │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                      服务层（SERVICE LAYER）                  │    │
│  │  RenderService · AttributedRenderer · Renderer               │    │
│  │  ExportService · ScrollSyncService/Coordinator               │    │
│  │  MarkdownSyntaxHighlighter · CodeSyntaxHighlighter           │    │
│  │  FindController · PlugInManager                              │    │
│  └──────────────────────────┬───────────────────────────────────┘    │
│                             ▼                                        │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │            MARKDOWN / THEME / STORES 层                       │    │
│  │  MarkdownParser · MarkdownElement · DocumentAnchor           │    │
│  │  Theme · EditorTheme · Preferences                           │    │
│  └──────────────────────────┬───────────────────────────────────┘    │
│                             ▼                                        │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                     工具层（UTILITY LAYER）                   │    │
│  │  Constants · FontResolver · ResourceLoader · TerminalUtility │    │
│  │  StringExtensions · 打包资源（样式、编辑主题、模板）           │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

## 4. 分层原则

依赖严格单向流动：**App → UI → Document → Services → Markdown/Theme/Stores → Tools/Extensions**。某一层可以依赖本层或更底层；`Document` 层可为每个文档组合 `Services`，但 `Services` 绝不引用 `UI` 或 `Document`。

| 层 | 职责 | 允许依赖 |
|----|------|---------|
| App | 组合根：场景、命令/菜单、应用代理、设置窗口 | 以下所有层 |
| UI（`UI/Shared`、`UI/macOS`） | 文档界面、编辑器与预览窗格、工具栏、查找栏、设置 UI | Document、Services、Stores、Theme |
| Document | 文件生命周期、会话注册表、打开队列、最近文档、脚本桥、未保存保护、front matter | Services、Markdown、Theme、Stores、Tools |
| Services | 渲染管线、属性化渲染、导出、滚动同步、语法高亮、插件 | Markdown、Theme、Stores、Tools/Extensions |
| Markdown / Theme / Stores | 元素树与解析；主题值；基于 UserDefaults 的偏好 | Tools/Extensions、swift-markdown、Yams |
| Tools / Extensions | 无状态助手：常量、字体解析、资源加载、终端安装、字符串助手 | — |

### 4.1 理由

- **可测试性**：Markdown 层与服务层保持与 UI 解耦，无需宿主应用即可单元测试；`MacMarkDownTests` 直接链接 `MacMarkDownKit`。
- **SwiftUI 响应式**：`@Observable` 模型直接通知视图，UI 无需命令式刷新。
- **严格并发**：把所有可变状态收敛在 `@MainActor` 上，让 `Sendable` 要求从层的边界自然得出，而不是事后补救。

## 5. 关键组件

| 组件 | 位置 | 职责 |
|------|------|------|
| `MacMarkDownApp` | `Application/` | `@main`；`WindowGroup`、`Settings` 场景、菜单命令 |
| `MarkdownDocument` | `Document/` | `@Observable` 事实源：`text`、`fileURL`、`lastSavedText`、`isEdited`、自动保存 |
| `DocumentSession` | `Document/` | 已打开窗口/文档的注册表，供菜单动作取用 |
| `DocumentOpenQueue` | `Document/` | 在窗口就绪前缓冲 Finder/CLI 的文件打开请求 |
| `RecentDocumentsStore` | `Document/` | 「最近打开」菜单 |
| `ScriptableDocument` | `Document/` | AppleScript 桥（`MacMarkDown.sdef`） |
| `UnsavedChangesGuard` | `Document/` | 在关窗或退出时保护未保存的修改 |
| `FrontMatter` | `Document/` | 用 Yams 提取 YAML front matter |
| `DocumentView` | `UI/Shared/Document` | 分屏布局、工具栏、查找栏、字数统计、滚动同步协调 |
| `MarkdownEditorView` | `UI/macOS/Editor` | TextKit 2 编辑面（布局片段、行号槽、智能编辑） |
| `MarkdownPreviewSurface` | `UI/macOS/Preview` | 基于 `AttributedRenderer` 输出的只读 TextKit 2 预览 |
| `PreviewWebBlockView` | `UI/macOS/Preview` | 用于表格与 MathJax 公式的 `WKWebView` 块 |
| `MarkdownView` | `UI/Shared/Preview` | 纯 SwiftUI 元素树预览（回退路径） |
| `Preferences` | `Stores/` | `@Observable`、基于 `UserDefaults` 的五个面板设置 |
| `RenderService` | `Services/Preview` | 防抖的解析/渲染协调器；发布元素、锚点与 HTML 片段 |
| `ScrollSyncService` / `ScrollSyncCoordinator` | `Services/ScrollSync` | 配对编辑器与预览锚点并映射偏移 |
| `ExportService` | `Services/Export` | 文件、剪贴板、打印与 PDF 导出 |
| `PlugInManager` | `Services/PlugIn` | 将 `.macmarkdown-plugin` 包载入插件菜单 |
| `TerminalUtility` | `Tools/` | 将 `macmarkdown` CLI 安装到 `/usr/local/bin` |

## 6. 数据流

编辑器→预览的规范路径：

```
用户键入字符
        │
        ▼
MarkdownEditorView.onTextChange
        │ 写入
        ▼
MarkdownDocument.updateText(_:)  ◀────────────（唯一事实源）
        │ 若未开启手动渲染
        ▼
RenderService.scheduleRender(text:options:)   （防抖 300 ms；取消过期工作）
        │
        ▼
MarkdownParser.parseDocument → ParsedDocument([MarkdownElement], [DocumentAnchor])
        │ 被观察
        ▼
PreviewPane
        ├─► MarkdownPreviewSurface：AttributedRenderer → NSAttributedString → TextKit 2
        └─► PreviewWebBlockView 覆盖层：表格与 MathJax 公式
        │
        ▼
预览展示更新后的文档
```

- `MarkdownEditorView` 是直写（write-through）面：击键立即写入 `MarkdownDocument.text`；任何瞬时编辑器局部状态都不参与渲染。
- 所有跨窗格同步（至少在滚动位置层面）都经 `ScrollSyncCoordinator`，绝不使用全局共享量。
- 偏好单向流入渲染：`Preferences` → `RenderService` 选项与 `Theme` → 预览和导出；预览从不反向修改设置。
- 导出经 `ExportService` 读取同一份解析输出（见 RFC-002 §9）。

## 7. 用 @Observable 管理状态

模型遵循 SwiftUI Observation，绝不使用 `ObservableObject`/`@Published`：

```swift
import Observation

@MainActor
@Observable
public final class MarkdownDocument: Identifiable {
    public let id = UUID()
    public var text: String = ""
    public var fileURL: URL?
    public private(set) var lastSavedText: String = ""

    public let preferences: Preferences
    public let parser: MarkdownParser
    public let renderService: RenderService

    /// 派生属性：撤销回已保存内容时自动清除「已修改」状态。
    public var isEdited: Bool { text != lastSavedText }
}
```

变更通知按属性粒度发出，因此 `DocumentView` 只重绘受影响的子视图；预览只观察 `renderService.elements`，字数栏观察派生计数，不拖拽整个视图树。`Preferences` 是 `@Observable` 类，其属性直写 `UserDefaults`，因此设置窗口与文档窗格观察到的是同一份值。

## 8. Swift 6.4 严格并发

### 8.1 隔离策略

| 类别 | 隔离 | 理由 |
|------|------|------|
| UI 视图（`DocumentView`、`MarkdownPreviewSurface`、`MarkdownView`） | `@MainActor` | 所有 UI 变更必须在主 actor 上进行 |
| `MarkdownDocument`、`Preferences`、`RenderService`、`ScrollSyncService` | `@MainActor`（`@Observable`） | 可变应用状态由 UI 写入、由视图读取 |
| `AttributedRenderer`、`Renderer`、`ExportService` | `@MainActor` | 它们由模型值构建 AppKit/HTML 输出 |
| `MarkdownElement`、`InlineElement`、`DocumentAnchor`、`ParsedDocument`、`Theme`、`EditorTheme`、`MarkdownParseOptions` | `Sendable` 值类型 | 可跨隔离边界传递的不可变数据 |
| 工具（Tools/Extensions） | `Sendable` 结构体 / 自由函数 | 无状态 |

### 8.2 并发规则

1. **不共享可变状态** —— 任何被多上下文写入的内容都必须是不可变值类型或主 actor 状态。
2. **主 actor 串行化** —— 解析与渲染发布构成一条串行管线；解析器产出 `Sendable` 值，观察者可无锁拷贝。
3. **取消优先** —— 新的渲染先取消上一项已调度的工作，而不是无限排队；手动渲染绕过队列。
4. **编译期强制** —— 项目以 `SWIFT_STRICT_CONCURRENCY = complete` 构建；CI 对警告设红线。

```swift
@MainActor
@Observable
public final class RenderService: @unchecked Sendable {
    public private(set) var elements: [MarkdownElement] = []
    public private(set) var anchors: [DocumentAnchor] = []

    private var workItem: DispatchWorkItem?

    /// 手动渲染（⌘R）：立即解析，不做防抖。
    public func parseNow(text: String, options: MarkdownParseOptions) { … }

    /// 实时键入：取消待执行的解析并调度新一轮。
    public func scheduleRender(text: String, options: MarkdownParseOptions) {
        workItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.parseNow(text: text, options: options)
        }
        workItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.defaultDebounceInterval,
            execute: work
        )
    }
}
```

### 8.3 线程契约

- 编辑器输入、解析、主题应用与预览更新都在主 actor 上按文档顺序发生；防抖窗口限定了整文档被重新分析的频率。
- 跨隔离边界的值类型都是 `Sendable` 拷贝；引用类型绝不跨线程共享。
- 主线程外的工作仅限系统框架（WebKit 高度测量、文件 I/O），它们都在主线程回报结果。

## 9. 待决议问题

1. `MarkdownDocument` 应采纳 SwiftUI 的 `FileDocument` 值语义，还是保留 `@Observable` 会话模型——毕竟 `DocumentSession` 与 `UnsavedChangesGuard` 依赖当前的显式打开/保存管线？
2. 编辑器应保留 TextKit 2 的 `NSTextView` 桥以获取光标与锚点坐标，还是纯 SwiftUI 编辑面已经能提供滚动同步所需的测量精度？
3. 整文档重解析是否能长期保持在预算内（见 RFC-002 §10），还是 v2 应引入增量解析？
4. `Preferences` 是否需要批量写入以支持多窗口实时更新，还是在目标文档规模下即时 `UserDefaults` 直写已足够？
