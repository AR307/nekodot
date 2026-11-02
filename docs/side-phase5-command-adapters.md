# Side Phase 5：Hermes 命令适配

基线：官方 Hermes v0.22.5。一个 Bot 一个 profile；聊天、派生、工具及压缩由 Hermes 执行。

## 模块与入口

| 模块        | 产品入口                                                                                  | 官方能力                                                                                   |
| ----------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| 会话        | `/new /clear /resume /sessions /branch /undo /retry /compress /save`                      | canonical session create/list/history/resume/mutate/export                                 |
| 运行控制    | `/agents /steer /stop /bg /btw /queue`                                                    | subagent、process、session.steer、原生 detached prompt/FIFO；主回合 Stop 与 `/stop` 不混用 |
| 工具/环境   | `/tools /reload-mcp /reload-skills /reload /browser /wake`                                | profile 工具配置、原生 reload/browser/wake 状态                                            |
| 主机与资料  | `/logs /snapshot /export /import /worktree /update`                                       | 官方日志、备份、profile archive、Git worktree、更新检查                                    |
| 原生资料    | `/journey /pet /hatch /subscription`                                                      | 实际学习条目、宠物目录/生成状态、Nous 订阅状态                                             |
| 本机        | `/copy /image /paste /focus /density /timestamps /statusbar /battery /skin /redraw /quit` | 当前客户端的剪贴板、附件、外观、实际电量、重同步及退出/后台入口                            |
| 页面/编辑器 | `/help /config /model /plugins /login /prompt /palette`                                   | 实际 App 参数说明、已有 Flutter 页面、当前输入框或指令栏                                   |

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
6. Android 长时间使用时电量轮询的 `setState` 返回 Future，真实旅程在一分钟后抛错；改为同步更新 Future 字段，并复测完整双端旅程。实拍发现用户气泡中的时间戳黑底黑字，改用对应气泡的反色文字。
7. 原生目录中的 CLI 参数不一定适用于 App（例如 `/quit --delete`、服务器端导入路径）。指令栏和 `/help` 现在显示实际 App 参数，不再提示不能执行的用法。

8. 真实队列 steer 的 receipt 为 started，但 snapshot.pending.steering 表示输入正在交给原回合，不能当成独立运行回合。按原生实际 pending 标记处理，双端复测不再重复审批或空回复。
9. 原生 loop 已执行但聊天没有结果：原先只跟随 App 提交的 admission。补只读原生事件观察，复用同一消费与恢复通路。真实 Windows loop 结果现已到达 App。
10. 插件命令无参数时不能对空字符串 JSON.parse；例行任务状态插件改为使用空对象，双端真实调用通过。

## 明确边界

- 目录实际 152 条：54 App 适配、95 原生/动态条目、2 纯终端设置、1 canonical 不支持。数字表示接入分类，不表示 149 条的全部参数均已执行。
- `/handoff`：此版本 canonical 明确不支持；不走 legacy 会话路径伪装成功。
- `/mouse /indicator`：终端鼠标捕获/提示符设置。Flutter 已使用本机鼠标、触摸与运行指示，不仿造终端设置。
- `/wake`：设备端 PCM16/16kHz/mono 麦克风、原生 wake feed、WAV 转录与发送前编辑已接入。页面离开或后台停止采音，不自动发送。当前真实 Hermes 环境未配置 STT，并缺 numpy；双端仅通过依赖状态页面，不能宣称语音识别或唤醒成功。
- `/queue`：原生 FIFO 入队、list、rm、edit 和 steer 已接，双端真实模型/审批/重连旅程通过。编辑替换项按原生规则移到队尾；原生没有 reorder API，产品不另造队列引擎。取消、替换和 steer 的输入卡保留实际状态，不生成虚假 Bot 回复。
- `/heartbeat`：实际复现 v0.22.5 保存成功却未触发 local canonical session。官方 `gateway/run_goals.py::_heartbeat_poll_watch` 在 local adapter 没有 `_message_handler` 时提前返回。App 保留 status/pause/stop，阻止新建/恢复并给出原因；没有改核心或另写调度器。
- 原生 loop/goal/后台 review 的 admission 和 `review.summary` 通过只读事件观察进入已有消息消费通路；不制造用户输入、不自动重跑。`/refine` 与详情按钮共用原生整理操作及完成信息，不再仅返回“已启动”。
- `/rollback` 只提供 list/diff；`/snapshot` 只创建备份；`/worktree` 只 list/new；`/cron` 不提供删除。恢复、清理与文件删除需要单独授权，不自动执行。
- `/update` 只检查，安装仍走 Node 已有受管发布流程，不通过聊天替换正运行的服务。profile 切换由 Bot 选择承担。
- 宠物孵化、Nous 订阅、浏览器连接、语音与外部服务技能依赖真实配置。没有配置时显示原生结果，不用假回复、fixture 或其他服务替代。

真实验收、逐项矩阵与未验范围见 `side-phase5-command-acceptance.md`。没有修改 Hermes 核心或发布生产。
