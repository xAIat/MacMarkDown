# Apple Swift 26 合规性审计

**项目**：MacMarkDown  
**Swift 版本**：6.4  
**目标平台**：macOS 26  
**审计日期**：2026-09-15  
**审计人员**：MacMarkDown 核心团队  

---

## 1. 概述

macOS 26 与 Swift 6.4 为 Apple 的开发生态开启了新纪元：SwiftUI、Observation、TextKit 2 与 Swift 并发已经成熟到足以承载一个完整的写作工具，因此 MacMarkDown 用纯 Swift 与 SwiftUI 从零写成。本文档审计代码库对 Swift 6.4 要求与最佳实践的符合情况，涵盖严格并发、`Sendable` 合规、数据竞争安全、Observation 的使用，以及让上述各项可验证的测试策略。

## 2. 严格并发

### 2.1 审计项目

| # | 检查项 | 状态 | 备注 |
|---|--------|------|------|
| SC-01 | 所有 `@MainActor` 隔离的类型都正确标注 | ✅ 通过 | `MarkdownDocument`、`DocumentSession`、`Preferences`、`MarkdownParser`、`RenderService`、`FindController`、`ScrollSyncService`、`PlugInManager`、`MarkdownTextView` 均已显式标注；`MarkdownEditorView` 与 `MarkdownPreviewSurface` 通过 `NSViewRepresentable` 获得主 actor 隔离 |
| SC-02 | 没有未隔离的可变共享状态 | ✅ 通过 | 所有可变存储要么是 `@MainActor` 隔离的，要么是 `let` 常量 |
| SC-03 | 传递给后台任务的闭包是 `Sendable` 的 | ✅ 通过 | `MarkdownDocument` 中的自动保存 `Task` 与 `RenderService` 中的防抖工作项只弱引用 `@MainActor` 状态 |
| SC-04 | `nonisolated(unsafe)` 的使用已审查并有依据 | ⚠️ 待审查 | 共 6 处：`NSCache` 缓存（`CodeSyntaxHighlighter`、`MarkdownView`）、Objective-C 委托转发（`UnsavedChangesGuard`）与通知观察令牌（`MarkdownPreviewSurface`） |
| SC-05 | 没有无理由的 `@preconcurrency import` | ✅ 通过 | 代码库中没有 `@preconcurrency` 导入；AppKit 边界由 `@MainActor` 隔离 |
| SC-06 | 构建设置中启用了严格并发模式 | ✅ 通过 | 所有 target 均为 `SWIFT_STRICT_CONCURRENCY = complete` |
| SC-07 | 没有与并发相关的编译器警告 | ✅ 通过 | 2026-09-15 验证的干净构建 |
| SC-08 | `TaskLocal` 值是 `Sendable` 的 | ✅ 通过 | 不适用 — 未使用 `TaskLocal` |

### 2.2 并发隔离映射

```
┌──────────────────────────────────────────────────────────┐
│                        @MainActor                        │
│   MarkdownDocument   DocumentSession   Preferences       │
│   RenderService      MarkdownParser    MarkdownTextView  │
│   ScrollSyncService  FindController    PlugInManager     │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│                      Sendable 值类型                      │
│   MarkdownElement       ParsedDocument   DocumentAnchor  │
│   MarkdownParseOptions  EditorTheme      Theme           │
│   CodeHighlightTheme                                     │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│                    非隔离 / 纯函数                        │
│   FontResolver   StringExtensions   EditorFormatting     │
└──────────────────────────────────────────────────────────┘
```

## 3. Sendable 合规

### 3.1 审计项目

