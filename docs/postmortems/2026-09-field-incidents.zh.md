# 现场事故报告 — 2026 年 9 月

**项目**：MacMarkDown  
**报告日期**：2026-09-15  
**报告类型**：前瞻性风险评估（实施前与实施初期）  
**状态**：动态风险登记册  
**作者**：MacMarkDown 核心团队  

---

## 1. 执行摘要

macOS 26 与 Swift 6.4 为 Apple 的开发生态开启了新纪元：SwiftUI、Observation、TextKit 2 与 Swift 并发已经成熟到足以承载一个完整的写作工具，MacMarkDown 正是用纯 Swift 与 SwiftUI 为这个新纪元从零写成。本文档是在首批实现迭代之前与进行之中写下的前瞻性风险评估，记录构建本应用时最可能出现的现场事故；每起事故都给出严重程度、可能性、受影响组件，以及在代码库中已经设计、并尽可能验证过的具体缓解措施。

**总体风险等级**：中等  
**缓解信心**：高（每项缓解措施都对应到带测试的组件）

## 2. 事故目录

### 事故 1：自定义 TextKit 2 编辑器是复杂度最高的组件

| 字段     | 值                                       |
|----------|------------------------------------------|
| ID       | FI-2026-001                              |
| 严重程度 | 高                                       |
| 可能性   | 确定（设计约束所致）                     |
| 组件     | `MarkdownTextView` / `MarkdownEditorView` |
| 状态     | ✅ 缓解措施已落地                        |

#### 描述

SwiftUI 的 `TextEditor` 只暴露纯文本绑定，无法应用 Markdown 专用属性、掌控视口或拦截文件拖放。因此，一个懂 Markdown 的写作界面必须拥有自己的 TextKit 2 文本栈：`MarkdownTextView` 持有 `NSTextContentStorage`、`MarkdownTextLayoutManager` 与 `NSTextContainer`，并在其上实现显示、选择、输入法、拖放与智能编辑。这是整个应用体量最大、也最容易出错的组件；选择或文本布局中的一个细微缺陷会直接落在核心写作体验上。

**影响**：如果这个自定义视图脆弱或缓慢，整个产品就会显得脆弱或缓慢 — 其他部分再精致，也无法弥补一个会丢按键或在滚动时卡顿的编辑器。

#### 缓解措施

**主要策略：用窄而可测试的接口隔离专用视图**

编辑器被隔离在 `MarkdownEditorView`（`NSViewRepresentable`）与 `EditorTextViewHost` 协议之后。智能编辑辅助逻辑在测试中可以对普通 `NSTextView` 运行，在应用里则对 `MarkdownTextView` 运行，因此无需窗口即可验证行为。

```swift
@MainActor
final class MarkdownTextView: NSView {
    let textContentStorage = NSTextContentStorage()
    let textLayoutManager: NSTextLayoutManager = MarkdownTextLayoutManager()
    let textContainer = NSTextContainer()
}
```

**视口纪律**：只为可见的 `NSTextLayoutFragment` 创建片段，由 `NSTextViewportLayoutController` 驱动；仅可见区域参与布局并常驻内存，因此长文档和短文档滚动起来一样轻快。

**语法高亮不进入视图**：`MarkdownSyntaxHighlighter` 依据选中的 `EditorTheme` 为文本存储着色，高亮逻辑因此是一个带独立测试的纯转换器。

**测试覆盖**：`MarkdownTextViewTests`、`MarkdownTextViewHostTests`、`MarkdownTextViewStandardEditingTests`、`MarkdownEditorCoordinatorTests`、`EditorSmartEditingTests`、`SyntaxHighlighterTests`。

#### 时间线

| 里程碑                                                          | 目标日期 |
|-----------------------------------------------------------------|----------|
| 文本栈原型（`NSTextContentStorage` → 布局管理器 → 容器）         | Sprint 1 |
| 视口片段缓存                                                    | Sprint 2 |
| 宿主与协调器测试套件                                            | Sprint 2 |
| 选择 / 输入法 / 拖放加固                                        | Sprint 3 |
| 生产发布                                                        | Sprint 5 |

---

### 事故 2：表格、数学公式与中日韩排版下的预览保真度

| 字段     | 值                                            |
|----------|-----------------------------------------------|
| ID       | FI-2026-002                                   |
| 严重程度 | 中等                                          |
| 可能性   | 可能                                          |
| 组件     | `AttributedRenderer` / `MarkdownView` / `PreviewWebBlockView` |
| 状态     | ✅ 缓解措施已落地                             |

#### 描述

