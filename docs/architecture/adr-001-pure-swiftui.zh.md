# ADR-001：使用纯 SwiftUI 构建所有 UI

## 状态

**已采纳** — 2026 年 9 月

## 背景

macOS 26 与 Swift 6.4 为 Apple 的开发生态开启了新纪元：SwiftUI、Observation、TextKit 2 与 Swift 并发已经成熟到足以承载一个完整的写作工具。因此，MacMarkDown 用纯 Swift 与 SwiftUI 从零写成，并且只面向 macOS 26 及更高版本。

这一基础为 UI 层留下一个需要明确的问题：SwiftUI 与 AppKit 的边界应该划在哪里？在 macOS 26 上，这个答案不再受兼容性限制左右。场景、窗口、工具栏、菜单、设置与布局都有完整的 SwiftUI 表达方式，因此只有在 SwiftUI 完全没有对应能力的地方，使用 AppKit 才是合理的。

Markdown 编辑器中有两类文本表面符合这一条件：

- **编辑器表面**需要 SwiftUI 内建的 `TextEditor` 不提供的文本布局与编辑控制：按词法着色的语法高亮、行号、精细的选区与滚动控制、拖放、拼写检查以及智能编辑钩子。
- **预览文本表面**需要只读文本视图，以支持整篇选择、拷贝 HTML，以及可供滚动同步直接测量的文本布局位置。

两者都需要 TextKit 2 文本视图，而 TextKit 2 文本视图属于 AppKit。

## 决定

MacMarkDown 的所有 UI 均以**纯 SwiftUI** 实现：

- **不使用任何 XIB 或 NIB 文件**，Interface Builder 流程不属于本项目的构建。
- **不基于视图控制器搭建窗口布局**。窗口与面板是 SwiftUI 场景与视图，而不是控制器层级。
- **场景**使用 `WindowGroup` 承载文档窗口、`Settings` 场景承载偏好设置；应用菜单通过 `.commands { }` 修饰符声明。
- **工具栏**通过 `.toolbar { }` 修饰符与 `ToolbarItemGroup` 声明。
- **状态绑定**使用 `@State`、`@Environment`、`@Bindable`，以及 Observation 框架的 `@Observable` 类；不存在插座或动作连接。
- **分栏布局**直接在 SwiftUI 中组合：两个面板位于 `HStack`，中间是可拖拽分隔条，并支持编辑器左右位置、面板显隐与分栏比例等偏好。

### 有意保留的 AppKit 桥接

文本表面是唯一刻意使用 AppKit 的地方：

- 编辑器是 `MarkdownTextView`——一个 TextKit 2 文本视图，由 `MarkdownEditorView` 通过 `NSViewRepresentable` 承载。
- 预览的文本表面是 `MarkdownPreviewSurface`，基于同一个 TextKit 2 文本视图，并以相同方式桥接。

文本表面之外的一切——窗口外观、面板布局与分隔条、工具栏、菜单栏、查找栏与设置——都是 SwiftUI。

### 视图架构

```
MacMarkDownApp（SwiftUI App）
├── WindowGroup("MacMarkDown")
│   └── ContentView → DocumentView
│       ├── 编辑面板   → MarkdownEditorView → MarkdownTextView（NSViewRepresentable）
│       ├── 分栏分隔条 → SwiftUI 拖拽手势
│       └── 预览面板   → MarkdownPreviewSurface（NSViewRepresentable，TextKit 2）
│                     → MarkdownView（SwiftUI 元素树，由偏好开关控制）
├── Settings 场景      → SettingsView
└── .commands          → 文件 / 编辑 / 格式 / 插件菜单
```

### 状态管理

状态存放在 `@Observable` 类中，通过 SwiftUI 环境注入：

- `MarkdownDocument` 持有文档文本、文件 URL、保存状态以及子服务（`MarkdownParser`、`RenderService`）。
- `Preferences` 持有编辑器、预览与渲染相关设置。
- 视图通过 `@State`、`@Environment` 与 `@Bindable` 读写状态；Observation 跟踪机制负责传播模型变更，无需手写通知管线。

