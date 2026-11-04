# nekoDOT 开发约定

- 产品仓库独立于 Hermes，集成只使用官方 CLI/API。
- 一个 Bot 对应一个独立 Hermes profile；私聊直接使用该 profile 的原生单 agent 运行、技能、记忆和工具循环，不另建 agent 引擎。
- nekoDOT 只负责产品界面、连接、消息同步与群聊接力路由；群聊每轮仍调用对应 profile 的 Hermes。新建 profile 保留 Hermes 默认技能初始化。
- 参考索引：docs/references/README.md。技术以原 PDF 为准，视觉以原 HTML 为准。
- 简单、模块化实现；外部输入在边界校验一次；不添加运行时 fallback 或兼容层。
- 每个完成模块更新 Summary.md、docs/progress.md，单独做本地 commit。
- 不提交凭证、私有配置、运行目录或原始未脱敏响应。
- 不删除文件；确需移除先报备并取得授权，再移到回收站。
- 真实使用场景和浏览器验收不可被单元测试替代。
- 默认进行真实验收：使用本次候选客户端、对应真实 Node/Relay、官方 Hermes 与真实模型。用户已允许必要的模型调用，不因费用缩减验收；单元测试和回放仅作辅助，不作为真实验收通过的依据，未验的设备与链路明确说明。
- Android 模拟器固定复用现有 `NekodotNativePhase3`，用 `pnpm native:emulator` 启动或复用；不按阶段新建 AVD，不 wipe-data，不动其他项目的模拟器。真机与模拟器结果分开记录。