完全原生的预览无法呈现 Markdown 文档可能包含的一切。TextKit 2 没有表格布局能力，也没有 TeX 排版引擎，表格与公式只能退化为近似效果；中日韩字体家族通常不提供斜体字面，中文的强调可能悄悄显示为直立字形，而拉丁文本却会倾斜；而把整个预览交给 Web 视图，又会放弃原生优先、SwiftUI 优先的渲染模型。每一处缺口都会以"预览与导出 HTML 不一致"的形式被用户看见。

**影响**：包含表格、公式或中日韩强调的文档渲染不正确，或者在预览与导出之间不一致 — 这恰恰是技术写作工具最受检验的内容。

#### 缓解措施

**策略：原生优先，WebKit 只做手术刀**

1. **表格与公式转为占位符。** `AttributedRenderer` 为每个表格和公式预留一个带尺寸的 `NSTextAttachment`。`PreviewWebBlockView`（`WKWebView`）把真实内容绘制在占位符之上，并通过脚本消息回报内容高度，文本布局据此预留精确空间。表格与公式的 HTML 来自 `TablePreviewHTML` 与 `MathPreviewHTML`：它们复用导出用的标记与随包分发的 MathJax，因此预览与导出共享同一份事实来源。

```swift
@MainActor
final class PreviewWebBlockView: NSView {
    private let webView: WKWebView
    var onHeightChange: ((CGFloat) -> Void)?
}
```

2. **WebKit 仅限真正需要的块。** 标题、段落、列表、引用、代码、图片等其余元素全部由 `MarkdownView` 或 `AttributedRenderer` 原生绘制。图表围栏通过 `WebBlockView` 走同一套 Web 块机制。

3. **中日韩强调使用合成倾斜。** 当某个字体家族没有斜体字面时，`FontResolver.syntheticItalic` 对它做水平剪切（约 12°，与浏览器行为一致）。SwiftUI 预览（`MarkdownView`）与富文本路径（`AttributedRenderer`）都会应用它，因此强调在任何地方看起来都一致，也不会影响断行。

4. **代码高亮是原生的。** `CodeSyntaxHighlighter` 用带缓存的正则表达式完成词法切分，`CodeHighlightTheme` 提供配色；预览与导出都不会加载 JavaScript 高亮器。

5. **测试锁定行为**：`AttributedRendererTests`、`TablePreviewHTMLTests`、`MathPreviewHTMLTests`、`InlineStyleRenderingTests`、`PreviewRenderingTests`、`PreviewSupportTests`。

#### 时间线

| 里程碑                               | 目标日期 |
|--------------------------------------|----------|
| 块级元素的原生渲染器                 | Sprint 1 |
| 带高度回报的表格 / 公式 Web 块       | Sprint 2 |
| 中日韩强调的合成倾斜                 | Sprint 2 |
| 图表 Web 块                          | Sprint 3 |
| 预览 / 导出一致性测试套件            | Sprint 3 |

---

### 事故 3：高度异构内容下的同步滚动精度

| 字段     | 值                                            |
|----------|-----------------------------------------------|
| ID       | FI-2026-003                                   |
| 严重程度 | 中等                                          |
| 可能性   | 可能                                          |
| 组件     | `ScrollSyncService` / `ScrollSyncCoordinator` |
| 状态     | ✅ 缓解措施已落地                             |

#### 描述

编辑器与预览以完全不同的比例展开同一份源文本：十行代码块在编辑器里可能比预览里矮，图片或表格占据预览像素却没有对应的编辑器高度，而预览中惰性测量的高度要到首次布局之后才会稳定。因此，朴素的行到像素比例会漂移；如果已测量的高度在滚动中途发生变化，预览还可能跳变甚至反向。

**影响**：在长文档中，预览会落在错误的段落上，这时的同步滚动比完全不同步更糟。

#### 缓解措施

**策略：密集锚点加区间插值**

1. `MarkdownParser` 为每个块级元素和列表项按文档顺序生成一个 `DocumentAnchor`。两侧窗格测量同一份有序锚点列表 — 编辑器从文本布局测量，预览从渲染表面测量 — 因此两个数组按下标一一对应。

2. 滚动偏移表示为它所处两个锚点之间的百分比，并映射到另一窗格中对应的区间；越过最后一个有效锚点后，映射会插值到文档的真实结尾。

3. 在实时滚动手势期间，协调器冻结映射输入（锚点与内容高度），只在手势结束后重新测量，因此正在稳定的布局不会从用户指尖下挪走目标。

4. 启用双向同步时，反向映射是正向映射的精确逆（用二分法求得），并抑制程序化滚动产生的回声，两个窗格因此不会互相拉扯。

```swift
public func previewOffset(forEditorOffset editorY: CGFloat,
                          editorContentHeight: CGFloat,
                          editorVisibleHeight: CGFloat,
                          previewContentHeight: CGFloat,
                          previewVisibleHeight: CGFloat) -> CGFloat
```

