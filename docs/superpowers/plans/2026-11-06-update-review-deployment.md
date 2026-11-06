# 最新更新审查、完善与部署实施计划

> **For agentic workers:** Use `executing-plans` to implement this plan task-by-task in the current session. The user has authorized review, improvements and deployment.

**Goal:** 审查当前更新、收尾未完成的补丁整合，验证候选后部署到本机。按用户本次要求，部署范围为本地环境。

**Architecture:** 沿用现有 Web / Flutter、Relay、Node 与官方 Hermes 架构。保留工作区原有官网文案及其他工作树，只集成已审查的修复。

**Tech Stack:** Node 24、pnpm 10、React、Flutter、Playwright / Edge、Docker Compose。

## Global Constraints

- 不删除文件、不提交私有数据；现有账号、数据库、Hermes profiles 和其他服务须保留。
- 真实浏览器、Node / Relay / 官方 Hermes / 真实模型验收，与回放测试分别记录。
- Android 仅复用 `NekodotNativePhase3`；没有相应环境的链路不记为通过。
- 每个完成模块更新 `Summary.md`、`docs/progress.md` 并单独本地提交。

## Task 1: 审查与集成遗漏修复

- [x] 基线 TypeScript 复现合并冲突错误，修正后执行 `pnpm lint`、`pnpm typecheck`、`pnpm test`、完整 build。
- [x] 审查旧节点更新提示的既有失败证据，收尾提交 `26d5b39fbd` 的 cherry-pick；专项 Edge 旅程通过，本地提交 `1dba4f62b1`。
- [x] 核对提交 `428cb9064b`：当前分支已包含 `TextFieldTapRegion` 与四项点击回归，不重复应用；本轮复跑验证。
- [x] 分别复跑 Node 更新 Edge 旅程、完整 store / TypeScript 与 Flutter 测试，更新模块记录并本地提交。

## Task 2: 候选真实验收与构建

- [x] 全量 lint / typecheck / test / build、Edge 回放（24通过/10跳过）、Flutter analyze / test通过；追查并修正两处验收脚本误判。
- [x] 本次 Web 候选连接真实 Node / Relay 与官方 Hermes，真实私聊与两轮群聊验收通过；Windows同源码 Debug 原生旅程完整通过。
- [x] 保留用户原有官网文案，本轮不做官网视觉改版或宣称官网全矩阵复验。
- [x] 构建连接本地 Relay 的 Windows Release 与未签名本地安装包；不改发布签名、不创建正式密钥。

## Task 3: 部署与交付

- [x] 确认本地服务与客户端，备份数据库/节点身份/私有配置、旧安装目录及安装包；Hermes profiles 原样保留。
- [x] 更新并重启本地 Web / Relay / Node，安装与启动 Windows Release；40个文件核对一致，账号/节点/Bot/群组/会话/模型来源保留。CUA 截图被产品策略阻止，未绕过。
- [x] 在 `docs/update-review-deployment-2026-11-06.md`、`Summary.md`、`docs/progress.md` 记录实际结果、版本和未验范围，并随验收完善模块本地提交。