| # | 检查项 | 状态 | 备注 |
|---|--------|------|------|
| SE-01 | 所有模型类型符合 `Sendable` | ✅ 通过 | `MarkdownElement`、`ParsedDocument`、`DocumentAnchor`、`MarkdownParseOptions`、`EditorTheme`、`Theme`、`CodeHighlightTheme`、`FrontMatter` 全部符合 |
| SE-02 | 带有关联值的枚举类型是 `Sendable` 的 | ✅ 通过 | `MarkdownElement`、`InlineElement`、`FrontMatterValue` 的关联值全部是 `Sendable` 的 |
| SE-03 | 具有 `Sendable` 属性的结构体隐式符合 `Sendable` | ✅ 通过 | 已对所有值类型验证 |
| SE-04 | `@Observable` 类有明确的 `Sendable` 策略 | ⚠️ 待审查 | `Preferences`、`MarkdownDocument`、`RenderService`、`FindController`、`ScrollSyncService`、`RecentDocumentsStore` 都是引用类型；它们依靠 `@MainActor` 隔离，而不是声明 `Sendable` 符合性 |
| SE-05 | 在适当的地方使用 `actor` 类型 | ℹ️ 信息 | 不需要 actor — 所有可变存储都由 `@MainActor` 隔离 |
| SE-06 | `@MainActor` 类型上的 `nonisolated` 成员已审查 | ✅ 通过 | 只有纯函数（`FontResolver`）、`MarkdownView` 的相等性判断和 Objective-C 回调是 `nonisolated` 的 |
| SE-07 | 并发上下文中的闭包捕获是 `Sendable` 的 | ✅ 通过 | 通过严格并发编译器检查验证 |

### 3.2 Sendable 合规表

| 类型 | 类别 | `Sendable` | 机制 |
|------|------|------------|------|
| `MarkdownElement` | 间接枚举 | ✅ 是 | 显式符合；所有关联值均为值类型 |
| `ParsedDocument` | struct | ✅ 是 | 隐式（所有存储属性都是 `Sendable`） |
| `DocumentAnchor` | struct | ✅ 是 | 隐式 |
| `MarkdownParseOptions` | struct | ✅ 是 | 隐式 |
| `EditorTheme` | struct | ✅ 是 | 隐式 |
| `Theme` | struct | ✅ 是 | 隐式 |
| `CodeHighlightTheme` | struct | ✅ 是 | 隐式 |
| `FrontMatter` | struct | ✅ 是 | 隐式 |
| `MarkdownDocument` | class | ✅ 是 | `@MainActor` 隔离 + `@Observable` |
| `Preferences` | class | ✅ 是 | `@MainActor` 隔离 + `@Observable` |
| `FindController` | class | ✅ 是 | `@MainActor` 隔离 + `@Observable` |
| `ScrollSyncService` | class | ✅ 是 | `@MainActor` 隔离 + `@Observable` |
| `MarkdownParser` | class | ✅ 是 | `@MainActor` 隔离；`@unchecked Sendable`，同步执行，调用之间无状态 |
| `RenderService` | class | ✅ 是 | `@MainActor` 隔离；`@unchecked Sendable`，防抖工作在主队列执行 |
| `Renderer` | class | ✅ 是 | `@MainActor` 隔离；`@unchecked Sendable`，输出一次赋值完成 |

## 4. 数据竞争安全

### 4.1 渲染管线分析

```
用户输入文本
       │
       ▼
┌──────────────────┐     ┌─────────────────┐     ┌────────────────┐
│ MarkdownDocument │────▶│ RenderService   │────▶│ MarkdownParser │
│   (MainActor)    │     │   (MainActor)   │     │  (MainActor)   │
└──────────────────┘     └─────────────────┘     └───────┬────────┘
                                                         │
                                                   ParsedDocument
                                                         │
                        ┌────────────────────────────────┤
                        │                                │
                        ▼                                ▼
                ┌────────────────┐               ┌────────────────┐
                │  MarkdownView /│               │   Renderer     │
                │  Attributed-   │               │  (MainActor)   │
                │  Renderer      │               │  → 导出 HTML   │
                │  (MainActor)   │               └────────────────┘
                └───────┬────────┘
                        │ 表格 / 数学公式
                        ▼
                ┌────────────────┐
                │ PreviewWeb-    │
                │ BlockView      │
                │  (MainActor)   │
                └────────────────┘
```

### 4.2 审计项目

