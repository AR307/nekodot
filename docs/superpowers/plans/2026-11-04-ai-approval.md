# AI approval Implementation Plan

**Goal:** 将用户提供的 AIApproval 视觉和确认后收起交互应用到全部产品审批消息。

**Architecture:** Web 与 Flutter 各维护一个共享展示组件，私聊与群聊复用现有消息入口。网络请求和持久化仍使用 approvals.respond，组件在请求成功后呈现结果。

**Tech Stack:** React 19、TypeScript、Tailwind 4、motion/react、Flutter。

## Constraints

- 保留现有主题、中英文、审批选项与 Hermes 原生权限行为。
- 保留工作区已有的登录页修改；仅提交本任务拥有的文件或差异。
- 不删除用户文件，不提交凭证和运行数据，不发布或 push。

## Steps

- [x] 为共享审批组件增加异步成功、失败重试、重复提交、历史结果与窄屏检查。
- [x] 在 React 的 components/ui 中实现 AIApproval，并接入 chat.tsx 的唯一审批消息入口；独立样式不干扰 question-card。
- [x] 实现 Flutter AIApproval 并从原有审批分支调用；模型提问继续使用原有分支。
- [x] 运行 TypeScript、Web 构建、受影响 ESLint/Prettier、Flutter analyze 和组件测试。
- [x] 使用候选客户端执行浏览器检查与审批回放，记录真实模型缺少配置及设备验收边界；见 docs/ai-approval-acceptance.md。
- [x] 更新 Summary.md、docs/progress.md；核对差异并作独立本地提交。
