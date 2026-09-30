# RFC-002：渲染管线

- **状态**：提议
- **日期**：2026-09-15
- **作者**：架构团队
- **读者**：工程、产品
- **关联**：[RFC-001 核心架构](rfc-001-core-architecture.zh.md)、[业务总览](../business/overview.zh.md)

---

## 1. 摘要

本渲染管线为 macOS 26 与 Swift 6.4 开启的框架世代而设计：TextKit 2 让预览拥有了一等的文本表面，Observation 驱动实时更新，Swift 并发让解析/渲染管线保持串行且无数据竞争。本 RFC 定义 Markdown 源文本如何转化为原生预览与导出 HTML。解析与表现解耦，因此预览、导出器与脚本桥共用由 Apple `swift-markdown` 包产出的同一棵元素树。

## 2. 目标 / 非目标

### 2.1 目标

- **唯一解析路径**：原生预览、HTML 导出与 AppleScript 的 `html` 属性共用同一条路径。
- **与呈现无关的元素树**（`MarkdownElement`）：只描述*展示什么*，外观由主题决定。
- **原生预览**：TextKit 2 在进程内渲染文档；WebKit 仅隔离在确实需要的块上（表格、MathJax 公式）。
- **自包含导出**：打包的模板、样式表与渲染脚本随输出一起分发。
- **确定性输出**：测试套件为每一种受支持的扩展固定 HTML 输出。

### 2.2 非目标

- v1 不做增量 AST diff；每次渲染都重新分析整个文档。
- 不支持直接编辑渲染后的 HTML；编辑器始终编辑 Markdown 源码。
- 不把隐藏浏览器当作通用预览；WebKit 只用于表格与数学块。
- 不依赖远程渲染服务；导出依靠打包资源即可离线工作。

## 3. 管线总览

```
输入：Markdown 文本（String）+ MarkdownParseOptions + Theme
        │
        ▼
步骤 1  MarkdownParser：行号保持的前处理 → swift-markdown Document
        │  → ParsedDocument([MarkdownElement], [DocumentAnchor])
        │  （Sendable 值；解析器在主 actor 上运行）
        ▼
步骤 2  [MarkdownElement] 是各输出面共享的模型
        │
        ├──► 实时预览（步骤 3）：AttributedRenderer → NSAttributedString
        │       → MarkdownPreviewSurface（TextKit 2，只读）
        │       表格 / MathJax → PreviewWebBlockView 占位（WKWebView）
        │       回退：MarkdownView 用 SwiftUI 渲染元素树
        │
        ├──► 主题（步骤 4）为两条预览路径提供样式并序列化为 CSS
        │
        └──► HTML 导出：Renderer → 完整 HTML 文档
                （Default.handlebars + Resources/Styles CSS）
                → ExportService：文件 / 剪贴板 / 打印 / PDF
        │
        ▼
步骤 5  RenderService 对文本变更防抖（300 ms），发布元素、
        锚点与 HTML 片段；⌘R 立即渲染
```

## 4. 输入

管线接收单个 `String`，包含一个文档的完整 Markdown 源码，连同激活的解析选项（扩展标志、front matter 检测、数学、TOC、高亮）与选中的 `Theme`。

```swift
public struct MarkdownParseOptions: Sendable, Hashable {
    public var enableTables: Bool
    public var enableFootnotes: Bool
    public var enableStrikethrough: Bool
    public var enableUnderline: Bool
    public var enableHighlight: Bool
    public var enableSuperscript: Bool
    public var enableQuote: Bool
    public var enableMath: Bool
    public var enableInlineMath: Bool
    public var enableTOC: Bool
    public var templateName: String
    // ……以及 MarkdownParser 遵循的其余标志
}
```

v1 不做增量解析；每次渲染都重新分析整个文档，步骤 5 的防抖保证交互式编辑的响应性。

## 5. 步骤 1 —— 解析为元素树

依赖：Apple 的 `swift-markdown` 包处理 CommonMark 与 GFM 块，Yams 处理 YAML front matter。

`MarkdownParser.parseDocument(_:options:)` 先做保持行号的前处理，使 `DocumentAnchor.line` 始终指向源文档中的行，然后遍历 `swift-markdown` 的 `Document`：

- **Front matter** 由 Yams 提取并从正文中置空；解析出的值成为开头的 `.frontMatter` 元素。
- **脚注** 不属于 `swift-markdown`；定义行被置空，`[^id]` 引用被改写为带编号的锚点链接。
- **数学区间**（`\[…\]`、`\(…\)`、`$$…$$`，以及启用时的 `$…$`）被改写为围栏式 `math`/`math-inline` 代码块，并维护行映射，使锚点仍指向源码行。
- **内联扩展**（下划线、高亮、上标、引语）在解析前用哨兵字符标记，在内联转换时恢复。
- **自动链接** 会被包裹，使 `swift-markdown` 识别裸 URL；按偏好的要求也可转义词内强调。