| # | 检查项 | 状态 | 备注 |
|---|--------|------|------|
| DR-01 | 没有对共享可变状态的并发写入 | ✅ 通过 | 所有写入都发生在 `@MainActor` 上 |
| DR-02 | 解析器从 `@MainActor` 上下文调用 | ✅ 通过 | `MarkdownParser.parse(_:options:)` 同步执行且绑定主 actor，解析不会与 UI 更新交错 |
| DR-03 | HTML 生成不会跨任务共享可变状态 | ✅ 通过 | `Renderer` 从不可变的 `ParsedDocument` 构建 HTML，最终字符串一次赋值完成 |
| DR-04 | 预览面板更新是单线程的 | ✅ 通过 | `MarkdownView` 与 TextKit 2 预览都在主 actor 上更新；WebKit 块高度通过 `WKScriptMessageHandler` 送达并在主 actor 应用 |
| DR-05 | 文件 I/O 使用适当的隔离 | ⚠️ 待审查 | `MarkdownDocument.load(from:)` 与 `save(to:checkConflict:)` 目前在主 actor 上执行文件读写；计划改用结构化并发与 `sending` 值 |
| DR-06 | 没有未保护的富文本缓冲区访问 | ✅ 通过 | 预览富文本在 `AttributedRenderer` 中本地构建，并按值发布 |
| DR-07 | Undo Manager 集成是 `@MainActor` 安全的 | ✅ 通过 | `NSUndoManager` 的注册发生在 `MarkdownTextView` 的编辑路径中，且在主 actor 上执行 |

## 5. @Observable 宏的使用

### 5.1 用 Observation 取代 KVO

MacMarkDown 不保留任何 Objective-C KVO 记录。所有共享 UI 状态都用 Swift 的 `@Observable` 宏（macOS 14 与 Swift 5.9 引入）表达，并由 SwiftUI 直接消费：

| 经典 AppKit 模式 | MacMarkDown 模式 |
|------------------|------------------|
| `@objc dynamic var text: String` 加观察者 | `MarkdownDocument` 中的 `@Observable var text: String` |
| `addObserver(_:forKeyPath:...)` | 由 SwiftUI 自动进行变更跟踪 |
| `observeValue(forKeyPath:...)` | 在需要副作用时使用 `onChange(of:)` / `.task(id:)` |
| 手动注册与移除观察者 | 观察生命周期限定在视图 body 内 |

### 5.2 审计项目

| # | 检查项 | 状态 | 备注 |
|---|--------|------|------|
| OB-01 | 所有可观察状态都使用 `@Observable` 宏 | ✅ 通过 | `Preferences`、`MarkdownDocument`、`RenderService`、`FindController`、`ScrollSyncService`、`RecentDocumentsStore`；没有残留的 KVO 注册 |
| OB-02 | 没有使用 `@Published` | ✅ 通过 | 代码库中没有任何 `@Published` 用法 |
| OB-03 | `@Observable` 类是 `@MainActor` 隔离的 | ✅ 通过 | 所有可观察类均已标注 |
| OB-04 | 细粒度观察没有性能回退 | ⚠️ 待审查 | `RenderService` 发布多个属性；`MarkdownView` 实现 `Equatable` 并以 `.equatable()` 应用，因此仅滚动位置变化不会重建元素树 |
| OB-05 | 观察的消费方将状态视为只读 | ✅ 通过 | 视图 body 只读取状态；变更通过 `MarkdownDocument`、`Preferences`、`FindController` 的方法进行 |
| OB-06 | 观察驱动的回调没有循环引用 | ✅ 通过 | 服务由文档/视图层级持有；回调只持弱引用 |

### 5.3 @Observable 状态清单

```swift
@MainActor @Observable
public final class RenderService: @unchecked Sendable {
    public private(set) var elements: [MarkdownElement] = []   // 使用方：MarkdownView / MarkdownPreviewSurface
    public private(set) var anchors: [DocumentAnchor] = []     // 使用方：ScrollSyncCoordinator
    public private(set) var renderedHTML: String = ""          // 使用方：HTML 导出 / 剪贴板
    public private(set) var isRendering = false                // 使用方：渲染状态 UI
    public private(set) var lastError: String?                 // 使用方：渲染状态 UI
}
```

**优化说明**：预览元素树是 `[MarkdownElement]` 与主题的纯函数。由于 `MarkdownView` 实现 `Equatable` 并以 `.equatable()` 应用，仅滚动位置变化只会重新求值父级 body，不会重建元素树。

## 6. 测试策略

### 6.1 审计项目

