# 为 MacMarkDown 做贡献

感谢你有兴趣为 MacMarkDown 做贡献。MacMarkDown 是一款面向 macOS 26 时代、用纯 Swift 与 SwiftUI 从零写成的原生 macOS Markdown 编辑器；本指南概述了所有贡献的标准和流程。

---

## 1. 代码风格

### 1.1 Swift 6.4 严格并发

MacMarkDown 使用 Swift 6.4 工具链、Swift 6 语言模式，并开启完整严格并发检查。所有代码必须符合以下要求：

- **无数据竞争**：所有可变的共享状态必须是 `@MainActor` 隔离的或 `Sendable` 的。
- **显式隔离**：在适当的地方使用 `@MainActor`、`@Sendable` 和 `sending` 参数。
- **除非不可避免，否则不使用 `@preconcurrency`**：仅在系统框架桥接时使用（例如 `NSViewRepresentable`）。
- **在 Xcode 构建设置中启用严格模式（`project.yml`）**：

```yaml
# project.yml
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
```

### 1.2 格式化

- 使用 **4 个空格**缩进（不使用 Tab）。
- 最大行长度：**120 个字符**。
- 保持全仓库格式一致；对 Swift 源码运行 `swift-format`（默认风格）：

```bash
swift-format format --in-place MacMarkDown/ CLI/
```

