# ADR-003：在 TextKit 2 文本表面上实现原生预览，表格与公式使用 WebKit 叠加块

## 状态

**已采纳** — 2026 年 9 月

**修订** — 2026 年 9 月：默认预览表面是只读的 TextKit 2 文本视图（`MarkdownPreviewSurface`），显示由 `AttributedRenderer` 生成的单个 `NSAttributedString`，而非 SwiftUI 元素树。渲染为单个属性字符串使预览具备整篇选择、⌘A 与拷贝为 HTML 的能力，并让滚动同步锚点直接由 `NSTextLayoutManager` 测量，而不再依赖 `GeometryReader` 探针。元素树仍保留在 `preferences.previewUsesTextSurface` 之后，其默认值为 `true`。

**修订** — 2026 年 9 月：文本表面中的表格与 TeX 公式由 WebKit 作为按尺寸布局的叠加块渲染。`AttributedRenderer` 为每个块预留一个占位附件，`MarkdownPreviewSurface` 将一个透明、不可滚动的 `PreviewWebBlockView` 定位在其上；页面通过 `height` 脚本消息回传高度，宿主据此调整占位符，使块之后的内容不会落在其下方。表格使用与 HTML 导出相同的 `<table>` 标记和内置样式表；公式由内置的 MathJax 3 排版，预览因此可离线工作。文本表面中的图表围栏仍按代码显示。

## 背景

macOS 26 与 Swift 6.4 为 Apple 的开发生态开启了新纪元：SwiftUI、Observation、TextKit 2 与 Swift 并发已经成熟到足以承载一个完整的写作工具，因此 MacMarkDown 用纯 Swift 与 SwiftUI 从零写成。预览面板最能体现这一决定。解析层（ADR-002）已经产出带类型的 `[MarkdownElement]` 树，而把 HTML 放进 `WKWebView` 会为应用已经以 Swift 值形式拥有的内容再引入第二套渲染引擎——独立的 Web 内容进程、每次击键都要付出的 IPC、DOM/CSSOM/JavaScript 运行时、脱离 Swift 类型的 CSS 主题，以及更有限的无障碍支持。

预览必须满足以下要求：

- **整篇文本交互** —— 作者会选中预览并拷贝；⌘A 与拷贝为 HTML 的行为应与文本面板一致。
- **与真实布局一致的滚动同步** —— 锚点位置必须来自用户实际看到的布局，而不是叠加其上的探针。
- **Swift 主题** —— 预览外观来自 `Theme` 值（ADR-004），而不是运行时拼接的 CSS 字符串。
- **默认离线** —— 公式不依赖网络即可渲染。
- **块的单一事实来源** —— 预览中的表格或公式必须与导出的 HTML 保持一致。

有两类块无法用纯文本布局处理。TextKit 2 完全不支持 `NSTextBlock`/`NSTextTable`，而在 macOS 27 上，即便使用 TextKit 1 的 `NSTextView`，表格单元格也会被当作普通制表符段落排版，各列无法排齐。TeX 公式需要 JavaScript 版 MathJax。纯文本表格网格同样不可行：系统等宽字体的拉丁字符步进为 0.618 em，而 CJK 字符为全宽 em，因此一个换行的中文单元格会使其后的所有列错位。用 Core Text 与 Core Graphics 把表格绘制成附件图片的尝试也被放弃：栅格必须与面板宽度完全一致，否则会被 TextKit 2 裁剪；其文本无法选择；这实际上等于再构建一个排版引擎。

## 决定

预览采用原生渲染。解析后的元素树转换为单个属性字符串，在只读 TextKit 2 文本表面中显示；仅对 TextKit 无法排版的两种块使用 WebKit 按尺寸叠加。

### 流程

```
Markdown 源文本
  → MarkdownParser（swift-markdown，ADR-002）
  → [MarkdownElement]
  → AttributedRenderer.render(_:)
        单个 NSAttributedString：块级样式、行内特征、图片附件
        表格与公式的按尺寸占位符
  → MarkdownPreviewSurface
        只读 MarkdownTextView（TextKit 2）
        表格与公式的 PreviewWebBlockView 叠加块
```

### 文本表面

`AttributedRenderer` 只遍历一次元素树，并向单个 `NSMutableAttributedString` 追加内容：标题、段落、有序/无序/任务列表、引用块、围栏与行内代码、分隔线、脚注、Front Matter、raw HTML 占位符，以及行内特征（强调、加粗、删除线、下划线、高亮、上标）。图片以 `NSTextAttachment` 嵌入。

