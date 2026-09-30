# ADR-002：使用 Apple 的 swift-markdown 作为 Markdown 解析器

## 状态

**已采纳** — 2026 年 9 月

## 背景

macOS 26 与 Swift 6.4 为 Apple 的开发生态开启了新纪元，MacMarkDown 用纯 Swift 与 SwiftUI 从零写成。在这一基础之上，解析器处于核心位置：一篇文档只需解析一次，其结果必须同时服务实时预览、滚动同步与全部导出路径，而不必为每个消费者重复解析或渲染。

这要求解析器具备以下特性：

- 生成**结构化的 Swift 原生语法树**，涵盖块级与行内内容，而不是 HTML 字符串，也不是已渲染的属性字符串。
- 是**纯 Swift** 实现，以便参与严格并发检查（`SWIFT_STRICT_CONCURRENCY = complete`）并跨 actor 传递 `Sendable` 值。
- 覆盖 **CommonMark 与 GitHub 风味 Markdown**（表格、任务列表、删除线、自动链接）。
- 有**持续的上游维护**，因为建立在它之上的文档模型会长期存在。
- 具备**可扩展性**，因为本项目支持的语法超出 CommonMark/GFM（数学公式、`[toc]`、脚注、front matter、行内扩展）。

### 解析流程

1. 编辑器上报文本变更，`RenderService` 做防抖后再解析。
2. `MarkdownParser` 先以保留行号的方式准备源文本（front matter 与脚注定义置空、数学公式与行内扩展做标记、裸 URL 加上尖括号以便识别为自动链接），再调用 `Document(parsing:options:)` 解析。
3. swift-markdown 的语法树被转换为 `[MarkdownElement]`——一棵 `Sendable`、与渲染器无关的树——并同时产出按行关联编辑器和预览滚动位置的 `DocumentAnchor`。
4. 预览层原生渲染这些元素（ADR-003）；`Renderer` 遍历同一棵元素树生成 HTML，用于导出、打印与拷贝 HTML。
5. YAML front matter 由 Yams 解析，成为以嵌套表格渲染的 `.frontMatter` 元素。

## 决定

使用 Apple 的 **swift-markdown** 作为 Markdown 解析器，通过 Swift Package Manager 声明 `swift-markdown` 包及其 `Markdown` 产品；YAML front matter 由 **Yams** 解析。

### 为什么选择 swift-markdown

- **Apple 维护的开源库**，提供 Swift 原生 API。
- **类型化语法树** — 解析产出 `Document`，其 `Markup` 节点覆盖块级与行内内容；`MarkupWalker` 让语法树遍历显式而清晰，转换层在遍历时完成节点转换。
- **CommonMark 与 GFM 扩展** — 表格、任务列表复选框、删除线与尖括号自动链接均由库直接支持。
- **Sendable 值** — 解析结果可以在 Swift 并发环境中安全地生产与消费，不存在数据竞争。
- **无 C 互操作** — 没有桥接头文件、模块映射，也没有 C 构建产物。
- **与项目范围契合** — 库的节点集合能干净地映射到 `MarkdownElement`，转换层因此保持小巧且易于测试。

### 集成方式

- 包在 `project.yml` 中声明，并链接进 `MacMarkDownKit` framework；Yams 以相同方式声明。
- `MarkdownParser` 是应用内解析的唯一入口，原生预览（`MarkdownView`/`MarkdownPreviewSurface`）与 HTML 导出器（`Renderer`）都消费它的输出。
- 解析层中不存在 C 代码、桥接头文件或模块映射。

### 解析流程图

```
源 Markdown
  → MarkdownParser（保留行号的预处理，然后 Document(parsing:options:)）
  → swift-markdown 语法树（Document / Markup）
  → [MarkdownElement] + [DocumentAnchor]
      → 预览层                 原生渲染（ADR-003）
      → Renderer               用于导出、打印与拷贝 HTML 的 HTML
YAML front matter
  → Yams
  → .frontMatter 元素（渲染为表格）
```

### CommonMark/GFM 之外的扩展

swift-markdown 对核心 Markdown 与常见 GFM 扩展建模。本项目在其外围叠加额外语法，而不是分叉库本身：

