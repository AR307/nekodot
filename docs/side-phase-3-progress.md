# Side Phase 3 实施与验收

## 范围

本阶段目标为 Flutter Windows / Android 原生客户端与账号、提供方、交互、记忆、扩展、通知更新。旧客户端与线上服务在新客户端实际验收前保持可用；此文档不表示 0.2.0 已完成或发布。

## 3.4 原生提问与输出恢复

- `clarify` 与执行审批分开建模，问题的普通选项不再进入审批枚举。使用原生 `requestId`、`execution_generation` 和当前 `runId` 提交 `/clarify`，不转换成聊天或 steer。
- Hermes 等待提问时 run 仍为 `running`，Node 根据 `pending_controls.kind=clarify` 恢复问题。新建与已存在 profile 的 API toolset 显式包含 Hermes 原生 `clarify`。
- SSE 断流保留文本并显示重新连接；续接同一 run，不重新执行任务。协议解析错误、运行失败、输出终止均显示原因并结束遗留的运行中卡片。
- 真实模型验证：隔离 WSL / Hermes home 中，提问 Amber / Teal，回答 Amber 后相同 run 完成，实际输出 `NEKODOT_CLARIFY_OK Amber`。命令入口为 `scripts/spike-clarify.ts`；脱敏事件与状态在 `docs/fixtures/runs-clarify.*`。
- 自动化：Node 覆盖等待问题时禁止普通发送、回答、重复回答拒绝；Edge 完整私聊旅程覆盖提问中刷新、Node 重建、草稿保留、回答及同 run 完成。截图 `docs/evidence/side-phase3-clarify-answered.png` 是浏览器回放证据，不冒充真实模型截图。
- 本轮复测：TypeScript 检查通过，15 文件 / 27 项测试通过。完整 Edge 4 项通过，真实 Linux 屏幕项因缺少本轮私有现场跳过。Flutter analyze 通过；Flutter 实际原生旅程另行记录。

## 尚未完成

- 外部 SMTP、真实授权服务、账号级 USER 记忆、Bot 欢迎回合、扩展元数据与原生通知仍需逐项验收。
- Flutter 页面已进入开发，但未实现的服务端接口与原生构建障碍尚未全部解决，不能切换产品或发布安装包。
- Windows 完整构建、Android 真机、原生屏幕输入、跨设备共享记忆及外部收码不得以代码检查或浏览器手机尺寸替代。
