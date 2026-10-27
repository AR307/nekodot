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
Phase 1 实现注册配对、私聊和正式 UI；群聊和电脑接管在后续阶段实现。

## Phase 1：私聊闭环与正式界面

- 1.1 Relay：账号、30 天 JWT、8 位单次配对码、nodeToken 摘要、WebSocket 路由、在线状态与解绑。
- 1.2 Node：pair/run 命令、SQLite 事务事件、隔离 Hermes 生命周期、退避重连与已知 run 恢复。
- 1.3 提供方与 bot：OpenRouter/自定义 API、hub 模型目录、独立 profile、唯一私聊、编辑与逻辑归档。
- 1.4 私聊：clientMsgId 去重、流式快照、工具与审批、停止、同 run 原生 steer、Last-Event-ID 续接。
- 1.5 Web：正式设计 tokens、猫耳头像、响应式团队与私聊、配对、设置、中英与主题；按节点隔离同步。
- 1.6 验收：真实录制回放支撑自动化，实际自定义 API 单独验收，保留浏览器截图与 WSL 现场。

按 1.1 → 1.6 逐模块实现和本地提交。技术/数值以 PDF 为准，布局/视觉以静态 HTML 参考为准。
消息 offset 使用 JS 字符串位置；同 run steer 成功才落新用户气泡，不停止重开、不自动补跑未消费指令。
computerUse=false，不显示群聊和屏幕入口。完整验收、证据和限制见 docs/progress.md。

完整后续阶段内容见原 PDF 和全页文本提取，不以本摘要替代原件。
