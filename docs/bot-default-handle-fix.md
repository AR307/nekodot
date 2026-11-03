# 新建 Bot 默认名称代号修复

## 原因和行为

2026-11-03，用户在 Android 新建 Bot 时没有填写 `@handle`。原协议要求 1–24 个小写英文、数字或连字符，表单没有默认值，因此 Node 返回泛化的 `Invalid RPC arguments`，无法完成创建。

- 新建可以省略或留空 handle，由 Node 按名称生成，保留中文，统一大小写并整理空格/标点；同名依次使用 `-2`、`-3`。
- Flutter 新建表单随名称填入预览；用户手动修改后保留其选择。最终唯一代号以 Node 的创建结果为准。
- 已有 Bot 改名不自动改变代号。手动输入支持中文，前导 `@` 和英文大小写会规范化。
- 群聊提及识别同一字符范围；原有顺序、去重及 `@everyone` 保留。
- 参数错误返回字段路径与校验说明，例如 `params.model`；不把请求内容或凭据写入日志。

## 真实旅程

环境为固定 `NekodotNativePhase3` Android 模拟器、隔离的真实持久化 Node/Relay、官方 Hermes v0.22.5、既有自定义 API 的 `gpt-6.1-sol`。没有使用 fake Hermes、录制回复或固定欢迎文案替代本次真实结果。

1. 在实际 Flutter BotEditor 输入中文名称，不触碰 handle；检查名称自动填入代号。
2. 模型留空保存，显示具体 `params.model` 错误，表单仍在；填入已有真实模型后保存成功。
3. 读回真实 Bot/profile/session，并等待实际 Hermes 欢迎回复完成。
4. 新建群聊，将另一个 Bot 设为主答，显式提及新建 Bot 的中文代号；实际完成回复的作者为新 Bot。

最终通过记录见 `evidence/bot-default-handle-android.json`。初期驱动的控件定位/等待错误，以及过度要求模型固定文本的失败记录，保留于私有验收目录；测试角色和断言已调整为检查实际路由结果。未把这些失败称为产品通过，也未删除其现场。

辅助检查为协议、提供方/建 Bot、群聊及连接四文件共 11 项测试通过；其中连接测试还通过真实 TCP/Relay 验证握手恢复。TypeScript、限定文件 ESLint、Flutter analyze 通过。真实模型与原生客户端结果单独记录；本次没有 Android 真机或 Windows GUI 复验。

## 部署与交付范围

- Node 补丁版本 `20261103042820` 已更新现有正式下载分发，并安装到本次故障 VPS。
- 更新前检查节点无活跃私聊/群聊任务；只重启该节点服务。更新后确认 active/running、NRestarts=0 和 online=true。
- 旧程序保存在各自版本目录的 backup；账号、nodeId、数据库、profiles、历史和浏览器资料保留。未重启 Relay、Caddy、其他产品或整机。
- 当前已安装手机版留空 handle 即可创建，无需重装。新表单的实时自动填入显示已在候选中验证，但本次未发布新 APK/EXE。
- 产品源码与文档只作本地 commit，不 push。
