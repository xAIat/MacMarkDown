# RFC-003：编辑器集成架构

| 字段     | 值                             |
|----------|--------------------------------|
| RFC      | 003                            |
| 标题     | 编辑器集成架构                  |
| 作者     | MacMarkDown 核心团队           |
| 状态     | 草案                           |
| 创建日期 | 2026-09-15                     |
| 更新日期 | 2026-09-15                     |

---

## 1. 摘要

本 RFC 定义 MacMarkDown 编辑器的架构：文本表面本身、其背后的 TextKit 2 布局技术栈、编辑管线、格式化与智能编辑、输入法/中日韩输入、选区、无障碍支持、插件，以及编辑器如何托管于 SwiftUI 并与预览面板同步。

macOS 26 与 Swift 6.4 为 Apple 的开发生态开启了新纪元：SwiftUI、Observation、TextKit 2 与 Swift 并发已经成熟到足以承载一个完整的写作工具，因此 MacMarkDown 用纯 Swift 与 SwiftUI 从零写成，而编辑器正是这一选择体现得最充分的组件。它并非对现成文本控件的封装：它是一个自定义的 TextKit 2 视图 `MarkdownTextView`，自行持有 `NSTextContentStorage`、布局管理器与文本容器；通过 `NSTextViewportLayoutController` 为每个可见布局片段创建一个视图来渲染；处理输入、输入法组字、选区、格式化、拖放、拼写检查、朗读与无障碍；并由 `MarkdownEditorView` 嵌入 SwiftUI。

应用的目标平台是 macOS 26，使用 macOS 27 SDK 构建，因此编辑器直接建立在当前 TextKit 2 能力之上，而不是兼容层之上。

## 2. 动机

写作工具需要声明式文本控件不会暴露的布局细节：在自动换行的行上解析插入点几何位置、放置行号栏、绘制不可见字符、为预览测量滚动锚点、计算附件尺寸，以及为选区高亮生成片段矩形。只有自行持有文本栈，才能用一套一致的坐标系提供所有这些能力。

塑造这一设计的其他需求：

- **文本输入不只是打字。** 组字（输入法）事件、暂存文本（marked text）、候选窗口、按键绑定与服务菜单都经由 AppKit 的输入与响应者机制到达。编辑器直接实现 `NSTextInputClient` 与相关 `NSResponder` 动作，因此日文、中文、韩文输入是一等路径，而非降级方案。
- **大文档必须保持低成本。** 布局是惰性、按视口进行的：只布局可见区域加上预取边距，片段视图会被缓存与复用。内容高度仅在文本或换行宽度变化时测量，并且用户正在滚动或缩放窗口时会推迟测量。
- **严格并发是默认配置。** 所有视图状态都由 `@MainActor` 隔离。AppKit 的文本协议并非 Actor 隔离，因此其实现遵循 SE-0466 声明为隔离，由编译器强制校验边界。
- **一套引擎，两个面板。** 预览使用同一个只读 TextKit 2 表面，因此整篇文档的选区、复制与锚点测量都来自与编辑器相同的布局引擎。
- **可测试性。** 协议接缝 `EditorTextViewHost` 让智能编辑辅助函数与 SwiftUI 协调器既能针对编辑器视图运行，也能针对普通 `NSTextView` 运行，无需宿主应用；编辑器还可以无头方式执行完整布局流程。

## 3. 架构总览

```
NSScrollView
└── MarkdownTextView（翻转坐标的 NSView，文档视图）
    └── contentView（CATiledLayer）
        ├── selectionView  ──  MarkdownSelectionHighlightView × n
        └── contentViewportView（CATiledLayer）
            └── 每个可见布局片段对应一个 MarkdownTextFragmentView
                └── 附件视图（图片、表格、Web 块）

由 MarkdownTextView 持有的 TextKit 2 技术栈：

  NSTextContentStorage ──▶ MarkdownTextLayoutManager ──▶ NSTextContainer
        （NSTextStorage）        （NSTextLayoutManager）      （宽度跟随视图）
                                        │
                                        └── NSTextViewportLayoutController
                                            （可见区域 + 预取）
```

