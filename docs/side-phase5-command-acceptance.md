# Side Phase 5：命令接入与真实验收

日期：2026-11-02。基线是官方 Hermes v0.22.5（`bf0203a794`）。本次继续完成有实际 App 意义的命令适配，并逐项记录调用参数、真实旅程和环境限制。目录条数不是“全部参数和外部服务均验收通过”的数量。

## 阶段结项确认

**状态：已验证完成，已结项。** 2026-11-02，用户在知悉本文所列真实通过项、原生限制与待验边界后，明确确认 Side Phase 5 可以验证完成。

本次结项接受已交付的接入范围与核心真实旅程，不将原生 heartbeat / handoff 限制、未完成的语音闭环、Android 真机 / 推送 / 完整视觉矩阵及缺少配置的外部工作流改记为通过。这些记录保留为后续事项，不再阻塞本阶段结项。结项不包含生产部署、发布或 push。

## 接入方式

根因是 Hermes 的 `commands.catalog` 汇总 CLI、TUI、Desktop、Skill 和插件条目，不能直接等同于 `slash.exec` 支持列表。会话、工具、运行控制走各自 canonical RPC；配置、备份和扩展管理走固定官方管理接口；设备操作和页面导航在 Flutter 完成。没有任意 URL/shell 代理，也没有恢复旧 Runs API。

实现分为 `session-commands.ts`、`command-controls.ts`、`host-commands.ts`、`native-extras.ts`、`voice.ts` 和只读 `native-activity.ts`。Flutter 保持原生页面。一个 Bot 一个 Hermes profile，模型执行、工具、队列、压缩、自动化判断仍由 Hermes 完成。

当前目录 152 条：55 App 薄适配、94 原生/动态条目、2 纯终端设置、1 canonical 不支持。`/mouse /indicator` 对应终端 UI，App 使用本机鼠标/触摸和运行状态；`/handoff` 被当前原生接口明确拒绝。

## 实际通过的旅程

| 范围         | 实际结果                                                                                                                                                                                      |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 会话         | Windows、固定 Android 模拟器实际新建/恢复/分支/undo/retry，查看原生历史与会话列表；真实压缩减少原生历史条数，重连未重放任务。                                                                 |
| 运行控制     | 双端真实后台问答与旁路问答，主上下文不变；真实子 Agent list/tail/steer/interrupt、派生暂停/恢复、进程 kill、私聊 steer 与主 Stop。                                                            |
| 队列         | 双端真实 FIFO 入队、编辑、取消、steer；审批期间操作、重连保留 admission/消息标识，主回复和排队回复各一次。编辑按原生 FIFO 移到队尾。                                                          |
| 工具及主机   | 双端实际工具启停与新会话工具目录、隔离 Git worktree 创建/切换、官方日志/更新检查、ZIP 备份下载、profile 导出后由 App 导入新 Bot，记忆一致且真实欢迎回合完成。                                 |
| 本机         | 双端实际剪贴板文字/图片，模型识别测试图片；Windows 中文路径图片上传。显示密度、主题、时间戳、专注、电量、页面导航与偏好保存。                                                                 |
| 文件保存     | Windows 实际系统保存 JSON/Markdown/HTML，含中文文件名；读回文件并检查真实模型标记和格式。Android 系统保存未独立验收。                                                                         |
| 退出         | Windows 实际进程退出、Android 进入后台；独立读取服务器确认同一工具和真实模型回合完成，各执行一次。Windows 销毁 integration 进程的结果由外部检查记录，不伪造 Flutter driver 通过。             |
| 动态技能     | Windows 原生候选逐条加载当时目录的 54 个技能，均由真实模型确认加载；未据此宣称每个技能的外部账号、工具和完整工作流通过。                                                                      |
| 原生自动回合 | Windows、Android 实际完成 goal/subgoal、loop 模型回合；loop 原生历史与 App 的最终结果一致。后台结果观察只读取事件，不提交或调度任务。                                                         |
| 学习与整理   | 双端实际完成 `/init /learn /review /refine`：隔离 worktree 生成真实 AGENTS.md，实际 SKILL.md 读回且另一 profile 未安装，后台审查结论与原生整理完成结果回到 App。                              |
| MoA          | 双端真实单回合参考与汇总，原生 trace 有实际参考输出、token 用量和汇总输出；下一回合恢复普通模型。参考和汇总使用同一已配置模型，没有宣称不同供应商验收。Android 另验忙碌时拒绝且不变成 steer。 |
| 蓝图与 cron  | 双端实际 custom-reminder 蓝图创建任务，cron 创建、修改、暂停、恢复、立即执行；读取原生执行状态和对应执行会话中的真实模型结果。验收任务暂停并保留。其他蓝图及对话式补全未全验。                |
| 状态与设置   | 双端逐项执行状态/目录命令、`/debug local`、两次 `/yolo` 与四次 `/verbose`，显示非空原生响应；权限开关和输出级别恢复，原生对话历史不变。本地诊断没有走裸命令的外部上传。                       |
| 插件         | 双端实际调用无参数例行任务状态插件，返回原生结果，没有 JSONDecodeError 或新增模型回合。                                                                                                       |

