# nekodot 实施计划

原始技术稿和视觉稿见 docs/references/README.md。

## Phase 0：骨架与 Hermes 接入验证

0.0 完整保留两份原件，建立私有初始 GitHub 归档、Summary.md 和进度记录。
0.1 Node 24 / pnpm workspace：web、relay、node、protocol、fake-hermes；
TypeScript strict，ESLint/Prettier，Vitest，CI lint/test/build。
0.2 按原稿第 7 节实现 Zod 协议和真实业务合法/非法样例。
0.3 WSL Ubuntu 24.04 隔离 Hermes 环境：真实回复、工具、审批允许/拒绝和停止，
回答七项 CLI/API 调研问题，保留脱敏 SSE/状态证据。
0.4 仅测试使用的 HTTP 回放服务：health、runs、events、state、stop、approval。
0.5 lint/typecheck/test/build、浏览器实际访问留图、真实自定义 provider 验收。

使用独立 D:/nekodot-app；D:/nekodot 作为 Hermes 参考。
真实 provider 为自定义 OpenAI-compatible API，endpoint/model/key 在本地 .env 输入。
凭证不进入 Git、日志或 fixture。每个完成模块独立本地提交，后续不自动推送。
Phase 1 才实现注册配对、私聊和正式 UI；群聊和电脑接管在后续阶段实现。

完整后续阶段内容见原 PDF 和全页文本提取，不以本摘要替代原件。