| 组件 | 职责 |
|------|------|
| `MarkdownTextView` | 持有 TextKit 2 技术栈与整个编辑表面的 `NSView` |
| `NSTextContentStorage` | 文档存储与 `NSTextContentManager` |
| `MarkdownTextLayoutManager` | 自定义 `NSTextLayoutManager`；布局期渲染的接缝 |
| `NSTextContainer` | 宽度跟随视图；行片段内边距为零；高度不受限 |
| `NSTextViewportLayoutController` | 布局可见区域并请求片段视图 |
| `MarkdownTextFragmentView` | 单个布局片段的绘制表面；承载附件视图 |
| `MarkdownTextLayoutFragment` | 可绘制不可见字符的布局片段子类 |
| `MarkdownContentView` / `MarkdownContentViewportView` | 基于 `CATiledLayer` 的容器，控制重绘成本 |
| `MarkdownSelectionView` | 在字形下方绘制的选区高亮条带池 |
| `MarkdownGutterView` | 位于文档坐标系中的行号栏 |
| `MarkdownEditorView` | SwiftUI `NSViewRepresentable` 宿主与协调器 |
| `EditorTextViewHost` | 协调器、智能编辑与语法高亮共用的协议接缝 |
| `EditorFormatting` / `EditorOperations` | 工具栏与「格式」菜单共用的纯格式化命令 |
| `MarkdownSyntaxHighlighter` | 基于主题的语法高亮，直接作用于文本存储 |

## 4. TextKit 2 技术栈

### 4.1 归属与装配

`MarkdownTextView` 创建并持有技术栈的每一层：

```swift
textLayoutManager.textContainer = textContainer
textContentStorage.addTextLayoutManager(textLayoutManager)
textContentStorage.primaryTextLayoutManager = textLayoutManager
textLayoutManager.textViewportLayoutController.delegate = self
```

`textContainer.widthTracksTextView = true` 让换行宽度跟随视图宽度（减去用户设置的内容内边距），`lineFragmentPadding` 置零，使布局原点与视图坐标系完全一致。`NSTextViewportLayoutController` 的委托就是视图本身：它为每个 `NSTextLayoutFragment` 创建、缓存并复用 `MarkdownTextFragmentView`。

自行持有技术栈，才让编辑器的其余部分成为可能：通过子类化布局管理器或布局片段即可在布局期改变行为，而宿主视图无需知晓；视图可以驱动 `layoutViewport()`、以 O(1) 重新定位视口，并在单元测试中以无头方式运行同一套流程。

### 4.2 视口布局与片段视图

视图只布局用户可见的内容，外加一条预取带（可见区域上下各半个视口），因此滚动长文档的代价与可见内容成正比，而不是与文档大小成正比。片段视图保存在以 `NSTextLayoutFragment` 为键的弱映射表中；每次视口布局结束时，未被复用的视图会被移除并移出映射表。

容器由 `CATiledLayer` 支撑，从而限制超长文档的重绘成本。由此有两个刻意的设计：

- 选区高亮位于分块容器与片段视图之间的一个专用非分块视图中，因为分块图层会忽略普通的 `needsDisplay` 失效。该视图池化小型条带视图，并根据布局管理器的 `.selection` 片段矩形重建。
- 由 WebKit 支撑的块（表格与数学公式）放置在文档视图上的覆盖宿主中，而不是分块片段宿主内部，因为托管在分块图层内的 `WKWebView` 无法可靠合成。

`MarkdownTextFragmentView` 还会布局属于其片段的任何 `NSTextAttachmentViewProvider` 视图，图片、表格与 Web 块正是以此参与正常文本流。

### 4.3 布局管理器作为渲染接缝