| # | 检查项 | 状态 | 备注 |
|---|--------|------|------|
| ST-01 | 所有单元测试套件都基于 XCTest 并使用有类型的断言 | ✅ 通过 | `MacMarkDown/Tests` 下共 29 个测试文件 |
| ST-02 | 涉及 UI 与状态的套件由 `@MainActor` 隔离 | ✅ 通过 | 例如 `MarkdownTextViewTests`、`AttributedRendererTests`、`ScrollSyncServiceTests`、`FindControllerTests` |
| ST-03 | 每个测试都构建全新夹具并完成清理 | ✅ 通过 | 偏好设置套件使用独立的 `UserDefaults` suite；共享存储与队列在用例之间复位 |
| ST-04 | 依赖环境的测试跳过而不是失败 | ✅ 通过 | 用 `XCTSkip` 处理缺失字体与无窗口服务器的环境（`FontResolverTests`、`AttributedRendererTests`、`MarkdownTextViewTests`） |
| ST-05 | 解析器与编辑器的覆盖包含边界情况 | ✅ 通过 | `MarkdownParserTests`、`FrontMatterTests`、`SyntaxHighlighterTests`、`EditorSmartEditingTests` |
| ST-06 | 同步滚动映射在正反两个方向都有覆盖 | ✅ 通过 | `ScrollSyncServiceTests`（正向映射、钳制、无锚点回退）与 `ScrollSyncCoordinatorTests` |
| ST-07 | 数据安全路径有测试覆盖 | ✅ 通过 | `MarkdownDocumentAutosaveTests`、`DocumentSessionTests`、`UnsavedChangesGuardTests`、`DocumentOpenQueueTests` |

### 6.2 覆盖范围对照表

| 领域 | 测试套件 |
|------|----------|
| 解析 | `MarkdownParserTests`、`FrontMatterTests`、`StringExtensionsTests` |
| 预览渲染 | `AttributedRendererTests`、`InlineStyleRenderingTests`、`PreviewRenderingTests`、`PreviewSupportTests`、`TablePreviewHTMLTests`、`MathPreviewHTMLTests` |
| 编辑器 | `MarkdownTextViewTests`、`MarkdownTextViewHostTests`、`MarkdownTextViewStandardEditingTests`、`MarkdownEditorCoordinatorTests`、`EditorFormattingTests`、`EditorOperationsTests`、`EditorSmartEditingTests`、`SyntaxHighlighterTests`、`FindControllerTests` |
| 文档与数据安全 | `MarkdownDocumentAutosaveTests`、`DocumentSessionTests`、`DocumentOpenQueueTests`、`RecentDocumentsStoreTests`、`UnsavedChangesGuardTests`、`ScriptableDocumentTests` |
| 同步滚动 | `ScrollSyncServiceTests`、`ScrollSyncCoordinatorTests` |
| 主题与偏好设置 | `EditorThemeStyleFileTests`、`PreferencesTests`、`FontResolverTests` |

## 7. 已知限制

### 7.1 SwiftUI ↔ TextKit 2 桥接

| ID | 限制 | 影响 | 缓解措施 |
|----|------|------|----------|
| NL-01 | `NSViewRepresentable` 是 SwiftUI 与自定义 TextKit 2 编辑器之间的边界（`MarkdownEditorView` 承载 `MarkdownTextView`） | 中 | 视图与协调器都由 `@MainActor` 隔离；回调跳回主 actor |
| NL-02 | `updateNSView()` 不支持 `sending` 参数 | 低 | 跨边界传递的都是值类型（`String`、`EditorTheme`、`NSRange`） |
| NL-03 | `makeNSView()` 必须同步返回 | 低 | `MarkdownTextView` 完全在主 actor 上初始化，无需异步初始化 |
| NL-04 | 符合 `NSViewRepresentable` 的类型不能是 `Sendable` 的 | 低 | `@MainActor` 隔离使这一点在实践中不构成问题 |

### 7.2 WKWebView 集成

| ID | 限制 | 影响 | 缓解措施 |
|----|------|------|----------|
| NL-05 | Web 块的高度回报默认不是 `async` 安全的 | 中 | `PreviewWebBlockView` 通过 `WKScriptMessageHandler` 接收高度并在主 actor 上应用 |
| NL-06 | 脚本注入与页面加载需要主线程 | 低 | Web 块按内容键从 `@MainActor` 代码中只加载一次 |

