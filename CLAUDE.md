# 驭Git（Yugit）

AI 原生 + 中文界面的 macOS 原生 Git 客户端。Slogan：「AI 帮你写代码，驭Git 帮你驾驭它」。Bundle ID `com.chenya.yugit`。

## 现状（2026-08-12）

需求阶段完成，**尚未开始编码**。实现计划在 `~/.claude/plans/macos-app-mighty-kahn.md`，其中 M0–M4 里程碑需按 PRD 的版本节奏（v0.1→v0.5→v1.0→v2.0）更新后再开工。

## 必读文档

- `docs/01-竞品调研与功能设计.md` — 13 款竞品的精华/糟粕分析、8 个差异化设计的依据
- `docs/02-产品需求文档.md` — PRD：定位、目标用户、分版本功能需求、AI 设计铁律、非功能指标、商业模式

## 关键决策（已与用户确认，勿擅自推翻）

- Swift + SwiftUI/AppKit 原生，目标 macOS 14+；提交历史列表和 diff 视图这两处用 AppKit 保性能，其余 SwiftUI
- Git 引擎：调用系统 git CLI + porcelain 解析（`-z` + `core.quotepath=false`），**不用 libgit2/SwiftGit2**
- AI：用户自带 API Key（OpenAI 兼容 + Anthropic 双协议），Key 存 Keychain；所有 AI 动作可预览、可编辑、可撤销
- 商业模式：本地 Git 全功能永久免费（含私有仓库），绝不对基础功能收订阅
- 分发：Developer ID 签名 + 公证，不开沙盒，暂不上 App Store

## 协作约定

- 全程用中文沟通；Git 术语保留英文
- 用户是资深全栈开发者，但正在边学 Swift 边做——涉及 Swift/SwiftUI 特有概念时适当多解释一句
- 工程质量：每修一个 git 边缘 case 补一个 fixture 测试；性能指标见 PRD 第 5 节
