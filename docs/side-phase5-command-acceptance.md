# Side Phase 5：命令接入与真实验收

日期：2026-11-02。基线是官方 Hermes v0.22.5（`bf0203a794`）。本次继续完成有实际 App 意义的命令适配，并逐项记录调用参数、真实旅程和环境限制。目录条数不是“全部参数和外部服务均验收通过”的数量。

## 接入方式

根因是 Hermes 的 `commands.catalog` 汇总 CLI、TUI、Desktop、Skill 和插件条目，不能直接等同于 `slash.exec` 支持列表。会话、工具、运行控制走各自 canonical RPC；配置、备份和扩展管理走固定官方管理接口；设备操作和页面导航在 Flutter 完成。没有任意 URL/shell 代理，也没有恢复旧 Runs API。

实现分为 `session-commands.ts`、`command-controls.ts`、`host-commands.ts`、`native-extras.ts`、`voice.ts` 和只读 `native-activity.ts`。Flutter 保持原生页面。一个 Bot 一个 Hermes profile，模型执行、工具、队列、压缩、自动化判断仍由 Hermes 完成。

当前目录 152 条：54 App 薄适配、95 原生/动态条目、2 纯终端设置、1 canonical 不支持。`/mouse /indicator` 对应终端 UI，App 使用本机鼠标/触摸和运行状态；`/handoff` 被当前原生接口明确拒绝。

## 实际通过的旅程

| 范围         | 实际结果                                                                                                                                                                          |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 会话         | Windows、固定 Android 模拟器实际新建/恢复/分支/undo/retry，查看原生历史与会话列表；真实压缩减少原生历史条数，重连未重放任务。                                                     |
| 运行控制     | 双端真实后台问答与旁路问答，主上下文不变；真实子 Agent list/tail/steer/interrupt、派生暂停/恢复、进程 kill、私聊 steer 与主 Stop。                                                |
| 队列         | 双端真实 FIFO 入队、编辑、取消、steer；审批期间操作、重连保留 admission/消息标识，主回复和排队回复各一次。编辑按原生 FIFO 移到队尾。                                              |
| 工具及主机   | 双端实际工具启停与新会话工具目录、隔离 Git worktree 创建/切换、官方日志/更新检查、ZIP 备份下载、profile 导出后由 App 导入新 Bot，记忆一致且真实欢迎回合完成。                     |
| 本机         | 双端实际剪贴板文字/图片，模型识别测试图片；Windows 中文路径图片上传。显示密度、主题、时间戳、专注、电量、页面导航与偏好保存。                                                     |
| 文件保存     | Windows 实际系统保存 JSON/Markdown/HTML，含中文文件名；读回文件并检查真实模型标记和格式。Android 系统保存未独立验收。                                                             |
| 退出         | Windows 实际进程退出、Android 进入后台；独立读取服务器确认同一工具和真实模型回合完成，各执行一次。Windows 销毁 integration 进程的结果由外部检查记录，不伪造 Flutter driver 通过。 |
| 动态技能     | Windows 原生候选逐条加载当时目录的 54 个技能，均由真实模型确认加载；未据此宣称每个技能的外部账号、工具和完整工作流通过。                                                          |
| 原生自动回合 | Windows 实际完成 goal/subgoal、loop 模型回合；loop 原生历史与 App 的最终结果一致。后台结果观察只读取事件，不提交或调度任务。                                                      |
| 插件         | 双端实际调用无参数例行任务状态插件，返回原生结果，没有 JSONDecodeError 或新增模型回合。                                                                                           |

另有 55 个参数调用场景已收到真实 Node/Hermes 响应。仅目录读取、usage、缺少配置、原生拒绝的结果分别记录，不能算作相应完整功能成功。

## 真实失败、修复及限制

- 已修：多客户端目录误标 slash 支持、工具写错 profile、wake.status 多传 session_id、后台完成帧错配当前 admission、子 Agent 列表缺控制 ID、队列 steer 被误判为独立回合、原生 loop 结果未进聊天、无参数插件解析错误、Android 电量轮询 Future/setState 异常、低对比度时间戳及长页面顶栏重叠。对应真实旅程重跑情况见逐项矩阵。
- heartbeat：Windows 创建/查询成功后等待 180 秒无输出，原生历史同样没有执行。源码确认 local adapter 分支提前返回；停止该隔离 heartbeat 后保留现场。App 只保留原生查询/暂停/停止，明确阻止创建/恢复，不另造调度器，不把“保存成功”报成“执行成功”。
- 麦克风：本机捕获、native wake feed 与转录入口已接；真实环境未配置 STT 且缺 numpy。双端只通过实际依赖提示页，唤醒检测、真实音频转录及 TTS 尚未通过。
- 新增学习旅程：使用隔离 worktree 验 `/init /learn /review /refine`，保留真实文件、审批和失败现场。首次 `/init` 停在工具审批，验收脚本已补实际 App 的 Allow once 操作；此完整旅程尚未通过，不以脚本存在代替通过结果。
- 后续真实 Android goal/loop 旅程收到模型服务 `403: Insufficient account balance`，请求未被处理。已通知用户恢复服务；没有换成假模型、录制回复或自动重跑。余额恢复后的结果需另行记录。
- `/moa` 目前仅 usage；`/blueprint` 目录与配置，未执行新蓝图工作流。无 Nous 账号、图像服务、运行中的 MCP/browser 及其他外部配置的操作如实标为受限或待验。`/debug` 未触发可能上传私有诊断的动作。
- 删除、清理、restore、prune 不开放、不执行。更新只检查，不替换运行服务。

## 环境、证据与工程检查

- 客户端：实际 Flutter Windows x64 候选；固定 `NekodotNativePhase3` Android API35 x64 模拟器。没有新建 AVD 或 wipe-data。
- 服务：持久隔离 Ubuntu 24.04 WSL 中的匹配 Node/Relay、官方 Hermes；真实 gpt-6.1-sol。没有改生产服务器或其他服务。
- 辅助检查：当前 TypeScript typecheck、35 文件57项测试和 Flutter analyze 已通过；新增 heartbeat 限制测试、最终独立检出的 frozen install/lint/typecheck/test/build 与双端 release 构建在最终检查后更新。旧独立检出 `77ac30ea32` 的结果不代表当前代码。
- 逐项矩阵：`side-phase5-command-matrix.md`；脱敏证据：`evidence/side-phase5-command-adapters-real.json`。原始响应、密钥、私有账号配置与个人路径不纳入 Git。
- Android 真机、FCM、完整视觉矩阵、全部外部集成及当前新增学习完整旅程未通过。没有部署、发布或 push；本地提交保留模块记录。