`MarkdownTextLayoutManager` 目前保持标准 TextKit 2 管线（启用了 `usesFontLeading`），但它的存在就是为了成为后续渲染阶段的钩子：隐藏强调标记、绘制行内图片占位符、柔化硬换行，都可以在布局期实现，而无需改动宿主视图。自定义的 `MarkdownTextLayoutFragment` 是这一思路的第一个消费者——启用不可见字符时，它会在已排版的文字之上为每个空格、制表符与换行符绘制符号。

### 4.4 内容尺寸与滚动

文档视图的高度跟随布局：

- 文本或换行宽度变化时（`needsFullHeightMeasurement`），视图强制执行一次完整的 `ensureLayout`，确保可滚动范围精确；一个之后会增长的局部估算会移动所有滚动锚点。
- 纯滚动时复用现有估算，而不重新布局整篇文档。
- 用户正在实时滚动或缩放窗口期间推迟测量，避免画面在指针下抖动。
- 「允许滚动越过文末」在底部追加一个视口的空白；文档变短时，滚动原点会被夹回有效范围。

滚动到某个位置时，先检查当前视口；若目标在视口之外，则直接重新定位视口锚点，而不是布局两者之间的全部内容，然后再把目标片段矩形带入可视区域。`centerSelectionInVisibleArea(_:)` 让查找与跳转获得居中结果，且不产生额外布局开销。

## 5. 编辑管线

### 5.1 变更核心与撤销

每一次编辑——打字、输入法提交、格式化命令、查找替换、拖放、无障碍写入——都汇入同一个替换原语：

```swift
func replaceCharacters(in range: NSTextRange, with replacement: NSAttributedString) {
    textContentStorage.performEditingTransaction {
        textStorage?.replaceCharacters(
            in: textContentStorage.range(from: range),
            with: replacement
        )
    }
    registerUndo(for: range, replacement: replacement)
    needsFullHeightMeasurement = true
    needsLayout = true
}
```

替换在编辑事务中执行，使布局管理器、视口与 `textSelections` 保持一致。写入走底层的 `NSTextStorage`，而不是内容存储的整文档替换，这使空文档与非空文档在 macOS 27 SDK 上走同一条路径。每次编辑都注册一个重放同一原语的撤销动作，连续打字会被合并，让 `⌘Z`/`⇧⌘Z` 按自然的编辑步骤回退。

两个宿主钩子让外围应用无需了解文本栈即可介入：

- `shouldChangeTextHandler`——每个即将落地的编辑都会先经过它；返回 `false` 即可否决（智能编辑与协调器使用）。
- `doCommandHandler`——在默认 `NSResponder` 动作执行前被查询。

文档被打开、另存为或还原时，协调器递增 `undoResetGeneration`；编辑器整体替换缓冲区并清空撤销历史，而不是把加载记录成一次可撤销的差异。由模型驱动的编辑（例如「格式」命令）以最小的可撤销替换应用，行为与普通编辑步骤一致。

### 5.2 键盘输入与输入法

文本输入经由 `interpretKeyEvents(_:)` 到达，视图将其路由到自身的 `NSResponder` 动作；已提交文本则通过 `NSTextInputClient` 实现到达：

- `insertText(_:replacementRange:)` 先结束组字，解析目标范围，再通过变更核心应用替换。
- `setMarkedText(_:selectedRange:replacementRange:)`、`unmarkText()`、`markedRange()` 与 `hasMarkedText()` 实现组字。暂存文本与已提交选区分开保存，从而允许输入法就地修改；输入属性会与暂存文本属性（默认单下划线）合并，输入法附带的不可见下划线颜色会在显示前移除。
- `firstRect(forCharacterRange:actualRange:)` 与 `characterIndex(for:)` 负责放置候选窗口，并把屏幕坐标解析回文档偏移。
- `attributedSubstring(forProposedRange:actualRange:)`、`attributedString()` 与 `validAttributesForMarkedText()` 补全整个协议契约。