- 遵循 [Swift API 设计指南](https://www.swift.org/api-design-guidelines/)。
- 使用 `guard` 进行提前返回。
- 尽可能使用 `let` 而非 `var`。

### 1.3 命名约定

| 元素           | 约定              | 示例                          |
|----------------|-------------------|-------------------------------|
| 类型           | UpperCamelCase    | `EditorFormatting`            |
| 函数/方法      | lowerCamelCase    | `toggleMarkup(...)`           |
| 属性           | lowerCamelCase    | `editorBaseFontSize`          |
| 常量           | lowerCamelCase    | `defaultEditorFontSize`       |
| 枚举值         | lowerCamelCase    | `.strong`                     |
| 协议           | UpperCamelCase    | `Theme`                       |
| 文件           | UpperCamelCase    | `EditorFormatting.swift`      |
| 测试文件       | UpperCamelCase + Tests | `EditorFormattingTests.swift` |

### 1.4 文档注释

所有公共 API 必须有文档注释。使用 `///` 风格：

```swift
/// 在当前选区上切换一对 Markdown 前后缀。
///
/// 如果选区已经被包裹，则移除标记；空选区会插入带 `placeholder` 的包裹
/// 并选中占位文本。
///
/// - Parameters:
///   - text: 要修改的字符串缓冲区。
///   - selectedRange: 当前选区。
///   - prefix: 插入到选区前的标记。
///   - suffix: 插入到选区后的标记。
///   - placeholder: 选区为空时插入的文本。
/// - Returns: 新文本以及需要选中的范围。
public static func toggleMarkup(
    in text: String,
    selectedRange range: Range<String.Index>,
    prefix: String,
    suffix: String,
    placeholder: String = ""
) -> (text: String, newRange: Range<String.Index>) {
    // ...
}
```

### 1.5 模块组织

App target 只是薄壳，所有可复用代码都位于 `MacMarkDownKit` 框架中。每个目录都有明确职责：

| 目录         | 职责                              |
|--------------|-----------------------------------|
| `Application` | 应用入口、菜单命令、App delegate |
| `Document`   | 文件 I/O、文档生命周期、会话、front matter |
| `Markdown`   | swift-markdown 解析、元素模型、解析选项 |
| `Theme`      | 预览主题、编辑器主题、代码高亮    |
| `Stores`     | 可观察应用状态（偏好设置）        |
| `Services`   | 编辑操作、预览渲染、导出、滚动同步、插件 |
| `UI`         | SwiftUI 视图，以及 TextKit 2 编辑器与预览表面 |
| `Tools`/`Extensions` | 共享工具（常量、资源加载、扩展） |

不要创建跨模块循环依赖。依赖关系向内流动：
`Application → UI → Services → Document/Markdown/Theme/Stores → Tools/Extensions`。
`MacMarkDown/Application` 只导入 `MacMarkDownKit`；框架从不导入 App 外壳，
CLI target 通过共享的 `UserDefaults` 交接套件（`Constants.cliHandoffSuiteName`）
与应用通信。

## 2. 分支命名

使用以下分支命名约定：

| 类型         | 格式                       | 示例                           |
|--------------|----------------------------|--------------------------------|
| 功能         | `feature/<简短描述>`       | `feature/toggle-bold-shortcut` |
| Bug 修复     | `fix/<简短描述>`           | `fix/line-prefix-empty-list`   |
| 热修复       | `hotfix/<简短描述>`        | `hotfix/crash-on-empty-doc`    |
| 重构         | `refactor/<简短描述>`      | `refactor/format-engine-split` |
| 文档         | `docs/<简短描述>`          | `docs/update-contributing-zh`  |
| 测试         | `test/<简短描述>`          | `test/add-auto-complete-tests` |

- 使用小写和 kebab-case。
- 保持描述简短但有意义（2-5 个词）。
- 不要在分支名称中使用 issue 编号（在提交信息中注明即可）。

## 3. Pull Request 要求

### 3.1 PR 模板

每个 PR 必须包含：

```markdown
## 摘要
变更的简要描述。

## 相关 Issue
Closes #<issue-number>

## 变更类型
- [ ] Bug 修复
- [ ] 新功能
- [ ] 重构
- [ ] 文档
- [ ] 测试
- [ ] 其他：___

## 变更内容
- 具体变更的要点列表

## 测试
- [ ] 所有现有测试通过
- [ ] 已添加新测试（如适用）
- [ ] 已完成手动测试（如有 UI 变更）

## 检查清单
- [ ] 代码符合项目风格指南
- [ ] 已完成自审
- [ ] 文档已更新（EN + ZH）
- [ ] 未引入新的警告
- [ ] 已验证并发模型合规性
```

### 3.2 PR 规则

1. **每个逻辑变更一个 PR。** 不要捆绑不相关的变更。
2. **标题格式**：`<type>: <description>`（例如 `feat: add highlight shortcut`）。
3. **不要对 `main` 进行 force push。** 使用功能分支。
4. **合并前至少需要 1 个审批。**
5. **CI 必须通过**（构建 + 测试 + 代码检查）。
6. **合并前解决所有评审意见。**
7. **使用 Squash merge** 合并到 `main`，保持历史清晰。

### 3.3 代码审查

审查者应检查：

- [ ] 逻辑正确性
- [ ] 并发安全性（`@MainActor` 隔离、`Sendable` 合规）
- [ ] 新代码的测试覆盖率
- [ ] 文档完整性（EN + ZH）
- [ ] 性能影响（尤其是编辑器操作）
- [ ] 无障碍合规
- [ ] 未提交密钥或凭证

## 4. 测试要求

### 4.1 覆盖率目标

| 领域         | 最低覆盖率 |
|--------------|------------|
| `Editor`     | 90%        |
| `Markdown`（解析器） | 95%  |
| `Preview`    | 80%        |
| `Document`   | 85%        |
| `Tools`/`Extensions` | 90% |
| 总体         | 85%        |

### 4.2 测试组织

`MacMarkDownTests` target 的测试采用扁平结构：每个领域一个文件，以被测类型或功能命名。

```
MacMarkDown/Tests/
├── MarkdownParserTests.swift      # 解析与元素模型
├── EditorFormattingTests.swift    # 格式命令
├── EditorOperationsTests.swift    # 字符串级变换
├── AttributedRendererTests.swift  # 原生预览渲染
├── PreviewRenderingTests.swift    # Renderer 输出与样式表
├── DocumentSessionTests.swift     # 文档生命周期
├── PreferencesTests.swift         # 偏好设置持久化
└── …                              # 每个领域一个文件
```

### 4.3 测试命名

```swift
func testToggleMarkup_wrappedInMarkers_removesMarkers() { ... }
func testToggleMarkup_plainSelection_addsMarkers() { ... }
func testIndentLines_orderedList_incrementsIndent() { ... }
```

模式：`<方法>_<条件>_<预期行为>`

### 4.4 测试内容

- **所有格式化操作**：每个 `EditorFormatCommand` case 的添加和移除场景。
- **所有按键处理路径**：每个快捷键和边界情况。
- **自动补全**：所有匹配字符对和冲突解决。
- **行前缀**：所有前缀类型（有序、无序、引用、任务）以及空列表结束的情况。
- **解析器扩展**：每个自定义语法扩展的有效和无效输入。
- **错误路径**：无效的文件操作、损坏的文档处理。

### 4.5 性能测试

对于编辑器操作，添加 XCTest 性能测试：

```swift
func testPerformanceToggleMarkupLargeDocument() {
    let largeText = String(repeating: "Hello world. ", count: 100_000)
    let selection = largeText.startIndex..<largeText.index(largeText.startIndex, offsetBy: 11)

    measure {
        for _ in 0..<100 {
            _ = EditorOperations.toggleMarkup(
                in: largeText, selectedRange: selection, prefix: "**", suffix: "**"
            )
        }
    }
}
```

目标：在 10 万字的文档上切换格式化操作不超过 50ms。

## 5. 文档要求

### 5.1 双语文档

所有文档必须同时用 **英文** 和 **中文（简体）** 编写。

| 文件               | EN 路径                     | ZH 路径                       |
|--------------------|-----------------------------|--------------------------------|
| 设计文档（RFC）    | `docs/design/rfc-*.md`      | `docs/design/rfc-*.zh.md`      |
| 指南               | `docs/guide/guide.md`       | `docs/guide/guide.zh.md`       |
| 贡献指南           | `docs/guide/contributing.md` | `docs/guide/contributing.zh.md` |
| 参考文档           | `docs/reference/*.md`       | `docs/reference/*.zh.md`       |
| 事后分析           | `docs/postmortems/*.md`     | `docs/postmortems/*.zh.md`     |

### 5.2 文档标准

- 使用清晰、简洁的语言。
- 为所有技术概念包含代码示例。
- 保持示例与当前 API 同步更新。
- 使用表格展示结构化数据。
- 在每个文件底部包含最后更新日期。
- 交叉引用相关文档。

### 5.3 API 文档

所有公共类型和方法必须有文档注释。内部实现细节可以使用普通注释。文档应说明：

- **功能**：API 做什么
- **使用场景**：何时使用
- **参数**及其含义
- **返回值**描述
- **抛出**条件（如适用）
- **示例**用法（对于复杂 API）

## 6. 提交信息

遵循 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

类型：`feat`、`fix`、`docs`、`style`、`refactor`、`test`、`chore`、`ci`

示例：

```
feat(editor): add highlight shortcut
fix(preview): keep scroll sync anchored on nested lists
docs(guide): update Chinese translation for setup section
test(editor): add auto-complete conflict resolution tests
refactor(markdown): extract inline marker handling in MarkdownParser
```

## 7. 获取帮助

- **Issues**：提交 GitHub issue 报告 bug 或功能请求。
- **Discussions**：使用 GitHub Discussions 进行讨论和设计对话。
- **代码审查**：在 Pull Request 中提及维护者，或开 Issue 请求审查。

## 8. 版本控制

- **本地模型配置不入库**：`opencode.jsonc` 与 `Opencode/` 模板包含本机模型与端点设置，均已列入 `.gitignore`，切勿提交。
- **`project.yml` 是唯一事实来源**：target、源码与构建设置都以它为准；`MacMarkDown.xcodeproj` 由 XcodeGen 生成。修改后请运行 `xcodegen generate`，并将两者一起提交。
- 构建产物（`.derived/`、`build/`、`DerivedData/`）一律不入库。

---

*最后更新：2026-09-15*