### 7.3 渲染与布局性能

| ID | 限制 | 影响 | 缓解措施 |
|----|------|------|----------|
| NL-07 | 每次编辑都会重新解析整个文档 | 中 | `RenderService` 中 300ms 防抖并支持取消；`MarkdownTextView` 只对可见区域做片段布局 |
| NL-08 | 原生文本没有内置的代码高亮 | 高 | `MarkdownSyntaxHighlighter` 为编辑器文本存储着色；`CodeSyntaxHighlighter` + `CodeHighlightTheme` 为预览代码块着色 — 纯 Swift 实现，无需 Web 视图 |
| NL-09 | TextKit 2 无法布局表格网格或 TeX 公式 | 高 | 由 `PreviewWebBlockView` 覆盖按尺寸预留的占位附件；回报的高度写回文本布局 |

### 7.4 macOS 26 API 可用性

| ID | 限制 | 影响 | 缓解措施 |
|----|------|------|----------|
| NL-10 | TextKit 2 会随操作系统版本持续演进 | 中 | 编辑器在 `MarkdownTextView` 背后拥有完整的文本栈，将其余代码与之隔离 |
| NL-11 | 某些 `AttributedString` API 需要 macOS 15+ | 低 | 目标平台是 macOS 26 — 无需兼容分支 |
| NL-12 | Swift 6.4.x 可能引入新的严格并发诊断 | 中 | 关注发布说明并及时处理 |

## 8. 合规检查清单汇总

### 8.1 通过项（30 项）

- SC-01 至 SC-03、SC-05 至 SC-08
- SE-01 至 SE-03、SE-06、SE-07
- DR-01 至 DR-04、DR-06、DR-07
- OB-01 至 OB-03、OB-05、OB-06
- ST-01 至 ST-07

### 8.2 待审查项（4 项）

- SC-04：`nonisolated(unsafe)` 的使用（6 处，均有合理依据）
- SE-04：`@Observable` 类的 `@MainActor` 隔离策略
- DR-05：文件 I/O 的隔离策略
- OB-04：大文档场景下的观察粒度

### 8.3 信息项（1 项）

- SE-05：没有 actor 类型 — 主 actor 隔离已覆盖全部可变存储

### 8.4 失败项（0 项）

没有硬性失败。所有代码都在启用严格并发的情况下编译并通过检查。

## 9. 待办事项

| # | 事项 | 优先级 | 负责人 | 目标 |
|---|------|--------|--------|------|
| AI-01 | 为每个 `nonisolated(unsafe)` 成员补充理由注释 | 低 | 核心团队 | Sprint 2 |
| AI-02 | 用结构化并发与 `sending` 值将文档读写移出主 actor | 中 | 核心团队 | Sprint 3 |
| AI-03 | 为 `MarkdownParser`、`MarkdownTextView` 视口布局与 `MarkdownSyntaxHighlighter` 建立性能基线 | 中 | 核心团队 | Sprint 3 |
| AI-04 | 为 `PreviewWebBlockView` 补充布局测试，并将 WebKit 的使用范围限制在表格/数学块 | 中 | 核心团队 | Sprint 3 |
| AI-05 | 添加 CI 检查，将新的严格并发诊断视为失败 | 低 | 核心团队 | Sprint 4 |

## 10. 来源与延伸阅读

- [Swift Evolution SE-0302：Sendable 和 @Sendable 闭包](https://github.com/apple/swift-evolution/blob/main/proposals/0302-sendable-and-sendable-closures.md)
- [Swift Evolution SE-0304：结构化并发](https://github.com/apple/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
- [Apple 文档：采用 Swift 并发](https://developer.apple.com/documentation/swift/adopting-swift-concurrency)
- [Apple 文档：Observation](https://developer.apple.com/documentation/observation)
- [Apple 文档：TextKit](https://developer.apple.com/documentation/appkit/textkit)

---

*本审计是一份动态文档，将随开发迭代的推进持续更新。*

*最后更新：2026-09-15*