**性能目标**：同步滚动延迟低于 30ms（60fps 下的两帧），由 `ScrollSyncServiceTests` 与 `ScrollSyncCoordinatorTests` 验证。

#### 时间线

| 里程碑                               | 目标日期 |
|--------------------------------------|----------|
| 解析器输出密集锚点                   | Sprint 1 |
| 区间插值与边缘渐变                   | Sprint 2 |
| 实时手势冻结                         | Sprint 2 |
| 双向逆映射与回声抑制                 | Sprint 3 |
| 长文档测试                           | Sprint 3 |

---

### 事故 4：大文档性能与内存抖动

| 字段     | 值                                            |
|----------|-----------------------------------------------|
| ID       | FI-2026-004                                   |
| 严重程度 | 高                                            |
| 可能性   | 可能（约 200KB 以上的文档）                   |
| 组件     | `RenderService` / `MarkdownTextView` / `@Observable` 状态 |
| 状态     | ✅ 缓解措施已落地                             |

#### 描述

每一次经过防抖的编辑都会让 `RenderService` 重新解析整个文档，重建 `[MarkdownElement]`、锚点数组与富文本预览。随后 `@Observable` 会通知这些属性的所有消费方。如果编辑器为整个文档保留布局片段，或者滚动位置变化会让预览元素树失效，那么长篇文档就会在每次按键和每个滚动刻度上付出全部代价 — 表现为输入延迟、卡顿与内存增长。

**影响**：输入延迟与滚动卡顿会让大文件（小说章节、技术书籍）难以甚至无法编辑；无上限的片段保留则会把滚动变成持续的内存抖动。

#### 缓解措施

**策略：防抖、仅视口布局、可相等比较的视图**

1. **防抖渲染。** `RenderService.scheduleRender` 等待 300ms（`Constants.defaultDebounceInterval`），并取消进行中的工作；新的按键会重新开始计时。

2. **仅视口布局。** `MarkdownTextView` 通过 `NSTextViewportLayoutController` 只为可见区域布局并缓存片段，文档其余部分留在文本存储中。

3. **渲染输入可相等比较。** `MarkdownView` 实现 `Equatable` 并以 `.equatable()` 应用，因此只有滚动位置变化时，父级 body 会重新求值，但元素树不会重建。

4. **高度保持缓存。** `AttributedRenderer` 保存 WebKit 最近一次回报的每个表格与公式高度（`tableHeights`、`mathHeights`），重新渲染时布局不会跳回估算值。

5. **带测试与基准的性能预算。**

| 文档大小   | 最大按键延迟   | 最大滚动延迟 | 最大预览更新 |
|------------|----------------|--------------|--------------|
| < 50KB     | 16ms（1 帧）   | 16ms         | 100ms        |
| 50–200KB   | 33ms（2 帧）   | 33ms         | 300ms        |
| 200KB–1MB  | 50ms（3 帧）   | 50ms         | 500ms        |
| > 1MB      | 100ms（降级）  | 100ms        | 1000ms       |

#### 时间线

| 里程碑                               | 目标日期 |
|--------------------------------------|----------|
| 防抖渲染调度                         | Sprint 1 |
| 视口片段缓存                         | Sprint 1 |
| 可相等比较的预览输入                 | Sprint 2 |
| Web 块高度缓存                       | Sprint 2 |
| 大文档基准测试套件                   | Sprint 3 |
| 200KB 以上文档的优化                 | Sprint 4 |

---

### 事故 5：自动保存与未保存改动的数据安全

| 字段     | 值                                            |
|----------|-----------------------------------------------|
| ID       | FI-2026-005                                   |
| 严重程度 | 高                                            |
| 可能性   | 可能                                          |
| 组件     | `MarkdownDocument` / `DocumentSession` / `UnsavedChangesGuard` |
| 状态     | ✅ 缓解措施已落地                             |

#### 描述

桌面编辑器在两次保存之间掌握着用户文件的唯一副本。有三种情况会造成丢失或损坏：退出或崩溃时丢失尚未落盘的改动；自动保存覆盖了已被其他程序修改的文件；由于 SwiftUI 弹窗是异步的，关闭/退出确认无法同步作答。多窗口编辑还带来第四种：守卫或命令作用到了错误窗口的文档上。

**影响**：哪怕丢失用户一段文字，也是写作工具能犯下的最严重错误 — 远比任何渲染瑕疵更糟。

#### 缓解措施

**策略：原子写入、显式自动保存、同步守卫**

1. `MarkdownDocument.save(to:checkConflict:)` 采用原子写入；手动保存时会把磁盘内容与最近一次保存的文本比对，发现外部改动就抛出 `SaveError.fileChangedExternally`，而不是直接覆盖。