组字进行期间会抑制撤销注册，因此一次已提交的组字对应一步撤销，而不是每次暂存修订各占一步。配对补全在暂存范围内会被跳过，避免输入法输入在组字中途被自动补全。

### 5.3 选区与插入点

选区状态保存在布局管理器的 `textSelections` 中，以 `NSTextSelection` 表示，由指针与键盘共同驱动：

- 单击、拖动、双击、三击与 Shift 单击都通过 `NSTextSelectionNavigation` 更新选区；指针选区会话期间会持有一个锚点。
- 在已有选区内部按下指针时，只有按住超过一个很短的阈值才开始拖出手势；更快的拖动则改为扩展选区。
- 高亮以文本下方的后处理条带呈现（见 4.2）。插入点是一个 `NSTextInsertionIndicator`，按内容坐标放在空选区处，滚动时无需额外处理即可跟随。
- 键盘导航（方向键、按词移动、Home/End、翻页）走同一个导航对象，因此移动语义与系统其余部分一致。

### 5.4 标准编辑命令

编辑器是 `NSView` 而非 `NSTextView`，因此 AppKit 的标准编辑动作需要显式实现：

- 剪贴板：剪切、复制、粘贴、删除、全选；复制同时写入纯文本、RTF 与 HTML，粘贴到富文本目标时保留格式。
- 导航与删除：`moveLeft/Right/Up/Down` 及其按词、按行变体，`deleteForward/Backward`、`deleteWordBackward`、翻页，以及 `interpretKeyEvents(_:)` 产生的其余动作。
- 查找动作通过 `onFindAction` 交给外围文档界面处理。
- 大小写转换（`capitalizeWord`、`lowercaseWord`、`uppercaseWord`）、字体面板（`changeFont`）与 `centerSelectionInVisibleArea(_:)` 补全响应者表面。

## 6. 格式化命令

格式化被建模为一组封闭的命令，使工具栏与「格式」菜单共享同一实现：

```swift
public enum EditorFormatCommand: String, Sendable, CaseIterable {
    case paragraph, h1, h2, h3, h4, h5, h6
    case strong, emphasis, inlineCode, strikethrough
    case underline, highlight, comment
    case unorderedList, orderedList, blockquote, codeBlock
    case link, image
    case indent, unindent
    case newParagraph
}
```

`EditorFormatting.apply(_:to:selection:listMarker:tabPadding:)` 是一个作用于纯文本与 UTF-16 选区的纯函数。它返回新文本与需要恢复的选区；选区无效时返回 `nil`。内部调用 `EditorOperations`——一组无需文本视图即可测试的字符串变换：

- `toggleMarkup`——用前缀/后缀对包裹或解包选区（`**`、`*`、`` ` ``、`~~`、`_`、`==`、`<!--`）；空选区时插入占位文本（链接文字、图片替代文字）。
- `toggleBlock`——在选区的每一行上开关行级结构（无序列表、有序列表、引用块）。
- `setHeaderLevel`——设置或清除标题级别。
- `indentLines` / `unindentLines`——按用户设置的制表符内边距缩进。

列表标记（`* `、`- ` 或 `+ `）与制表符内边距来自偏好设置；工具栏与「格式」菜单调用同一入口，因此同一命令不会因触发位置不同而表现不同。SwiftUI 宿主把结果作为最小的可撤销替换应用，恢复命令报告的选区，将其滚入可视区域并重新应用语法高亮。

## 7. 智能编辑

智能编辑运行在协调器之中，位于文本视图与输入事件之间。每项行为都可单独由偏好设置控制：

| 触发条件 | 行为 |
|----------|------|
| 输入左括号、引号或中日韩标点 | 当插入点位于词边界时，插入配对的右字符并把光标移到两者之间 |
| 输入右字符且下一个字符已是配对右字符 | 光标越过它，而不是插入重复字符 |
| 在配对字符之间按退格 | 一次删除两个字符 |
| 有选区时输入左字符 | 用配对字符包裹选区（`*文本*`、`` `代码` ``、`【文本】` 等） |
| 有选区时输入 `*`、`_`、`` ` ``、`=` 或 `~~`（启用时） | 用该标记包裹选区 |
| Tab | 以空格前进到下一个 4 列制表位，或缩进选中的每一行 |
| Shift-Tab | 将选中的每一行减少一级缩进 |
| 行首 2–4 个空格后按退格 | 删除整个制表步进 |
| 在列表项中按回车 | 延续列表标记；有序列表自动递增；空列表项结束列表 |
| 在引用块中按回车 | 延续 `> ` 标记 |
| 在缩进行中按回车 | 保留行首空白 |
| Home | 移到第一个非空白字符；已在该处时回退到行首 |