```swift
public func parseDocument(_ text: String, options: MarkdownParseOptions) -> ParsedDocument {
    let body = preprocess(text, options: options)   // 保持行号
    let document = Document(parsing: body)
    var elements: [MarkdownElement] = []
    var anchors: [DocumentAnchor] = []
    for block in document.blockChildren {
        if let element = convertBlock(block, path: [elements.count], anchors: &anchors) {
            elements.append(element)
        }
    }
    return ParsedDocument(elements: elements, anchors: anchors)
}
```

- 在主 actor 上、于防抖窗口内同步运行（RFC-001 §8）；输入与输出都是 `Sendable` 值。
- `ParsedDocument` 携带元素树与有序滚动锚点；不做任何 UI 工作。
- 错误以渲染状态（`RenderService.lastError`）暴露，绝不穿透视图层级抛出。
- **HTML 输出契约**：测试套件为每一种受支持的扩展固定 HTML 输出，因此改变导出标记的前处理改动会先让测试失败，而不会悄然发布。

## 6. 步骤 2 —— 元素树与锚点

`MarkdownElement` 是本应用自有的、与呈现无关的树，由解析器产出，`AttributedRenderer` 与 `Renderer` 共同消费：

```swift
public enum MarkdownElement: Sendable, Hashable {
    case heading(level: Int, text: String)
    case paragraph([InlineElement])
    case codeBlock(language: String?, code: String)
    case blockQuote([MarkdownElement])
    case unorderedList([ListItem])
    case orderedList([ListItem])
    case table(TableData)
    case thematicBreak
    case rawHTML(String)
    case image(url: String?, alt: String)
    case taskList([ListItem])
    case tableOfContents([TOCItem])
    case footnotes([FootnoteItem])
    case frontMatter(title: String?, entries: [FrontMatterEntry])
}
```

内联内容是一个平行枚举（`text`、`emphasis`、`strong`、`code`、`link`、`strikethrough`、`image`、`underline`、`highlight`、`superscript`、`quote`、`lineBreak`、`inlineHTML`），使文本片段无需重新解析即可组合。

每个块与列表项在遍历时还会发出一个 `DocumentAnchor`：

```swift
public struct DocumentAnchor: Sendable, Hashable {
    public var path: AnchorPath    // 元素树中的子索引路径
    public var line: Int           // 源文档中的 1 基行号
}
```

- 遍历器是纯函数：`swift-markdown Document → ParsedDocument`，无副作用，可独立单元测试。
- 锚点是稠密的（每个块/列表项一个）且有序，因此编辑器与预览测量的是**同一个**序列，可 1:1 配对用于滚动同步（RFC-001 §5）。
- 对扩展敏感的解析（表格、脚注、Mermaid 围栏、数学区间、TOC、任务列表）在此处完成，由 `MarkdownParseOptions` 门控。

## 7. 步骤 3 —— 原生预览

默认预览路径把元素树渲染为一个 `NSAttributedString`，并显示在只读 TextKit 2 文本表面上：

```
[MarkdownElement] ──► AttributedRenderer ──► NSAttributedString
                              │
                              ├─► MarkdownPreviewSurface（TextKit 2，可选中、
                              │     ⌘A、复制为 HTML、可测量锚点）
                              └─► PreviewWebBlockView（WKWebView）覆盖层：
                                  表格与 MathJax 公式
```

```swift
struct MarkdownPreviewSurface: NSViewRepresentable {
    let elements: [MarkdownElement]
    var anchors: [DocumentAnchor] = []
    let theme: Theme
    // ……
}
```

- 标题、段落、列表、引用、代码、分隔线与 front matter 由 `AttributedRenderer` 生成带段落样式的属性化文本。
- 表格与数学公式无法由 TextKit 排版，因此渲染器为它们预留占位附件；`MarkdownPreviewSurface` 用 `PreviewWebBlockView` 覆盖该占位，并把 WebKit 测得的真实高度写回附件，使周围文本按真实尺寸回流。
- 网页视图会被池化，且只在接近可视区域时创建，因为每个网页视图都是一个网页内容进程。
- 图片以 `NSTextAttachment` 嵌入；锚点直接从文本布局测量，从而与编辑器的锚点保持配对。
- 纯 SwiftUI 元素树 `MarkdownView` 可在关闭「Text Surface」偏好时渲染同一份 `[MarkdownElement]` 作为回退路径；它不是默认路径。

## 8. 步骤 4 —— 主题

`Theme` 是 `Sendable` 的 Swift 值——配色与代码 token 调色板——是两条预览路径与导出 CSS 共用的唯一模型：