`MarkdownPreviewSurface` 是一个 `NSViewRepresentable`，包装 `NSScrollView` 与只读的 `MarkdownTextView`——与编辑器相同的 TextKit 2 文本视图。只有当影响渲染的输入发生变化时（`RenderInputs` 实现 `Equatable`）才会重新渲染，因此编辑器中的光标移动不会替换文本存储，也不会使布局失效。

`DocumentView` 中 `usesTextSurface` 的默认值为 `true`；设置 → 渲染以“Selectable Preview (Text Surface)”暴露同一个开关。

### 表格

`AttributedRenderer` 为每个 `.table` 元素生成按尺寸的占位符，并记录 `TableBlock`（锚点路径、占位范围、`TableData`、附件）。`MarkdownPreviewSurface` 将 `PreviewWebBlockView` 定位在占位符上并加载 `TablePreviewHTML.page(markup:theme:zoom:)`。标记来自与 HTML 导出共享的 `TablePreviewHTML.tableMarkup`，页面使用同一份内置样式表，因此预览表格与导出表格不会出现差异。

页面通过 `height` 脚本消息回传内容高度。协调器将测得高度写入附件的 bounds，使占位范围失效并重新排版，表格之后的内容因此从表格下方开始。测得高度会回放到后续渲染中，避免布局跳回估算值。`PreviewWebBlockView` 通过小型空闲池（最多 2 个）复用，且只为与视口相交（外加一个视口边距）的块创建；每个实例都是一个 Web 内容进程，包含大量块的文档不应一次性启动全部实例。

### 公式

解析层在构建元素树之前将 TeX 片段转换为围栏 `math`/`math-inline` 块（`MarkdownParser.applyMath`）。在 TeX 数学开启时识别 `\\[ … \\]`、`\\( … \\)`、`\[ … \]`、`\( … \)` 与 `$$ … $$`，在内联美元符号选项开启时额外识别 `$ … $`。围栏代码与行内代码片段会被跳过，未闭合的片段保持书写形式。

`AttributedRenderer` 为每个公式块生成与表格相同的占位符；公式由 `MathPreviewHTML.page(tex:isDisplay:theme:zoom:)` 中的内置 MathJax 3 排版，仅在内置资源缺失时回退到 CDN。占位附件携带 TeX 源文本，因此拷贝选区得到的是公式而不是占位字符。

### 图表

Mermaid、Graphviz 及其他图表围栏在文本表面中按代码块显示；该表面只有表格与公式使用 Web 叠加块。在相应偏好设置开启时，元素树回退路径仍可通过 `WebBlockView` 渲染图表围栏。

### 元素树回退路径

`MarkdownView` 将同一棵 `[MarkdownElement]` 树渲染为 SwiftUI 视图（在开启时使用 `WebBlockView` 渲染公式与图表围栏）。它保留在 `preferences.previewUsesTextSurface` 之后，并与文本表面共享解析输出、`Theme` 值与滚动同步锚点。

### 导出

HTML 导出与实时预览相互独立。`Renderer` 将元素树序列化为完整 HTML 文档，用于拷贝 HTML、导出文件与打印。它复用 `TablePreviewHTML.tableMarkup`、内置样式表与内置 MathJax 资源，这就是预览块与其导出形式保持一致的原因——预览本身并不经过导出路径。

### 滚动同步

`MarkdownPreviewSurface.Coordinator` 使用 `NSTextLayoutManager.typographicBounds(in:)` 测量每个锚点并上报 Y 坐标；滚动同步服务在编辑器与预览的锚点之间插值。当 WebKit 回传块高度时，占位符会伸缩，协调器因此在布局稳定后重新上报度量与锚点，避免两个面板逐渐错位。

## 备选方案

### 1. 在 WKWebView 中承载 HTML 预览

解析 → 生成 HTML 字符串 → `WKWebView.loadHTMLString`。**已否决。** 它引入第二套渲染引擎与独立的 Web 内容进程，每次预览更新都要付出 IPC 代价，为文本文档携带 DOM/CSSOM/JavaScript 运行时，滚动同步需要 JavaScript，主题变为 Swift 类型系统之外的 CSS 字符串，扩大处理不可信 Markdown 的攻击面，限制无障碍集成，打印结果还可能与屏幕显示不同。