另有 55 个参数调用场景已收到真实 Node/Hermes 响应。仅目录读取、usage、缺少配置、原生拒绝的结果分别记录，不能算作相应完整功能成功。

## 真实失败、修复及限制

- 已修：多客户端目录误标 slash 支持、工具写错 profile、wake.status 多传 session_id、后台完成帧错配当前 admission、子 Agent 列表缺控制 ID、队列 steer 被误判为独立回合、原生 loop 结果未进聊天、无参数插件解析错误、Android 电量轮询 Future/setState 异常、低对比度时间戳及长页面顶栏重叠。对应真实旅程重跑情况见逐项矩阵。
- 已修 MoA：原生 `slash.exec /moa` 返回看似正确的回复，却没有参考模型执行，trace 缺失且用量只有普通模型。改用官方 canonical `prompt.submit.model_override`，随本次 admission 传入和保存；双端修复后均核对实际 trace。没有增加 MoA 引擎、改 Hermes 核心或使用旧执行路径。群聊只影响所选成员本回合；忙碌时拒绝单回合命令，不当作 steer。
- heartbeat：Windows 创建/查询成功后等待 180 秒无输出，原生历史同样没有执行。源码确认 local adapter 分支提前返回；停止该隔离 heartbeat 后保留现场。App 只保留原生查询/暂停/停止，明确阻止创建/恢复，不另造调度器，不把“保存成功”报成“执行成功”。
- 麦克风：本机捕获、native wake feed 与转录入口已接；真实环境未配置 STT 且缺 numpy。双端只通过实际依赖提示页，唤醒检测、真实音频转录及 TTS 尚未通过。
- 学习旅程初次停在真实工具审批，补上 App 的 Allow once 操作后完整旅程双端通过；测试断言随后修正为读取本次命令结果，避免误读其他后台系统消息。保留真实文件、审批与失败现场。
- 历史上真实模型曾返回 `403: Insufficient account balance`。用户补充余额后，实际重新发起并完成双端学习、目标/循环、MoA、蓝图与 cron 旅程，当前已不再受此问题阻塞。历史失败证据作为历史记录保留，不覆盖成通过。
- 无 Nous 账号、图像服务、运行中的 MCP/browser 及其他外部配置的操作仍如实标为受限或待验；目录/缺配置提示不等于外部工作流通过。`/debug local` 已验，裸 `/debug` 的外部诊断上传未执行。
- 删除、清理、restore、prune 不开放、不执行。更新只检查，不替换运行服务。

## 环境、证据与工程检查

- 客户端：实际 Flutter Windows x64 候选；固定 `NekodotNativePhase3` Android API35 x64 模拟器。没有新建 AVD 或 wipe-data。
- 服务：持久隔离 Ubuntu 24.04 WSL 中的匹配 Node/Relay、官方 Hermes；真实 gpt-6.1-sol。没有改生产服务器或其他服务。
- 工程快照：`4e503403bf` 独立检出通过 frozen install、lint、typecheck、35 文件59项服务端测试、build、Flutter frozen pub、analyze、18项测试，以及 Windows/Android release 构建。后续仅补充真实旅程脚本和验收记录，不修改该快照的产品实现。
- 真实旅程按模块在持续迭代的候选上完成，并非所有场景都在最终 release 安装包重新跑过。最终普通构建使用产品 Relay 地址，本次新功能的真实旅程使用匹配隔离服务，不能把普通安装包当作已部署生产新功能的证明。
- 本地 release 产物为 Windows x64 EXE 与沿用既有签名的 Android arm64 APK；Windows 安装器没有 Authenticode 签名。私有手测候选另连隔离服务，不含入公开分发包；没有提交私有入口、配置或凭据。
- 逐项矩阵：`side-phase5-command-matrix.md`；脱敏证据：`evidence/side-phase5-command-adapters-real.json`。原始响应、密钥、私有账号配置与个人路径不纳入 Git。
- Android 真机、FCM、完整视觉矩阵、Android 系统保存/文件选择器、全部外部集成和成功语音旅程仍未通过；屏幕及授权流程本轮未重验。没有部署、发布或 push；本地提交保留模块记录。