配对字符表覆盖 ASCII 括号与引号——`()[]{}<>'"`——以及中日韩配对 `（）`、`「」`、`『』`、`‘’`、`“”`、`‹›`、`«»`、`〈〉` 与 `《》`。由于检查是边界感知的，配对不会在单词中间触发，也绝不会在输入法暂存范围内触发。

「智能 Home」还有一条额外规则：先把当前偏移与目标偏移解析到各自的行片段，当两者位于不同的视觉行时回退到标准 Home 行为。这样 Home 不会在自动换行的行之间跳跃，同时仍能跳过行首缩进。

## 8. 编辑器的原生能力

### 8.1 行号栏

行号栏是文档坐标系中的一个子视图，随内容一起滚动，除既有布局流程外无需额外的滚动观察者。行首偏移按文本变更世代缓存，并用二分查找解析；行号栏会在内容内边距左侧预留自己的宽度。

### 8.2 不可见字符

启用后，自定义的 `MarkdownTextLayoutFragment` 会在普通文字之上，按每个字符的片段矩形为空格、制表符、换行、回车及其他 Unicode 空白绘制占位符号。

### 8.3 拼写检查、朗读与服务

- 拼写检查使用 `NSSpellChecker` 返回的范围并绘制红色点状下划线。这些属性只存在于内存中，绝不会写入保存的文件。
- 朗读通过 `AVSpeechSynthesizer` 朗读选区；没有选区时朗读整篇文档。
- 视图参与服务菜单，并能通过剪贴板提供和接收文本。

### 8.4 拖放与附件

文本拖放会插入到指针下的插入点。文件拖放会在窗口的 SwiftUI 拖放处理之前被拦截：拖入文档会在应用中打开它，拖入图片文件会以内联 base64 Markdown 插入。选区可以拖出到其他应用。附件是一等文本内容，因此图片、表格与内嵌 Web 块占据真实的布局空间，并由各自的片段视图完成布局。

### 8.5 语法高亮

`MarkdownSyntaxHighlighter` 把当前 `EditorTheme` 应用到文本存储：标题、强调、代码、引用、链接与标记等文本段获得主题颜色，同时保留字体与段落样式。用户编辑后、主题或字体变化后、文档加载后都会重新应用高亮；由于它会更新整篇文档的属性，也会标记需要重新测量完整高度，保证滚动范围正确。

### 8.6 插件

编辑器暴露一组小型事件 API（`MarkdownPlugin`）：插件通过 `setUp(textView:events:)` 注册，可观察 `shouldChange`、`didChange` 与 `didLayoutViewport` 事件，其中 `shouldChange` 可以否决一次编辑。插件通过 `tearDown()` 卸载。这是面向编辑器行为的进程内扩展点；应用级插件包见业务总览。

## 9. 无障碍

`MarkdownTextView` 是普通 `NSView`，若不显式实现，VoiceOver 无法识别出有用的内容。视图把自己暴露为具有标准几何信息的文本区域：