2. 自动保存由用户主动开启，并用可取消的 `Task` 做防抖；应用退出时 `DocumentSession.flushAutosave()` 会落盘待处理的改动，防抖窗口因此绝不会成为"已保存"与"已丢失"的分界。

3. `UnsavedChangesGuard` 作为窗口委托同步处理关闭窗口与退出应用的确认；`DocumentSession` 保存对关键文档的引用，守卫因此总能检查正确的缓冲区。

4. Finder 打开与 URL scheme 打开由 `DocumentOpenQueue` 串行化；`RecentDocumentsStore` 会清理已失效的最近文档，缺失的文件不会卡住启动流程。

5. **测试**：`MarkdownDocumentAutosaveTests`、`UnsavedChangesGuardTests`、`DocumentSessionTests`、`DocumentOpenQueueTests`、`RecentDocumentsStoreTests`、`ScriptableDocumentTests`。

#### 时间线

| 里程碑                               | 目标日期 |
|--------------------------------------|----------|
| 带冲突检测的原子保存                 | Sprint 1 |
| 关闭 / 退出守卫                      | Sprint 1 |
| 可选开启的防抖自动保存               | Sprint 2 |
| 退出时落盘与打开队列                 | Sprint 2 |
| 数据安全测试加固                     | Sprint 3 |

---

## 3. 风险矩阵

| ID  | 事故                              | 严重程度 | 可能性 | 风险等级   | 缓解信心 |
|-----|-----------------------------------|----------|--------|------------|----------|
| 001 | 自定义 TextKit 2 编辑器复杂度     | 高       | 确定   | 🔴 高      | 高       |
| 002 | 预览保真度（表格 / 公式 / 中日韩）| 中等     | 可能   | 🟡 中等    | 高       |
| 003 | 同步滚动精度                      | 中等     | 可能   | 🟡 中等    | 高       |
| 004 | 大文档性能与内存                  | 高       | 可能   | 🔴 高      | 高       |
| 005 | 自动保存与未保存改动安全          | 高       | 可能   | 🟠 偏高    | 高       |

## 4. 跨事故依赖关系

```
事故 1（编辑器复杂度）──┐
                        ├──▶ 共同约束：仅视口布局
事故 4（大文档）      ──┘

事故 2（预览保真度）──▶ 块高度 ──▶ 事故 3（同步滚动）

事故 5（数据安全）── 相互独立 ──▶ 文档层，在 Sprint 1 落地
```

## 5. 实施顺序

基于依赖关系与关键程度：

1. **Sprint 1**：事故 4 的基础（防抖渲染、视口布局）与事故 5（原子保存、关闭/退出守卫）
2. **Sprint 2**：事故 1 的主要措施（文本栈、片段缓存）与事故 3 的主要措施（密集锚点、区间插值）
3. **Sprint 3**：事故 2 的缓解措施（Web 块、中日韩合成倾斜）与事故 1 的加固（选择 / 输入法 / 拖放）
4. **Sprint 4**：针对事故 1、3、4 的横切性能优化
5. **Sprint 5**：集成测试、边界情况与发布准备

## 6. 监控与告警

在应用进入 Beta 测试后，我们将监控：

| 指标                        | 阈值        | 告警操作                |
|-----------------------------|-------------|-------------------------|
| 按键到显示延迟              | > 50ms      | 启动性能问题调查        |
| 同步滚动偏移量              | > 5 行      | 启动同步滚动问题调查    |
| 预览渲染时间                | > 500ms     | 启动预览问题调查        |
| 内存使用（> 500KB 文件）    | > 200MB     | 启动内存问题调查        |
| 代码高亮时间                | > 100ms     | 启动高亮问题调查        |

## 7. 经验预期

这些是我们预期实现过程会验证的经验；它们将随真实测量结果进一步修订：

1. **纯 `TextEditor` 不是 Markdown 写作界面。** 自己掌握 TextKit 2 文本栈是一流编辑器的必要代价 — 而且必须把它隔离在窄协议之后，才能测试。
2. **Observation 需要可相等比较的输入。** 没有 `Equatable` 视图输入时，一个滚动刻度会让远超滚动位置的东西失效。
3. **WebKit 最大的价值在于做手术刀。** 表格、公式与图表值得用 Web 视图；其余内容原生绘制更便宜也更一致。
4. **密集锚点把同步滚动变成映射问题**，而不是猜谜；启发式应该是兜底，而不是地基。
5. **数据安全属于 Sprint 1。** 原子写入与关闭/退出守卫在早期加入代价很低，等用户把工作托付给应用之后再补则极其昂贵。
6. **性能预算必须从第一个 Sprint 开始测量。** 拖到最后再测，每次优化都会变成重新设计。

---

*本文档是一份动态风险登记册，将随实际测量结果更新；若真的发生事故，将另行记录在单独的事后分析报告中。*

*最后更新：2026-09-15*