### 2. 仅使用 SwiftUI 元素树

用 SwiftUI 视图渲染每个元素。**保留为回退路径，而非默认方案。** `Text` 视图不提供 ⌘A 整篇选择，拷贝为 HTML 需要单独实现，为每个元素构建视图比向单个字符串追加属性更重，滚动锚点也只能来自 `GeometryReader` 探针而非真实文本布局。

### 3. 使用 TextKit 原生表格

用 `NSTextTable`/`NSTextBlock`，或在 TextKit 1 文本视图中用制表符段落排版表格。**已否决。** TextKit 2 不支持表格 API，TextKit 1 路径无法让各列排齐，而纯文本网格在 CJK 与拉丁混排时会失效：系统等宽字体的拉丁步进为 0.618 em，而 CJK 字符为全宽 em。

### 4. 使用 Core Text 手绘表格

将每个表格栅格化或绘制为附件图片。**已否决。** 绘制必须精确跟随面板宽度，否则会被裁剪；表格文本无法选择；该方案等于重建排版引擎。

### 5. 基于 PDF 的预览

将文档渲染为 PDF 并在 `PDFView` 中显示。**已否决。** PDF 输出不具备文本表面那样的可重排与可选择能力，需要大量 Core Graphics 代码，也不适合实时预览工作流。

## 影响

### 积极影响

- **整篇选择** —— ⌘A、拖拽选择与拷贝为 HTML 的行为与文本面板一致；占位附件会把表格或 TeX 内容带入拷贝路径。
- **与布局一致的锚点** —— 滚动同步锚点位置来自 TextKit 2 自身的布局，不会与渲染文本产生偏移。
- **原生无障碍与外观** —— 该表面是真正的文本视图；VoiceOver 与系统外观无需 Web 无障碍桥接即可工作。
- **稳定的日常开销** —— 每次输入变化只渲染一次属性字符串；相同的渲染会被完全跳过，点击光标不会重新排版预览。
- **有界的 Web 使用** —— 只有视口附近的表格与公式持有 Web 视图，空闲视图进入池中复用。
- **一致的导出** —— 预览与 `Renderer` 共享表格标记、样式表与 MathJax 资源。
- **离线可用** —— 内置 MathJax 无需网络即可排版公式。

### 消极影响

- **需要维护两条表面** —— 文本表面是默认路径，SwiftUI 元素树是回退路径；二者使用同一元素树与主题，但涉及共同行为的改动需要在两处完成。
- **并非所有块都无 WebView** —— 每个可见的表格或公式块都是一个 Web 内容进程，其内部文本由 WebKit 选择，而非周边 TextKit 选区。
- **高度估算** —— 在页面回传实测高度之前，块使用估算高度；实测高度会被回放，以保持后续渲染稳定。
- **图表围栏按代码显示** —— Mermaid 与 Graphviz 围栏在文本表面中不会渲染为图表，而是显示为代码块。

### 风险

- **超大文档** —— 整篇文档是一个属性字符串。缓解措施：跳过未变化的渲染、TextKit 2 基于视口的布局、按需创建块视图。
- **屏幕上存在大量表格或公式** —— 每个靠近视口的块都会持有 Web 内容进程。缓解措施：空闲池、一个视口的边距、块滚离后回收；活动视图数量由可见内容而非文档规模决定。
- **附件支撑的拷贝** —— 拷贝包含表格或公式的选区依赖附件携带其内容。`AttributedRendererTests`、`TablePreviewHTMLTests` 与 `MathPreviewHTMLTests` 覆盖了这一点。

## 参考

- `MarkdownPreviewSurface` — MacMarkDown/UI/macOS/Preview/MarkdownPreviewSurface.swift
- `PreviewWebBlockView` — MacMarkDown/UI/macOS/Preview/PreviewWebBlockView.swift
- `AttributedRenderer` — MacMarkDown/Services/Preview/AttributedRenderer.swift
- 表格与公式页面 — MacMarkDown/Services/Preview/TablePreviewHTML.swift、MathPreviewHTML.swift
- HTML 导出 — MacMarkDown/Services/Preview/Renderer.swift
- Apple swift-markdown MarkupWalker — https://github.com/apple/swift-markdown/blob/main/Sources/Markdown/MarkupWalker.swift
- Apple TextKit 2 — https://developer.apple.com/documentation/appkit/textkit
- MathJax — https://www.mathjax.org
