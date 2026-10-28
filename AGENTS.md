# nekodot 开发约定

- 产品仓库独立于 Hermes，集成只使用官方 CLI/API。
- 一个 Bot 对应一个独立 Hermes profile；私聊直接使用该 profile 的原生单 agent 运行、技能、记忆和工具循环，不另建 agent 引擎。
- nekodot 只负责产品界面、连接、消息同步与群聊接力路由；群聊每轮仍调用对应 profile 的 Hermes。新建 profile 保留 Hermes 默认技能初始化。
- 参考索引：docs/references/README.md。技术以原 PDF 为准，视觉以原 HTML 为准。
- 简单、模块化实现；外部输入在边界校验一次；不添加运行时 fallback 或兼容层。
- 每个完成模块更新 Summary.md、docs/progress.md，单独做本地 commit。
- 不提交凭证、私有配置、运行目录或原始未脱敏响应。
- 不删除文件；确需移除先报备并取得授权，再移到回收站。
- 真实使用场景和浏览器验收不可被单元测试替代。