- front matter 在解析前由 Yams 提取。
- 脚注定义以保留行号的方式置空、引用转换为锚点；定义最终成为 `.footnotes` 元素。
- 数学公式片段（`\[…\]`、`\(…\)`、`$$…$$`，以及可选的 `$…$`）转换为 `math`/`math-inline` 围栏，交给 Web 块管线排版。
- 下划线、高亮、上标与引号片段用私有区哨兵字符标记，由元素转换层解析。
- `[toc]`、自动链接包装、智能标点开关与词内强调处理都作为解析选项在外围应用。

所有预处理都保留行号，因此 `DocumentAnchor.line` 始终指向源文档中的行，滚动同步保持精确。

## 备选方案

### 1. cmark-gfm（C 库）
cmark-gfm 是 GitHub 的 GFM C 实现，扩展覆盖完整。**已否决**：从 Swift 调用需要 C 互操作层，其节点树是 C 指针 API 而非 Swift 值，也无法参与 Swift 的严格并发模型（节点值不满足 `Sendable`）。项目仍需维护包装层和一套并行的 Swift 文档模型，并在解析路径上保留一段非内存安全的边界。

### 2. Ink（纯 Swift）
Ink 是 Swift 原生的 Markdown 解析器，API 友好。**已否决**：它由社区维护，扩展覆盖面较窄，也没有 Apple 背书。对于如此核心且长期存在的文档模型，Apple 维护的库所带来的更低维护风险，胜过 Ink 更轻量的优势。

### 3. 自行实现解析器
在项目内实现 CommonMark/GFM。**已否决**：规范合规是庞大且持续存在的测试负担（数千个用例），解析器工作还会挤占编辑器与预览功能的投入。基于维护良好的库构建才是更合理的分工。

### 4. 基于 NSAttributedString 的解析
把属性字符串（例如把 Markdown 导入 `NSAttributedString`）当作文档模型。**已否决**：属性字符串描述的是呈现样式片段，而不是文档结构。它没有标题、列表、表格层级可用于大纲、表格布局、滚动锚点或导出，样式决策还会混入解析环节。

## 影响

### 积极影响

- **Swift 原生文档模型** — 所有消费者都使用 `MarkdownElement` 这棵类型化、`Sendable` 的树；解析边界上没有 C 指针或字符串形式的 HTML。
- **一次解析服务所有消费者** — 同一棵树同时支撑原生预览渲染、滚动锚点与 HTML 导出，预览与导出对结构的理解不可能出现分歧。
- **严格并发** — 跨 actor 传递的值满足 `Sendable`；解析被隔离（应用中为 `@MainActor`），也可以按需放到后台 actor 上执行。
- **无 C 互操作** — 构建中没有桥接头文件或模块映射，项目保持单一语言。
- **CommonMark + GFM 覆盖** — 表格、任务列表、删除线与自动链接来自库而不是项目代码。
- **活跃维护** — swift-markdown 由 Apple 维护，并随工具链更新。

### 消极影响

- **不含 HTML 渲染器** — 库产出语法树而非 HTML。`Renderer` 遍历 `MarkdownElement` 生成用于导出与打印的 HTML，这部分由项目自行维护。
- **扩展需要预处理** — 脚注、数学公式、`[toc]`、front matter 与行内扩展都由解析前后的项目侧处理完成；每新增一种扩展都必须遵守保留行号的约定。
- **多一个依赖** — YAML front matter 需要 Yams，因为 swift-markdown 不解析 front matter。
- **发布节奏** — swift-markdown 跟随 Apple 的发布节奏，紧急修复的交付可能慢于社区项目。
- **API 演进** — 库仍在演进；主要版本升级需要检查 `Document(parsing:)`、`ParseOptions` 与节点 API。

### 风险

- 改变行数的预处理（目前只有数学公式，且带有行号映射）会破坏滚动锚点的准确性。新增的转换型扩展必须保留行号，或自带映射。
- swift-markdown 的节点 API 与 GFM 行为可能在版本之间变化；`MarkdownParser` 中的转换层是唯一需要适配的地方。

## 参考

- Apple swift-markdown：https://github.com/apple/swift-markdown
- CommonMark 规范：https://spec.commonmark.org/
- GitHub 风味 Markdown 规范：https://github.github.com/gfm/
- Yams：https://github.com/jpsim/Yams
- 应用代码：`MacMarkDown/Markdown/MarkdownParser.swift`、`MacMarkDown/Markdown/MarkdownElement.swift`、`MacMarkDown/Document/FrontMatter.swift`、`project.yml`
