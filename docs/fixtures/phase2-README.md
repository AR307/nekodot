# Phase 2 群聊录制

这些 SSE 与状态资料来自隔离 WSL Hermes 的真实自定义 API，非手写模型回复。提供方配置、密钥及个人目录已脱敏，实际临时现场留在本地忽略目录。

| 文件前缀 | 真实行为 |
| --- | --- |
| group-lead | 无有效提及，主答返回 PHASE2_LEAD_OK |
| group-target-1 / 2 | 用户按 Writer、Researcher 顺序指定成员 |
| group-researcher / writer | Researcher 最终文本 @writer，Writer 接力 |
| group-self-outsider | 自身与非成员提及，不产生额外回合 |
| group-loop-researcher / writer | 两位成员相互提及；Node 在六回合停止队列 |
| group-steer | terminal 执行中原生 steer，同一 run、一次工具与文件效果 |
| group-stop | 工具中停止，真实 cancelled |
| group-failed | 隔离提供方连接错误，真实 run.failed；后续成员继续 |

回放服务的 `additionalFixtures` / `scenarioFor` 只用于测试选取录制场景。它不合成成功回复，产品启动链路不导入回放服务。原 Hermes 错误输出中的建议作为原始事实保留，不表示 nekodot 增加了对应功能。