- 角色、角色描述、标签（「文本编辑器」）、启用状态与值。
- 共享字符范围；字符数量；可见字符范围。
- 选中的文本、选中文本范围、插入点所在行号。
- 行与范围的相互转换（`accessibilityLine(for:)`、`accessibilityRange(forLine:)`）。
- 范围对应的屏幕矩形与坐标点对应的范围，均通过布局管理器的片段矩形与排版边界解析。
- 范围内富文本子串的访问。

这些 API 与编辑器其余部分读取同一个布局管理器，因此在自动换行、滚动与视口复用过程中始终保持正确。

## 10. SwiftUI 托管与预览集成

### 10.1 MarkdownEditorView

`MarkdownEditorView` 是一个 `NSViewRepresentable`，围绕 `MarkdownTextView` 构建 `NSScrollView`，并通过 `Coordinator` 让两者保持同步：

- 应用字体、行距、编辑器主题、内容内边距、拼写检查、行号与不可见字符设置。
- 同步智能编辑偏好（智能 Home、制表符转换、块内前缀插入、列表自动递增、配对补全、删除线包裹）。
- 双向桥接选区，通过观察文本存储上报文本变化，并转发查找动作与拖入的文件。
- 把模型驱动的文本与选区变化作为可撤销编辑应用，并在文档层发出加载或还原信号时重置撤销历史。
- 在编辑、主题变化与文档加载后重新应用语法高亮。

### 10.2 预览与同步滚动

预览面板是同一个 TextKit 2 表面的只读实例。这使它具备整篇文档的选区与复制能力，也让滚动锚点可以直接从文本布局测量，而无需几何探针。

`ScrollSyncService` 使用解析器生成的密集有序锚点表把编辑器与预览配对——每个块与列表项一个锚点，按文档顺序排列。两个面板为同一张有序表测量 Y 坐标，因此数组按索引一一对应，滚动偏移在其中夹住它的两个锚点之间插值。同步默认从编辑器到预览；启用双向偏好后也会使用反向映射。反向映射是正向映射的精确逆运算，通过二分法求得，因此两个面板不会互相追逐。

## 11. 并发模型

- `MarkdownTextView`、其扩展、`MarkdownEditorView` 协调器、语法高亮器、`ScrollSyncService` 与 `Preferences` 都由 `@MainActor` 隔离。任何后台线程都不会触碰文本缓冲区。
- AppKit 的文本协议并非 Actor 隔离。它们的实现（`NSTextViewportLayoutControllerDelegate`、`NSTextLayoutManagerDelegate`、`NSTextInputClient`、`NSDraggingSource`、`NSServicesMenuRequestor`）遵循 SE-0466 声明为 `@MainActor` 隔离，使编译器能够验证回调只在主 Actor 上运行。
- 跨 Actor 边界传递的值都是不可变且 `Sendable` 的：`EditorFormatCommand`、格式化结果、解析出的元素/锚点树、主题与样式值。
- 解析与渲染服务接收纯值、在主 Actor 上返回纯值；编辑器通过文档模型观察结果，而不是共享可变状态。
- 项目在开启 Swift 6.4 严格并发的情况下构建。

## 12. 测试策略

| 领域 | 测试覆盖 |
|------|----------|
| 视口布局、内容高度、片段复用、插入点 | `MarkdownTextViewTests`——通过 `performFullLayoutForTesting()` 无头驱动真实视口管线 |
| 编辑与标准命令 | `MarkdownTextViewStandardEditingTests` |
| 协调器/宿主桥接、模型编辑、撤销重置 | `MarkdownEditorCoordinatorTests`、`MarkdownTextViewHostTests` |
| 智能编辑（配对、制表步进、回车延续、智能 Home） | `EditorSmartEditingTests` |
| 格式化命令 | `EditorFormattingTests`、`EditorOperationsTests` |
| 语法高亮 | `SyntaxHighlighterTests` |
| 输入法暂存文本处理 | `MarkdownTextViewTests`（`setMarkedText`、`unmarkText`、暂存范围） |
| 无障碍几何信息 | `MarkdownTextViewTests` |
| 滚动同步与锚点 | `ScrollSyncServiceTests`、`ScrollSyncCoordinatorTests` |
| 大文档性能 | 基于万行以上文档的 XCTest `measure` 测试装置（计划中） |

