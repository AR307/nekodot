# Side Phase 5：Hermes 命令适配

基线：官方 Hermes v0.22.5。一个 Bot 一个 profile；聊天、派生、工具及压缩由 Hermes 执行。

## 模块与入口

| 模块        | 产品入口                                                                                  | 官方能力                                                                              |
| ----------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| 会话        | `/new /clear /resume /sessions /branch /undo /retry /compress /save`                      | canonical session create/list/history/resume/mutate/export                            |
| 运行控制    | `/agents /steer /stop /bg /btw`                                                           | subagent、process、session.steer、原生 detached prompt；主回合 Stop 与 `/stop` 不混用 |
| 工具/环境   | `/tools /reload-mcp /reload-skills /reload /browser /wake`                                | profile 工具配置、原生 reload/browser/wake 状态                                       |
| 主机与资料  | `/logs /snapshot /export /import /worktree /update`                                       | 官方日志、备份、profile archive、Git worktree、更新检查                               |
| 原生资料    | `/journey /pet /hatch /subscription`                                                      | 实际学习条目、宠物目录/生成状态、Nous 订阅状态                                        |
| 本机        | `/copy /image /paste /focus /density /timestamps /statusbar /battery /skin /redraw /quit` | 当前客户端的剪贴板、附件、外观、实际电量、重同步及原生后台入口                        |
| 页面/编辑器 | `/config /model /plugins /login /prompt /palette`                                         | 打开已有 Flutter 页面、当前输入框或指令栏                                             |

- 会话切换改变下一条输入的 Hermes 上下文，不删除 nekodot 历史；undo 不撤销实际工具副作用。群聊与私聊沿用同 Bot 原有持久 Hermes 会话设计。
- `/model <id> [--provider name] [--reasoning level]` 使用原生会话 mutation；不带参数打开 Bot 持久配置。状态栏标注 Bot 配置，避免把配置模型误称为实际会话覆盖。
- native profile 导出由 Hermes 排除凭据；完整备份可能含私有状态，界面明确提醒。文件沿用认证资料库，不接受客户端传入任意服务器文件路径。
- Skills、Quick Commands 与插件目录继续动态发现，由原生命令 handler/dispatch 执行。没有聊天执行 URL 或任意 shell 代理。

## 已复现问题与修正

1. `commands.catalog` 汇总多个原生界面的目录，不等于 `slash.exec` 支持列表。为有 App 意义的会话、设备和主机能力补对应接口，而非盲目发送命令。
2. v0.22.5 的 `tools.configure` 没有正确绑定传入 profile，真实写入探测复现。改用官方 profile-scoped toolset REST writer；MCP 仅合并目标工具的 exclude 列表，不复制被遮罩的凭据。
3. `wake.status` 是 profile-scoped 方法，真实调用拒绝多余 session_id。参数按实际原生 contract 发送；不启动听不到 App 麦克风的服务器监听器。
4. 子 Agent 回投与新用户输入共用 canonical session 事件流。原代码把整个事件流投影到当前 run，真实出现下一次回复被后台结果抢先结束。现在按原生 admission ID 匹配帧，保留当前实际 generation；同一真实旅程重新运行通过，不重跑旧任务。
5. 子 Agent 与进程列表原先只显示说明，用户无法获得 tail/steer/stop 所需 ID。现在显示原生标识与状态。

## 明确边界

- 目录实际 152 条：52 App 适配、97 原生/动态条目、2 纯终端设置、1 canonical 不支持。数字表示接入分类，不表示 149 条的全部参数均已执行。
- `/handoff`：此版本 canonical 明确不支持；不走 legacy 会话路径伪装成功。
- `/mouse /indicator`：终端鼠标捕获/提示符设置。Flutter 已使用本机鼠标、触摸与运行指示，不仿造终端设置。
- `/wake`：接依赖状态；App PCM/麦克风采集未连接，不能用它声称真实语音唤醒通过。
- `/queue`：支持实际原生待处理项的查询/取消；App 入队、排序及对应消息展示尚未连接，不悄悄提交任务。
- `/rollback` 只提供 list/diff；`/snapshot` 只创建备份；`/worktree` 只 list/new；`/cron` 不提供删除。恢复、清理与文件删除需要单独授权，不自动执行。
- `/update` 只检查，安装仍走 Node 已有受管发布流程，不通过聊天替换正运行的服务。profile 切换由 Bot 选择承担。
- 宠物孵化、Nous 订阅、浏览器连接、语音与外部服务技能依赖真实配置。没有配置时显示原生结果，不用假回复、fixture 或其他服务替代。

真实验收、逐项矩阵与未验范围见 `side-phase5-command-acceptance.md`。没有修改 Hermes 核心或发布生产。
