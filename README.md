# nekodot

面向非技术用户的多智能体小队。当前是 Phase 0 工程基础，不包含聊天或配对业务。

## 开发

要求 Node 24 LTS、pnpm 10.34.5；浏览器验收当前使用本机 Microsoft Edge。

```
pnpm install
pnpm dev
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm test:e2e
```

Web：http://127.0.0.1:4318；Relay 健康检查：http://127.0.0.1:4319/health。
Windows 当前项目自带忽略的 Node 24，可在 PowerShell 运行 . ./scripts/activate.ps1。
真实 Hermes spike 在 WSL Ubuntu 24.04 执行；使用方法见 docs/hermes-notes.md。

参考索引见 docs/references/README.md；阶段结果见 docs/progress.md。
复制 .env.example 为 .env 后填入真实 provider。不要提交密钥或运行目录。

## Phase 0 验收

- 全新检出安装、lint、类型检查、13 项业务协议/SSE/HTTP 场景和全部构建通过。
- 实际 Edge 的桌面、语言切换、手机布局旅程通过并留图。
- 自定义 API 的真实文本、工具、审批允许、审批拒绝、执行中停止五项通过。
- 七项 Hermes 调查及复现命令见 [docs/hermes-notes.md](docs/hermes-notes.md)；
  完整验收记录见 [docs/progress.md](docs/progress.md)。
- [测试回放服务](packages/fake-hermes/README.md) 只供自动化测试，产品运行链路不接入它。

原 HTML 原件与九块静态参考已保留；原稿视觉核对仍受查看方式限制。
本阶段提供工程基础页面，完整聊天和参考界面还原留待 Phase 1。
