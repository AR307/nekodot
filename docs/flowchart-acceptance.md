# Flow 原生执行图验收

日期：2026-11-06。仅本地候选，不发布、不 push，不修改正式服务。

## 本轮交付

- 采用已审核的 Flow 文案；完成绿、运行/等待蓝、失败红、未执行灰。
- 节点外框由 40px 缩至 32px，行高由 72px 缩至 56px，保留 44px 点击区域。
- 原生 `todo.updated` 计划作为父节点，动作归属执行时的计划项。完成自动折叠，可展开、回到当前步骤。
- 只保留每个会话当前或最近一次聊天任务；不包含 cron/webhook，不补造历史执行图。
- Windows 两种主题使用右侧面板/窄窗覆盖，Android 竖横屏均为全屏页。查看、关闭、重连不提交任务。

## 环境与证据

- Windows 原生 Flutter 候选；Android 固定 `NekodotNativePhase3` / `emulator-5554`，未创建新 AVD、未清空数据。
- 隔离真实 Relay、Node、Hermes 与 `gpt-6.1-sol`。Windows 使用 `127.0.0.1:4459`，模拟器使用 `10.0.2.2:4459`；HTTP 仅用于本机 debug 验收，不是公网发布配置。
- Hermes 实际版本：`v0.22.5+canary.20261026T071310Z-241-g8ac43a3e2a`。包含此前授权的安装/cron 补丁，本轮未改 Hermes；不称为未经修改的官方稳定版。
- 原生旅程：`apps/native/integration_test/flowchart_journey_test.dart`；无 fake Hermes、录制回放或模拟工具响应。
- 脱敏结构化记录：`docs/evidence/flow/journeys.json`。截图来自实际候选渲染；Windows 只裁出右侧面板，原图留在私有 QA 目录。

## 已实际执行

| 场景              | 结果                                                                                                                             |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| 私聊工具链        | 双端真实 read_file → execute_code → write_file → read_file，均值 20；图与实际调用一致，可打开工具详情。                          |
| 三 Dot 接力       | 真实 web_search 找论文、browser_exec 浏览 arXiv、读取/计算、写报告。三个头像回合与实际成员顺序一致，双端显示同一群聊图。         |
| 原生计划          | 双端实际建立 read/analyse/write 三个计划，观察已完成/执行中/未执行；读写和计算归到对应父节点，完成自动折叠，手动展开后可见工具。 |
| 文件核对          | `flow-plan-windows-1793939533219.md`、`flow-plan-android-1793939868244.md` 均写入并由真实 read_file 复核均值 20。                |
| 审批、提问        | 双端真实 clarify；terminal 等待授权，点击图回到原卡片，允许一次后返回 63。等待节点为蓝色。                                       |
| 失败              | 双端执行专门的不存在命令，原生返回 exit 127，工具节点显示红色，不伪装成功。                                                      |
| steer、排队、停止 | 真实长工具运行中补充指令、加入再取消排队消息，图不被替换；停止后显示实际停止。Windows 控制续程完整通过，Android 分段确认。       |
| 重连、重新查看    | 重建真实业务 socket 后读取同一 execution；关闭重开、只读查看保持 flow seq，不产生额外运行。                                      |
| 新会话            | Windows `/new` 后空图；Android 重新登录同一新会话后空图确认通过。                                                                |
| 视觉与导航        | 紧凑节点、Plan 展开/折叠、浅深色、中英文、reduced-motion；Windows 宽窗/窄窗，Android 横竖屏与系统返回，关闭图保留聊天及草稿。    |

## 发现与复测

1. Windows Plan 真实执行已完成，但最初的整条测试在 reduced-motion 布局阶段因 `AnimatedSize(Duration.zero)` 断言失败。禁用动画时改为静态 child；随后双端只读视觉旅程复测通过，不重跑已完成工具。初始 `flow-plan-windows` 记录不代表最初整条测试通过。
2. Windows 玻璃主题 Flow 按钮被窗口控件遮挡，标题栏增加既有窗口控件预留宽度，候选复测通过。
3. 测试使用 `/new 固定名称` 时，Hermes 原生会复用同名会话，不能断言为空。旅程改为无名 `/new`；Windows 创建与 Android 只读空图分别验证，不把 Android 首次整条控制测试写成全绿。
4. 重复写旧报告曾触发 Hermes 原生整文件覆盖保护，图正确显示失败。之后每次验收使用新文件名；未绕过保护，也未删除旧文件。
5. `flow-controls-windows` 中 question/approval/toolFailure 为 false，表示该次 `QA_STOP_ONLY` 续程未执行这些步骤，非产品失败；它们由此前双端真实控制旅程与截图确认。`flow-view-windows` 的横屏/系统返回 false 表示 Android 专项不适用于 Windows。
6. Android release 曾因与 Flutter 测试并行而污染生成插件注册器。改为串行运行 Flutter 命令后构建成功，没有修改产品逻辑或删除缓存绕过。

## 工程与候选包

- TypeScript typecheck、相关 ESLint/Prettier、39 文件/81 项服务端辅助测试、Node/Relay bundle 通过。
- 最终 Flutter analyze、36 项辅助测试通过；Windows release 与 Android arm64 签名 release 构建通过。自动化不替代上述真实工具旅程。
- Windows：`dist/native/nekodot_0.3.1_x64-setup.exe`，未做 Authenticode 签名。
- Android：`dist/native/nekodot_0.3.1+7_android-arm64.apk`，沿用本地私有签名配置。
- 本轮未提升版本、未发布，也未重新验收完整安装/覆盖升级流程。

## 未验范围

Android 真机、物理网络切换/长时间离线、生产公网链路、真实模型并行工具及 A→B→A 回转、审批拒绝/超时与提供方模型故障，未在本轮逐项实测。对应部分有辅助行为测试，不据此宣称真实通过。最新快照持久恢复有行为覆盖，本轮未额外重启 QA Node/Relay 验收。Mac/Linux 不在本轮双端验收内。

## 截图索引

- `docs/evidence/flow/windows-compact-plan-final.png`
- `docs/evidence/flow/windows-plan-running.png`
- `docs/evidence/flow/android-compact-plan-expanded.png`
- `docs/evidence/flow/android-waiting-approval.png`
- `docs/evidence/flow/android-tool-failed.png`
- `docs/evidence/flow/android-compact-dark-en-reduced.png`
- `docs/evidence/flow/android-compact-landscape.png`
- `docs/evidence/flow/android-new-session-empty.png`