## 备选方案

### 1. AppKit + Storyboard/XIB
用 AppKit 与 Interface Builder 文件构建 UI。**已否决**：XIB 合并冲突代价高，插座断连只能在运行时暴露，且无法利用 macOS 26 已经成熟的声明式、响应式模型。

### 2. 无 XIB 的编程式 AppKit
用 `NSStackView`、Auto Layout 约束与控制器类构建每个界面。**已否决**：虽然消除了 XIB 合并冲突，但仍需维护控制器样板代码，也没有编译期绑定安全；同样的界面在 SwiftUI 中代码更少，并能随状态变化自动更新。

### 3. SwiftUI + 大范围 AppKit 回退
采用 SwiftUI，但分栏视图、工具栏与菜单也桥接 AppKit。**已否决**：在 macOS 26 上这些界面 SwiftUI 都能覆盖，大范围回退会在不存在能力缺口的情况下维护两套 UI 范式。真正需要 AppKit 的只有文本表面。

### 4. 仅用 SwiftUI 的文本编辑（`TextEditor`）
编辑器面板直接使用 SwiftUI 的 `TextEditor`。**已否决**：`TextEditor` 无法提供 Markdown 编辑器所需的布局、样式与事件控制。用 `NSViewRepresentable` 封装 TextKit 2 视图，是让应用外壳保持 SwiftUI 的最小桥接。

## 影响

### 积极影响

- **声明式 UI** — 视图是状态的可组合函数；新增偏好或视图变体通常只是一处局部修改。
- **编译期安全** — 绑定经过类型检查，不存在只能在运行时发现的连接失败。
- **更少样板代码** — 在 AppKit 中需要控制器类与多个生命周期回调的界面，在 SwiftUI 中通常只需其一小部分代码。
- **实时预览** — SwiftUI Previews 让 UI 迭代无需启动完整应用。
- **统一的状态模型** — Observation 类与 SwiftUI 属性包装器提供一致的读写应用状态方式。
- **主题能力** — 深色/浅色适配与动态字体由 SwiftUI 颜色与字体系统提供（`.foregroundStyle(.primary)`、`.background(.background)`），应用自身的主题体系在此之上叠加。

### 消极影响

- **文本表面桥接复杂** — `MarkdownEditorView` 与 `MarkdownPreviewSurface` 需要协调器在 AppKit 文本系统与 SwiftUI 状态之间同步文本存储、选区、高亮与滚动指标。这是 UI 层最精细的部分。
- **功能协同** — 行号栏、查找栏、滚动同步、拖放目标等高级功能都需要文本系统与 SwiftUI 状态之间的显式协同。
- **调试不透明** — 出现布局问题时，SwiftUI 的更新与差分管线比显式的 AppKit 布局代码更难推理。

### 风险

- SwiftUI 的 API 会随 macOS 版本演进。仅面向 macOS 26 限定了初期范围，但未来的系统升级仍可能需要适配。
- `NSViewRepresentable` 文本表面是长期存在的互操作边界。如果 Apple 推出控制力相当的编辑 API，应重新评估该桥接。

## 参考

- Apple SwiftUI 文档：https://developer.apple.com/documentation/swiftui
- Observation 框架：https://developer.apple.com/documentation/observation
- TextKit 2：https://developer.apple.com/documentation/textkit
- WWDC 2025 Session "What's new in SwiftUI"
- 应用代码：`MacMarkDown/Application/MacMarkDownApp.swift`、`MacMarkDown/UI/Shared/Document/DocumentView.swift`、`MacMarkDown/UI/macOS/Editor/MarkdownEditorView.swift`、`MacMarkDown/UI/macOS/Editor/MarkdownTextView/MarkdownTextView.swift`、`MacMarkDown/UI/macOS/Preview/MarkdownPreviewSurface.swift`