编辑器行为测试同时针对真实的 `MarkdownTextView` 与 `EditorTextViewHost` 接缝运行：格式化与智能编辑变换不依赖任何特定文本视图，而集成测试则覆盖真实的 TextKit 2 技术栈。

## 13. 考虑过的替代方案

1. **SwiftUI `TextEditor`**——否决。它暴露绑定与按键钩子，但不暴露插入点几何、行片段、行号位置、附件尺寸或滚动锚点；在其上构建编辑器意味着为本文档中的每一项能力与抽象层对抗。
2. **子类化 `NSTextView`**——否决。`NSTextView` 的渲染管线有大量不透明部分，而布局层计划实现的能力（标记隐藏、自定义片段、Web 块托管）需要一套自有的 TextKit 2 技术栈，而不是再叠加一层覆写。
3. **基于 Web 的编辑器（CodeMirror 风格）放入 `WKWebView`**——否决。这会让核心编辑表面失去原生特性，使输入法与无障碍复杂化，并把输入处理拆分到两个引擎。
4. **第三方原生文本视图包**——否决。文本表面是本产品的核心；自行持有可避免依赖风险，并让严格并发模型处于本项目掌控之内。

## 14. 待解决问题

1. **增量高度测量**——能否在不执行完整布局的情况下，由视口的用量边界估算文档高度，同时让滚动范围稳定到足以支撑同步？
2. **布局期标记渲染**——在布局片段内部隐藏强调标记、同时保持底层字符可选可编辑，正确的接缝在哪里？
3. **输入法边界情况**——在列表标记处开始的组字、与自动配对范围重叠的组字、输入法与撤销的组合，以及自动换行行上的候选窗口定位。哪些可以靠测试覆盖，哪些需要针对中日韩输入法的手工矩阵？
4. **附件测量**——当 Web 块（表格或数学公式）在布局后上报新高度时，能否把失效范围限制在受影响的片段，而不是强制整篇重新测量？
5. **插件 API 稳定性**——`MarkdownPlugin` 事件表面应跨版本提供怎样的兼容保证？
6. **双向同步**——在惯性滚动与回弹期间，反向映射应如何表现，才能避免两个面板互相反馈？
7. **性能预算**——我们为完全可交互打字设定的最大文档是多少（例如 5 MB / 10 万行）？在该规模下完整高度测量是否仍然可接受？

## 15. 参考资料

- [NSTextLayoutManager](https://developer.apple.com/documentation/appkit/nstextlayoutmanager)
- [NSTextViewportLayoutController](https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller)
- [NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [AppKit 无障碍](https://developer.apple.com/documentation/appkit/accessibility-for-appkit)
- [SE-0466：控制默认 Actor 隔离](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)
- [swift-markdown 仓库](https://github.com/apple/swift-markdown)
- [Yams 仓库](https://github.com/jpsim/Yams)
- [Apple 人机界面指南 — 文本输入](https://developer.apple.com/design/human-interface-guidelines/text-input)

本 RFC 引用的编辑器源码：

- `MacMarkDown/UI/macOS/Editor/MarkdownTextView/`——TextKit 2 视图及其扩展
- `MacMarkDown/UI/macOS/Editor/MarkdownEditorView.swift`——SwiftUI 宿主与协调器
- `MacMarkDown/Services/Editor/`——格式化命令、智能编辑与语法高亮

---

*本文档属于 MacMarkDown 设计 RFC 系列。请参阅 [RFC-001](./rfc-001-core-architecture.zh.md) 了解核心架构，[RFC-002](./rfc-002-rendering-pipeline.zh.md) 了解渲染管线设计。*
