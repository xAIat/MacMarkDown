# MacMarkDown 开发指南

欢迎来到 MacMarkDown 项目。MacMarkDown 是一款原生 macOS Markdown 编辑器，用纯 Swift 与 SwiftUI 从零写成：macOS 26 与 Swift 6.4 为 Apple 的开发生态开启了新纪元 —— SwiftUI、Observation、TextKit 2 与 Swift 并发已经成熟到足以承载一个完整的写作工具。

本指南涵盖开发、构建、测试和贡献 MacMarkDown 所需的一切信息。

---

## 1. 前置条件

| 要求    | 最低版本 | 推荐版本 |
|---------|----------|----------|
| macOS   | 26.0     | 26.0+    |
| Xcode   | 26.0     | 26.0+    |
| Swift   | 6.4      | 6.4+     |

你需要拥有有效的 Apple 开发者账号，才能从 [developer.apple.com](https://developer.apple.com) 或 Mac App Store 下载 Xcode 26。

验证你的工具链：

```bash
swift --version        # 预期输出：swift-driver version 6.4.x
xcodebuild -version    # 预期输出：Xcode 26.0
```

## 2. 快速开始

### 2.1 克隆仓库

```bash
git clone https://github.com/xAIat/MacMarkDown.git
cd MacMarkDown
```

### 2.2 打开项目

```bash
open MacMarkDown.xcodeproj
```

> 请打开 **`MacMarkDown.xcodeproj`**（单一 Xcode 工程），**不要**打开仓库文件夹。
> 该工程由 XcodeGen 根据 `project.yml` 生成，包含全部四个 target：`MacMarkDown` App、
> `MacMarkDownKit` 框架（核心逻辑）、`MacMarkDownCLI` 命令行工具（产物为
> `macmarkdown-cli`）以及 `MacMarkDownTests`。
> 根目录**没有** `Package.swift` —— 一切都位于 Xcode 工程中。
> 修改 `project.yml` 后，请运行 `xcodegen generate` 重新生成工程。

### 2.3 解决依赖

Xcode 会在首次打开时自动解析 Swift Package Manager 依赖（`swift-markdown` 与 `Yams`）。如果没有，请运行：

```bash
xcodebuild -project MacMarkDown.xcodeproj -scheme MacMarkDown -resolvePackageDependencies
```

或在 Xcode 中：**File → Packages → Resolve Package Versions**。

## 3. 构建

### 3.1 使用快捷键构建

| 操作     | 快捷键       |
|----------|--------------|
| 构建     | `Cmd+B`      |
| 运行     | `Cmd+R`      |
| 测试     | `Cmd+U`      |
| 清理     | `Cmd+Shift+K` |
| 性能分析 | `Cmd+I`      |

### 3.2 从命令行构建

```bash
# Debug 构建
xcodebuild -scheme MacMarkDown -configuration Debug build

# Release 构建
xcodebuild -scheme MacMarkDown -configuration Release build
```

`./scripts/build.sh [debug|release]` 封装了同样的命令，并把产物与日志写入 `.derived/`。

> **签名**：工程不固定开发团队。构建前请在 **Signing & Capabilities** 中选择
> 你自己的团队；或以 `xcodebuild ... CODE_SIGNING_ALLOWED=NO` 进行无签名构建。

### 3.3 为特定架构构建

```bash
# Apple Silicon
xcodebuild -scheme MacMarkDown -arch arm64 build

# Intel
xcodebuild -scheme MacMarkDown -arch x86_64 build

# 通用二进制
xcodebuild -scheme MacMarkDown -arch "arm64 x86_64" build
```

## 4. 项目结构

```
MacMarkDown/
├── MacMarkDown.xcodeproj            # 生成的 Xcode 工程（App + 框架 + CLI + 测试）
├── project.yml                      # XcodeGen 配置 —— 工程的唯一事实来源
├── MacMarkDown/                     # MacMarkDownKit 框架与 App 外壳
│   ├── Application/                 # MacMarkDown App target（薄壳）
│   │   ├── MacMarkDownApp.swift     # @main 入口与菜单命令
│   │   └── AppDelegate.swift        # NSApplicationDelegate 接线
│   ├── Info.plist                   # App bundle 配置（由 XcodeGen 生成）
│   ├── Document/                    # 文档模型、会话与 front matter
│   │   ├── MarkdownDocument.swift
│   │   ├── DocumentSession.swift
│   │   ├── FrontMatter.swift
│   │   └── …
│   ├── Markdown/                    # swift-markdown 解析与元素模型
│   │   ├── MarkdownParser.swift
│   │   └── MarkdownElement.swift
│   ├── Theme/                       # 预览主题与编辑器主题
│   │   ├── Theme.swift
│   │   ├── EditorTheme.swift
│   │   └── CodeHighlightTheme.swift
│   ├── Stores/                      # 可观察的应用状态
│   │   └── Preferences.swift
│   ├── Services/                    # 业务逻辑，按领域分组
│   │   ├── Editor/                  # 格式化、编辑操作、查找、高亮
│   │   ├── Export/ExportService.swift
│   │   ├── Preview/                 # AttributedRenderer、Renderer、RenderService 等
│   │   ├── ScrollSync/              # ScrollSyncService、ScrollSyncCoordinator
│   │   └── PlugIn/PlugInManager.swift
│   ├── Extensions/StringExtensions.swift
│   ├── Tools/                       # Constants、FontResolver、ResourceLoader、TerminalUtility
│   ├── UI/
│   │   ├── Shared/                  # 文档、预览与设置视图
│   │   └── macOS/                   # MarkdownTextView（TextKit 2）、预览表面、Touch Bar
│   ├── Resources/                   # MacMarkDownKit 的 bundle 资源
│   │   ├── Styles/                  # 预览样式表（.css）
│   │   ├── Templates/               # HTML 导出模板（Default.handlebars）
│   │   ├── Themes/                  # 编辑器主题（.style）
│   │   └── Extensions/              # Mermaid、Graphviz 与 MathJax 资源
│   └── Tests/                       # MacMarkDownTests target 源码
├── CLI/                             # MacMarkDownCLI target
│   └── main.swift                   # macmarkdown 命令行伴侣
├── Resources/                       # App target 资源
│   ├── Localizable.xcstrings        # 本地化字符串（源语言 en，共 21 个本地化）
│   ├── AppIcon.icns
│   ├── MacMarkDown.sdef             # AppleScript 脚本定义
│   └── help.md / contribute.md      # 内置帮助文档
├── docs/                            # 文档（EN + ZH）
│   ├── architecture/                # ADR
│   ├── business/
│   ├── design/                      # RFC
│   ├── guide/
│   ├── postmortems/
│   └── reference/
├── scripts/                         # build.sh、lint.sh、test.sh
└── README.md / README.zh.md
```

MacMarkDown 是一款地道的 macOS 文档应用：自研的 TextKit 2 编辑器
（`MarkdownTextView`）与原生 SwiftUI 预览并排显示，滚动同步由
`ScrollSyncService` 驱动；WKWebView 只用于必须走 Web 的内容块 —— 实时预览
中的表格与 TeX 数学公式，以及导出 HTML 中的 Mermaid/Graphviz 图表。HTML/PDF
导出经由 `Renderer`
（使用 `Default.handlebars` 与 `Styles/*.css` 样式表）和 `ExportService` 完成。

### 4.1 版本控制约定

| 路径 | 是否入库 | 说明 |
|------|----------|------|
| `Opencode/` | ❌ 不入库 | 本地模型接入配置模板（`opencode.jsonc_*`，按模型/网络分组），仅保留在本机，切勿提交 |
| `opencode.jsonc` | ❌ 不入库 | 本机实际生效的 opencode 配置（含本机模型与端口），已在 `.gitignore` 中忽略 |
| `.derived/`、`build/`、`DerivedData/` | ❌ 不入库 | xcodebuild 构建产物/缓存；`.derived/` 由 `scripts/*.sh` 生成，随时可以重建 |

> 新增文件前先确认 `.gitignore` 是否覆盖；本地模型配置（`opencode.jsonc`、`Opencode/`）一律不入库。

## 5. 核心依赖

| 包名           | 版本 | 用途                           |
|----------------|------|--------------------------------|
| `swift-markdown` | 0.6+ | Apple 的 Markdown 解析器（AST）|
| `Yams`         | 5.0+ | 解析 front matter 中的 YAML    |

`swift-markdown` 底层的 C 解析器 `swift-cmark` 会作为传递依赖自动解析，无需单独声明。
这些依赖在 `project.yml`（Xcode 包依赖）中声明，由 Xcode 解析。默认情况下不使用其他外部依赖。

### 添加新依赖

1. 打开 `project.yml`。
2. 将包添加到 `packages` 映射中。
3. 将其添加为相应 target 的依赖。
4. 运行 `xcodegen generate`，然后在 Xcode 中运行 **File → Packages → Resolve Package Versions**。

## 6. 添加新的 Markdown 扩展

MacMarkDown 基于 Apple 的 `swift-markdown`，并在两层之上扩展它：
`MarkdownParser` 中在解析前改写源码的预处理 pass，以及 `MarkdownParseOptions`
中启用该 pass 的开关。新语法应当始终走这两层，以保证编辑器、原生预览与 HTML
导出行为一致。

### 分步指南

1. **添加解析选项**（`MacMarkDown/Markdown/MarkdownElement.swift`）：

```swift
public struct MarkdownParseOptions: Sendable, Hashable {
    // …
    public var enableMyExtension: Bool
}
```

2. **实现语法 pass**（`MacMarkDown/Markdown/MarkdownParser.swift`）。在
   `Document(parsing:options:)` 之前预处理源码，并使用
   `transformOutsideFencedCode(_:_:)`，确保围栏代码块永远不会被改写：

```swift
if options.enableMyExtension {
    body = Self.transformOutsideFencedCode(body) { segment in
        applyMyMarker(to: segment)   // 保持行号不变的改写
    }
}
```

   对于行内语法，请沿用 `applyInlineExtensionMarkers` 中的哨兵模式（下划线、
   高亮与上标即由此实现）：用私有区字符包裹内容，再在 `convertInlines` 中把
   这一对哨兵映射为新的 `InlineElement` case。

3. **渲染新元素**：在
   `MacMarkDown/Services/Preview/AttributedRenderer.swift`（原生预览）与
   `MacMarkDown/Services/Preview/Renderer.swift`（HTML 导出）中处理新的
   `MarkdownElement` case；当预览以 SwiftUI 视图呈现时，还需在
   `MacMarkDown/UI/Shared/Preview/MarkdownView.swift` 中添加对应 case。

4. **暴露给用户**（如需）：在 `MacMarkDown/Stores/Preferences.swift` 中添加属性，
   在 `MacMarkDown/UI/Shared/Settings/SettingsView.swift` 的 **Markdown** 标签页中
   添加开关，并通过 `Preferences.parseOptions` 传递该值。

5. **添加测试**：在 `MacMarkDown/Tests/MarkdownParserTests.swift` 中补充解析测试，
   渲染覆盖可加入 `AttributedRendererTests.swift` 或 `PreviewRenderingTests.swift`。

6. **更新文档** —— 在中英文文档中添加扩展说明。

## 7. 添加新主题

MacMarkDown 有两套主题系统：预览主题（`MacMarkDown/Theme/Theme.swift` 中的
`Theme` 值，导出时由 CSS 样式表支撑）与编辑器主题（`EditorTheme` 值以及
INI 风格的 `.style` 文件）。请保持主题名在三类文件中一致。

### 分步指南

1. **创建导出样式表** `MacMarkDown/Resources/Styles/My Theme.css`。
   `Renderer` 与 `TablePreviewHTML` 会通过
   `ResourceLoader.styleSheet(forTheme:)` 按主题的 `displayName` 或 `name`
   查找该文件；找不到时回退到由 `Theme` 调色板生成的样式。

2. **定义预览主题**（`MacMarkDown/Theme/Theme.swift`）：

```swift
public static let myTheme = Theme(
    name: "My Theme",
    displayName: "My Theme",
    backgroundColor: Color(red: 1.0, green: 1.0, blue: 1.0)
    // …其余调色板颜色
)
```

3. **注册主题**到 `Theme.all`，使其出现在 **Settings → HTML → Preview Style**：

```swift
public static let all: [Theme] = [
    clearness, github, solarizedLight, solarizedDark, night, myTheme
]
```

4. **编辑器主题**：可在 `MacMarkDown/Theme/EditorTheme.swift` 中添加
   `EditorTheme` 值并追加到 `EditorTheme.all`，也可将 `.style` 文件放入
   `MacMarkDown/Resources/Themes/` —— 打包的文件会被
   `EditorTheme.fileBased` 自动发现（见 `EditorTheme+StyleFile.swift`）。

5. **测试**：在 **Settings → HTML**（预览样式）或 **Settings → Editor**（编辑器样式）
   中选择新主题，确认编辑器和预览都能正确渲染；并在
   `MacMarkDown/Tests/EditorThemeStyleFileTests.swift` 与
   `MacMarkDown/Tests/PreviewRenderingTests.swift` 中补充覆盖率。

## 8. 运行测试

`MacMarkDownTests` target 使用 XCTest。测试文件直接位于 `MacMarkDown/Tests/` 下，
每个领域一个文件。

### 8.1 运行所有测试

在 Xcode 中：`Cmd+U`

从命令行：

```bash
xcodebuild test -scheme MacMarkDown -destination "platform=macOS"
```

或运行 `./scripts/test.sh`（加 `--coverage` 可生成覆盖率结果包）。

### 8.2 运行特定测试套件

```bash
# 格式化与编辑操作
xcodebuild test -scheme MacMarkDown \
    -only-testing:MacMarkDownTests/EditorFormattingTests

# 解析
xcodebuild test -scheme MacMarkDown \
    -only-testing:MacMarkDownTests/MarkdownParserTests

# 原生预览渲染
xcodebuild test -scheme MacMarkDown \
    -only-testing:MacMarkDownTests/AttributedRendererTests
```

### 8.3 并行运行测试

```bash
xcodebuild test -scheme MacMarkDown -parallel-testing-enabled YES
```

### 8.4 生成代码覆盖率报告

```bash
xcodebuild test -scheme MacMarkDown -enableCodeCoverage YES \
    -derivedDataPath ./DerivedData
```

在 Xcode 中通过 **Report Navigator → Coverage** 查看覆盖率报告。

## 9. 调试技巧

- **编辑器状态检查**：在
  `MacMarkDown/UI/macOS/Editor/MarkdownTextView/MarkdownTextView.swift` 或
  `MacMarkDown/UI/Shared/Document/DocumentView.swift` 中设置断点，检查文本缓冲区、
  选区与撤销栈。
- **预览调试**：实时预览是原生 SwiftUI + TextKit 2（`MarkdownView`、
  `MarkdownPreviewSurface`）；只有表格、数学公式与图表块使用 WKWebView，
  在 Safari 中启用 **Develop → MacMarkDown** 即可检查这些 Web 块。
- **并发问题**：使用 Thread Sanitizer（**Scheme → Diagnostics → Thread Sanitizer**）来捕获数据竞争。
- **性能分析**：使用 Instruments 的 **Time Profiler** 模板来识别热点路径。

## 10. 常见任务

### 添加新的键盘快捷键

1. 在 `EditorFormatCommand` 中添加 case，并在 `EditorFormatting.apply`
   （`MacMarkDown/Services/Editor/EditorFormatting.swift`）中处理；
   具体文本变换写在 `EditorOperations.swift` 中。
2. 在 `MacMarkDown/Application/MacMarkDownApp.swift` 的 Format
   `CommandMenu`（或相应的 `CommandGroup`）中添加带 `.keyboardShortcut`
   的菜单项。
3. 通过现有的通知模式（`Constants.formatCommandUserInfoKey`）把命令发送到当前窗口；
   `DocumentView` 会将其应用到编辑器选区。若需要便于发现，也请在
   `ToolbarView` 中添加入口。
4. 在 `MacMarkDown/Tests/EditorFormattingTests.swift` 与
   `EditorOperationsTests.swift` 中添加测试。
5. 更新文档中的键盘快捷键一览表。

### 添加新的偏好设置

1. 在 `MacMarkDown/Stores/Preferences.swift` 的对应分区中添加属性，添加其
   `Key` case，并在 `init` 中写入默认值，使 setter 能持久化到 `UserDefaults`。
2. 在 `MacMarkDown/UI/Shared/Settings/SettingsView.swift` 的对应标签页
   （General、Markdown、Editor、HTML 或 Terminal）中添加 UI 控件。
3. 若该偏好影响解析或导出，请通过 `Preferences.parseOptions` 传递，
   使 `MarkdownParser` 与 `Renderer` 能读取到它。
4. 在 `MacMarkDown/Tests/PreferencesTests.swift` 中添加测试。

该类是 `@MainActor @Observable` 的，因此绑定的控件会在偏好变化时自动刷新。

### 修复 Bug

1. 编写一个失败的测试来重现 bug。
2. 在源代码中修复 bug。
3. 验证测试通过。
4. 运行完整测试套件以检查回归。

## 11. CI/CD

项目把检查脚本放在 `scripts/` 中，使本地与 CI 运行完全相同的命令：

- `./scripts/build.sh [debug|release]` —— 构建验证，产物写入 `.derived/`。
- `./scripts/lint.sh` —— 严格并发警告、TODO/FIXME 标记、文件结构与 TextKit 2 合规检查。
- `./scripts/test.sh [--coverage]` —— 单元测试，可选生成覆盖率结果包。

典型的流水线在每次推送以及每个发往 `main` 的 PR 上运行构建、检查与测试，
并发布 `test.sh --coverage` 生成的覆盖率报告。请让 CI 服务（例如 GitHub Actions）
调用这些脚本；仓库中不包含工作流文件。

---

*最后更新：2026-09-15*
