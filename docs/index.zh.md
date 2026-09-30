# MacMarkDown — 文档索引

> **版本**: 1.0.0 | **日期**: 2026-10-01 | **平台**: macOS 26+

## 概述

MacMarkDown 是一款用纯 Swift 与 SwiftUI 从零构建的原生 macOS Markdown
编辑器。macOS 26 与 Swift 6.4 为 Apple 的开发生态开启了新纪元：SwiftUI、
Observation、TextKit 2 与 Swift 并发已经成熟到足以承载一个完整、高性能的
写作工具。MacMarkDown 正是为这个新纪元而写，本文档体系描述它的设计、构建、
测试与维护方式。

## 文档目录

### 架构

| 文档 | 描述 |
|------|------|
| [ADR-001: 纯 SwiftUI 架构](architecture/adr-001-pure-swiftui.zh.md) | 使用 SwiftUI 构建全部 UI 的决策 |
| [ADR-002: Swift Markdown 解析器](architecture/adr-002-swift-markdown.zh.md) | 使用 Apple 官方 swift-markdown 的决策 |
| [ADR-003: 原生预览渲染](architecture/adr-003-native-preview.zh.md) | 使用原生方式渲染预览的决策 |
| [ADR-004: 编辑器主题系统](architecture/adr-004-editor-themes.zh.md) | 使用 Swift 定义编辑器主题的决策 |

### 业务

| 文档 | 描述 |
|------|------|
| [产品概述](business/overview.zh.md) | 产品目标、范围和路线图 |

### 设计

| 文档 | 描述 |
|------|------|
| [RFC-001: 核心架构](design/rfc-001-core-architecture.zh.md) | 系统架构和组件设计 |
| [RFC-002: 渲染管线](design/rfc-002-rendering-pipeline.zh.md) | Markdown 到原生视图的渲染管线 |
| [RFC-003: 编辑器集成](design/rfc-003-editor-integration.zh.md) | 编辑器设计和按键处理 |

### 指南

| 文档 | 描述 |
|------|------|
| [开发指南](guide/guide.zh.md) | 环境搭建、构建和开发流程 |
| [贡献指南](guide/contributing.zh.md) | 如何参与贡献 |

### 参考

| 文档 | 描述 |
|------|------|
| [Swift 26 合规审计](reference/apple-swift-26-compliance-audit.zh.md) | Swift 6.4 严格并发检查审计 |

### 事后分析

| 文档 | 描述 |
|------|------|
| [2026-09 现场事故](postmortems/2026-09-field-incidents.zh.md) | 风险、事故与解决方案 |

## 快速链接

- **源代码**: `MacMarkDown/` 目录
- **测试**: `MacMarkDown/Tests/`
- **脚本**: `scripts/`

## 约定

所有文档均提供英文版（`.md`）和中文版（`.zh.md`）。
