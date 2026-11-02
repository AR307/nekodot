# Side Phase 5：原生命令适配与真实验收

日期：2026-11-02。范围是修复手测 `/history → unsupported_command`，并校正命令目录；不是宣称 Hermes 全能力已经完成。

## 根因

Hermes v0.22.5 的 `commands.catalog` 汇总 CLI、TUI、Desktop、Skills 和插件命令。目录中的 `desktop: null` 不代表 canonical `slash.exec` 实现了该命令。原 Node 将没有特殊标签的条目全部直接发往 `slash.exec`，所以 `/history` 虽然可以选择，执行却被原生拒绝。

已核对官方 `gateway/session_commands.py`、`gateway/session_tui_ops.py`、`tui_gateway/command_discovery.py` 和 Desktop 的 slash 适配实现。`runtime.describe` 不提供逐条 slash 可执行清单，因此按已冻结版本的实际 handler 区分内置命令，Skills、Quick Commands 和插件仍由原生目录动态发现。

## 本次接入

| 命令                              | 适配方式                                                                     | 本次真实结果                                                                   |
| --------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `/history`                        | 当前 Bot canonical session 的 `session.history`，使用原生 display projection | Windows / Android 模拟器通过；包含刚完成的真实回复；没有新增模型回合或用户气泡 |
| `/agents`、`/tasks`               | `subagent.list` + `process.list`                                             | 双端通过空闲状态读取及别名；运行中子 Agent 的控制另待验收                      |
| `/tools`、`/tools list`           | `tools.show`，展示实际会话工具集                                             | 双端通过；启停工具仍在设置页，不伪装为已支持所有 slash 参数                    |
| `/reload-skills`                  | `skills.reload`                                                              | 双端读回 54 个实际可用技能，无新增技能                                         |
| `/config`                         | 打开所选 Bot 的 Hermes 原生设置页                                            | 双端通过，搜索并读取实际压缩设置                                               |
| `/v`                              | 官方别名解析后继续原生 `slash.exec`                                          | 双端返回实际 v0.22.5 版本信息                                                  |
| `/model`、`/plugins`              | 打开已有 Bot 编辑、插件页面                                                  | 已实现；本轮未实际点击这两个新入口                                             |
| `/prompt`、`/compose`、`/palette` | 填入当前 App composer，不调用服务器编辑器                                    | 辅助测试通过；本轮未做独立真实 UI 旅程                                         |
| `/reload`                         | `reload.env`，不重建现有 Agent                                               | 已实现；本轮未做真实凭据刷新验收                                               |

- 命令目录分为原生可执行、App 适配、服务器终端和待接入。后两类折叠在“其它指令”且不能从目录误选；不再把未接上的会话功能写成“需原生会话界面”来暗示已经支持。
- `/new`、`/resume`、`/branch`、`/undo`、`/retry` 等有实际用户价值，仍需要后续 canonical 会话切换/分支/回退适配。本次没有假装执行、清空历史或创建另一套会话引擎。压缩、导出、rollback 和 MCP 专用操作也不在本次通过范围。
- 原生控制是否允许在运行中调用由 Hermes 判断，移除 Node 对所有命令一律拒绝的 running gate。保留原有单 Bot 命令操作记录；未增加新的打断策略。
- Gateway 保留原生拒绝的 `data.detail`；未支持的参数给出可理解说明，不退回 Runs API、shell 或任意 HTTP 代理。
- 保留并纳入本模块已有的命令目录刷新按钮及相关草稿测试，没有覆盖其它界面工作。

## 实际环境与过程

- 客户端：当前源码 Flutter Windows Debug；固定复用 `NekodotNativePhase3`，Android API 35 x64 模拟器。没有新建或 wipe AVD。
- 服务：持久隔离的真实 Node/Relay、干净官方 Hermes v0.22.5（`bf0203a794`），真实 gpt-6.1-sol。没有使用 fake Hermes、旧 Runs 路径或录制回复代替模型。
- 两端均通过原生 UI 发送新的无害任务，观察真实流式回复，再从 `/` 目录选择历史、执行工具/子 Agent/版本/技能重载指令、打开设置、检查待接入提示，最后重连并比较消息标识，没有重放任务。
- 最终 Windows 旅程约 32 秒，Android 约 35 秒，不含构建。早期自动化的焦点/帧等待步骤不完整，出现未发送或后续文本没有进入 composer；修正为每次显式聚焦并确认输入后，完整复测通过。此前实际完成的无害回复全部保留。
- 实际目录包含 152 条（含 Skills）：原生可调用目录 100、App 适配 10、服务器终端 11、待接入 31。这个数字是目录分类，不是“152 条全部逐项实测通过”。

辅助检查：Node typecheck、ESLint/Prettier、32 个 Vitest 文件 / 48 项、Node bundle、Flutter analyze 和 17 项 Flutter tests 通过。自动化录制补齐官方当前目录的 alias/category 元数据，仅用于辅助协议测试。

## 证据与边界

- 脱敏结果：`docs/evidence/side-phase5-commands-real.json`。
- Android 实际历史画面：`docs/evidence/side-phase5-command-history-android.png`。
- 本轮候选使用预置已验证 QA 账号、隔离服务及私有手测入口；不是新的注册/SMTP 验收，也不是全新检出的 release 包。手测入口不替换产品安全存储中的登录，不作为公开构建包分发。
- Android 真机、生产 VPS 匹配版本、完整视觉矩阵、全部命令/参数、运行中子 Agent 控制及其余 Side Phase 5 能力仍待验收。
- 按已授权范围额外回收三个旧 Windows/Android 安装包，均移动保留，没有永久删除；当前候选、源码、profile、历史、凭据和证据未清除。
- 没有修改 Hermes 核心、部署生产、发布或 push。最新版私有手测候选另外启动供用户测试。
