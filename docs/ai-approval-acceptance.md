# AI approval 统一改版验收（2026-11-04）

## 交付范围

- React `components/ui/ai-approval.tsx` 与 Flutter `ui/ai_approval.dart` 统一纵向全宽选项、危险色、确认后的单行结果，以及失败重试。
- Web 与共用 React 的 Tauri、Flutter 的私聊/群聊均通过各自原有审批消息入口使用组件。仍调用原生 `approvals.respond`，不改变 Node/Relay/Hermes 的审批策略。
- 保留命令、审批范围、中英文、主题、历史状态和断线禁用。RPC 成功之前显示忙碌；拒绝、停止、失败和其他客户端确认后不重新开放选项。
- Web 沿用项目已有 Tailwind、TypeScript、shadcn 的 `components/ui` 目录、Motion 和图标组件；未新增依赖。参考里的 `framer-motion` 对应本仓库已安装的 `motion/react`。

## 已验证

- TypeScript typecheck、触及文件 ESLint/Prettier、Web production build 通过；构建保留现有的大 chunk 提示。
- 4 项浏览器组件行为检查：等待请求成功与重复点击、失败重试、无回调的独立使用、外部决策/停止状态/320px/深色与减少动画。
- 1 项 Edge 审批集成旅程：使用真实 NodeApplication、Relay、WebSocket 与已录制 Hermes 事件，覆盖私聊/群聊各自允许与拒绝；处理前刷新恢复选项，处理后刷新保留结果且没有按钮。测试账号、节点与端口隔离，不操作现有账号。
- 4 项 Flutter widget 测试通过；本模块 5 个 Dart 文件 analyze 无问题；Windows Release 构建成功。
- agent-browser 实际打开候选 Web，检查桌面浅色、390px 手机深色和减少动画的组件预览；截图人工检查通过。深色危险色局部调亮以保证可读性。

## 验收边界与未通过检查

- 上述集成旅程使用 `fake-hermes` 的已录制事件，属于辅助回放，不代表官方 Hermes/真实模型审批通过。
- 本机真实 Relay/Node 与官方 Hermes 在线，但账号没有配置模型服务，未创建模型 Bot 或触发真实模型审批。真实模型链路仍待有效配置。
- 两条原有全流程浏览器旅程在审批前失败：私聊欢迎 run 数期望 1 实际 0，群聊接力 run 数期望 4 实际 2。未改动这些既有行为；失败输出留在本机，独立审批旅程通过。全流程用例未作为本模块通过依据。
- 最初复用了其他 checkout 的 4318 开发服务，导致新组件 404；改用当前工作区的 4328 服务后组件检查通过。服务端集成测试在 Node 24 下需 `NODE_OPTIONS=--import=tsx` 处理仓库现有 JSON import。
- 未执行 Windows 原生 GUI 的真实审批旅程；Android 模拟器/真机、macOS、Linux、Tauri 宿主未重建验收。Windows 构建不代表设备交互验收通过；未替换已安装包、未发布或 push。

## 复验入口

启动本工作区开发服务后，在 PowerShell 设置 `PLAYWRIGHT_WEB_PORT` 指向该端口，设置 `NODE_OPTIONS=--import=tsx`，执行：

```text
pnpm exec playwright test tests/browser/ai-approval.spec.ts tests/browser/approval-chat.spec.ts --workers=1
node .runtime/local-deployment/windows-tool.mjs flutter test test/ai_approval_test.dart --no-pub
```

第二条为本机已有 Flutter 依赖入口；其他环境可通过 `scripts/flutter.mjs` 与相应 `FLUTTER_ROOT` 使用相同测试。
