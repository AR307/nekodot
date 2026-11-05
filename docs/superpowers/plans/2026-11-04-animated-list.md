# Animated List Implementation Plan

> **For agentic workers:** Execute inline using executing-plans. This is one shared UI module; no parallel delegation.

**Goal:** 所有 React 业务列表统一采用指定的 ReactBits Animated List 动效。

**Architecture:** 共享 AnimatedList 直接承载原有行元素，以 IntersectionObserver 支持页面和嵌套滚动，以 ResizeObserver/MutationObserver 同步尺寸与动态行。沿用 ReactBits 的弹性过渡、错位和边缘遮罩，主题由现有 CSS 变量提供。

**Tech Stack:** React 19、TypeScript、CSS、Playwright / Edge。

## Global Constraints

- 保留未提交的聊天、审批与原生端改动。
- 不修改认证、Relay、Node、Hermes、消息顺序或业务选择语义。
- 无新依赖；减少动效关闭移动/缩放；不删除文件。

## Steps

- [x] 添加 `tests/browser/animated-list.spec.ts`，用真实组件验证滚动时可见、插入/删除后行可见、行内复选框保留和减少动效；先运行确认组件缺失导致失败。
- [x] 添加 `apps/web/src/components/ui/animated-list.tsx` 和 `apps/web/src/styles/animated-list.css`，按设计适配上游动效；重新运行测试。
- [x] 将设计中列举的业务列表容器替换为 AnimatedList；去除侧栏原来重复的入场动效，保留选中高亮。
- [x] 执行 `pnpm typecheck`、相关 ESLint/Prettier、`pnpm --filter @nekodot/web build`、组件和现有业务浏览器旅程；实际浏览器检查桌面、手机、明暗主题。完整群聊/提供方旅程的运行次数及 HTTP 400 边界详见验收记录，未标为全通过。
- [x] 连接可用的真实 Node/Relay，记录真实 Hermes/模型链路及未验边界，更新 Summary.md、docs/progress.md，检查 diff 后仅提交本模块。