```swift
public struct Theme: Sendable, Hashable, Identifiable {
    public var name: String
    public var displayName: String
    public var backgroundColor: Color
    public var textColor: Color
    public var linkColor: Color
    public var codeBackgroundColor: Color
    public var codeTextColor: Color
    public var codeKeywordColor: Color
    // ……标题、引用、表格、分隔线与任务列表配色
}
```

- `AttributedRenderer` 与 `MarkdownView` 直接把主题值应用到原生预览；元素绝不硬编码外观。
- `Renderer` 把同一组值序列化为导出用的 CSS。
- 打包的 CSS 文件位于 `MacMarkDown/Resources/Styles`；用户可安装的 CSS 样式表与 `.style` 编辑主题在运行时加载。
- 深色模式跟随系统外观；用户切换明暗变体时预览随之更新。

## 9. 步骤 5 —— 更新调度

预览仅在源文本、选项或主题变化时重新渲染，由 `RenderService` 的防抖把关：

| 场景 | 延迟 | 行为 |
|------|------|------|
| 实时键入 / 粘贴（文本变更） | 300 ms | 取消待执行的工作项；调度新一轮解析；窗口内最后一次击键生效 |
| 手动渲染（⌘R、工具栏） | 0 ms（立即） | `parseNow` 绕过防抖，完整重新解析 |
| 主题 / 扩展 / 字体变更 | 0 ms（立即） | 以新选项重新渲染当前文本 |
| 开启「手动渲染」偏好 | — | 暂停实时解析，直到用户显式渲染 |

- 防抖间隔为 `Constants.defaultDebounceInterval`，由 `RenderService` 持有；新的 `scheduleRender` 会取消上一个 `DispatchWorkItem`，工作绝不堆积。
- `RenderService` 以 `@Observable` 属性发布 `elements`、`anchors` 与 `renderedHTML`，视图只在一轮渲染完成时更新。
- 解析期间预览保留上一个正常帧；`isRendering` 驱动可选的进度提示。

## 10. HTML 导出路径

同一棵元素树供给所有导出面，因此预览与导出在语义上不可能产生分歧：

```
[MarkdownElement] ──► Renderer（纯 String 构建器，生成完整文档）
                          │
                          ├─► 打包的 Default.handlebars 模板
                          ├─► Resources/Styles/*.css（或生成内联 CSS）
                          ├─► 代码高亮 CSS
                          └─► Mermaid / Graphviz / MathJax 脚本（一次）
                              │
                              ▼
                    ExportService
                     ├─► 写出 .html 文件
                     ├─► NSPasteboard（「复制 HTML」）
                     ├─► 打印
                     └─► 打印为 PDF
```

```swift
let renderer = Renderer(parser: parser, theme: theme, options: options)
let html = renderer.renderToHTML(text, title: title, inlineStyles: true)
try html.write(to: url, atomically: true, encoding: .utf8)
```

- `Renderer` 填充 `Default.handlebars` 的占位符（`titleTag`、`styleTags`、`codeHighlightCSS`、`body`、`scriptTags`）；模板不可用时回退到内联文档包装。
- Mermaid、Graphviz（Viz.js）与 MathJax 脚本每个文档只注入一次；有打包资源时直接内联，使导出可离线工作。
- 导出 HTML 由测试套件覆盖，为每一种受支持的扩展固定输出。

## 11. 测试与验证

- `MacMarkDownTests` 链接 `MacMarkDownKit`，无需宿主应用即可测试解析器、渲染器、文档、编辑器行为与滚动同步。
- HTML 导出按扩展固定：表格、脚注、front matter、TOC、任务列表、数学、代码高亮、硬换行与内联扩展。
- 原生渲染用包内夹具验证：属性化输出、锚点范围、网页块占位高度与预览表面行为。

## 12. 性能预算

| 指标 | 预算 |
|------|------|
| 解析典型万行文档 | < 60 ms |
| 构建元素 + 锚点序列 | < 20 ms |
| SwiftUI/TextKit 布局 + 首帧绘制 | 防抖窗口后 < 120 ms |
| 100 MB Markdown 文件的内存占用 | 有界；服务不跨文档持有循环引用 |
| 过期渲染取消延迟 | < 1 ms（工作项取消） |

## 13. 待决议问题

1. v2 是否支持增量 AST diff，使编辑只重渲染变更的子树？还是整文档重新解析永远在预算内？
2. 当预览与 HTML 导出的能力分叉时（例如某个仅浏览器支持的数学特性），以哪一端为准——原生预览必须与导出完全一致，还是可以呈现清晰标注的「尽力而为」子集？
3. 能否用一个共享的声明式树同时作为属性化预览与 HTML 字符串的唯一输出模型，从而消除两个渲染器重复的元素遍历？
