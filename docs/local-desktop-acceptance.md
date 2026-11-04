# 本地电脑运行：真实验收记录

日期：2026-11-04。实施计划见 [local-desktop-plan.md](local-desktop-plan.md)。

## 环境

- Windows 11 Home 10.0.26200 x64，Windows PowerShell 5.1；本次候选客户端 debug 构建，由 `integration_test/local_desktop_journey_test.dart` 驱动真实界面。
- 官方 Hermes **v0.22.6**（提交 `f0d94882e8`），私有 Node 24.22.1，已配置的真实模型。
- 隔离 loopback Relay（`.runtime/local-desktop/qa-relay.ts`，带 loopback SMTP 收件箱与私有 QA 路由），分发本次源码构建的 Node bundle。不是生产服务，未部署、未发布。
- 运行环境与数据目录位于 `D:\nekodot 本地验收\运行环境` 与 `D:\nekodot 本地验收\数据`（中文与空格路径）。测试只在内存中保存登录，不改动已安装客户端的登录与偏好。
- 这台电脑已有用户自装的 Python、uv、Node 与开发工具，**不是干净用户环境**；安装进程隔离了 `HERMES_*`、`UV_*`、`NEKODOT_*` 变量并核对了外部副作用（见下），但未在全新 Windows 账户上验收。

## Windows 结果

| 项目                   | 实际结果                                                                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 官方阶段（命令行复放） | `prerequisites`→`complete` 全部成功，约 7 分钟；`hermes.exe --version` 报告 v0.22.6 · f0d94882e89a，安装目录为中文路径                                                    |
| 外部副作用             | 用户 PATH 无 Hermes 项；未创建 `%LOCALAPPDATA%\hermes`、开始菜单或桌面快捷方式；用户自己的 `%APPDATA%\uv\python` 未改动（最后修改 10-28）；uv 的 Python 落在运行环境目录  |
| 目录权限               | 两个新建目录关闭继承，仅 SYSTEM、Administrators 与当前用户可访问                                                                                                          |
| GUI 首次使用           | 注册（loopback 收件箱验证码）→ 添加电脑 → 在这台电脑运行 → 显示所选目录与可用空间 → 安装并启动；13 步依次完成，**6.3 分钟**上线并自动选中这台电脑，Relay 记录平台 `win32` |
| 创建 Bot               | 通过 GUI Bot 编辑器创建，真实模型欢迎回复 9.4 秒                                                                                                                          |
| 真实工具与本地文件     | 真实模型调用原生 `read_file` 读取 `D:\nekodot 本地验收\工作区\来源-*.txt`，再以 `write_file` 写出新文件；磁盘内容与源文件第一行逐字一致；两轮独立运行均通过               |
| 重新打开               | 再次登录后自动启动已配对节点，不重新配对；同一 nodeId，历史完整                                                                                                           |
| 停止与启动             | 停止后所属进程 0 个；再启动恢复在线，历史不变，无重复执行                                                                                                                 |
| 退出                   | 退出前停止本机节点，所属进程 0 个                                                                                                                                         |
| 异常结束               | 强制结束客户端进程后 0.9 秒内所属 6 个进程（node、2 个 hermes.exe、3 个 python）全部结束；Relay 立即显示该节点离线                                                        |

| Relay 中断 | 隔离 Relay 实际停止并重启后，本机节点自动重连上线，客户端无需操作 |
| Android 访问 | 固定 `NekodotNativePhase3` 模拟器（emulator-5554，经 `adb reverse`）用同一账号登录，选中这台电脑上的节点，打开桌面端创建的会话，真实模型流式回复由本机 Hermes 完成；桌面客户端随后退出，Relay 立即显示该节点离线。不是 Android 真机结果 |
| 保持在线 | 桌面客户端持续运行 7.7 分钟（Android 访问、Relay 重启期间）始终在线；退出后所属进程 0 个 |

| 取消与重试 | 第二套全新目录（`运行环境2`/`数据2`）中，于依赖安装阶段取消：页面显示已取消，保留已完成的 5 个阶段；点重试后跳过这 5 个阶段继续，4.4 分钟上线。UTF-8 修正后 GUI 写出的阶段日志中文路径正确 |

截图：[目录选择](evidence/local-desktop-windows-folders.png)、[安装进度](evidence/local-desktop-windows-installing.png)、[取消后](evidence/local-desktop-windows-cancelled.png)、[真实工具聊天](evidence/local-desktop-windows-chat.png)；机器结果：[local-desktop-windows.json](evidence/local-desktop-windows.json)。

## 模块五：本机桌面操作能力（真实节点）

- `desktop.status` 在真实 Windows 节点返回 `host: desktop`、`computerUse: false`（无 Bot 独立屏幕），`desktopControl` 为已安装且 `ready: true`（cua-driver 健康检查）。
- Hermes 默认为新 profile 开启 `computer_use`。nekodot 在这台电脑上新建 Bot 时改为默认关闭，由 Bot 详情“操作这台电脑”开关显式开启；经官方 `/api/tools/toolsets/computer_use` 写入，Hermes CLI 读回新 Bot 与关闭后的旧 Bot 均为 disabled。
- Windows真实模型记事本输入、保存及停止已通过；macOS授权仍待验。

## 观察到的边界

- 本机 Hermes 与用户是同一系统账户：模型来源列表中出现 Hermes 自己检测到的 Claude Code 登录。nekodot 不会自动使用，用户选择后才会作为来源。
- 驱动状态检查提示 cua-driver 首次实际操作时会在用户目录创建 `.cua-driver`（驱动自己的目录，Hermes 未提供迁移设置）；早期未创建；后续真实桌面验收已运行驱动。用户已有的 `.hermes` 与 `.local/state/hermes` 在验收期间没有改动，gateway 锁目录位于账号数据目录内。

## 真实验收中发现并修正

- **Windows 控制台编码**：PowerShell 5.1 以 GBK 输出，中文路径在阶段详情和错误里乱码。阶段改经 `run-stage.ps1` 以 UTF-8 输出，命令行复验中文路径与结果帧正常；首次 GUI 安装使用修正前版本，修正后的 GUI 路径待下一次全新安装复验。
- **孙进程持有输出管道**：进程结束后先回收整棵进程树再读取剩余输出，避免遗留进程让读取永远不结束。
- **空白 commentary 气泡**：工具开始时空的文本段被保存为 commentary，聊天显示空气泡（截图可见，为修正前）；聊天列表不再显示空白 commentary，存储不变。
- 旅程脚本本身的问题（Windows 无驱动截图通道、过渡动画中点击、账号文件解析）已在测试中修正，不计为产品问题。
- **欢迎回复进行中发送的消息未送达**：新 Bot 的 gateway 冷启动期间欢迎回合还没有 Hermes 受理号，Node 以英文“The current run is starting”拒绝，消息未保存（草稿保留）。仅等待受理后 steer 也不对：Hermes 受理后异步认领，立即 steer 得到 `stale_generation`（真实复现一次）。现在欢迎回合期间的发送先等欢迎被受理，再作为原生排队输入跟在欢迎之后执行，显示“已排队”→“队列任务”；同一草稿重发共享等待、不重复送达（仅辅助测试覆盖）；普通运行中的发送仍为 steer。全新目录（`运行环境4`/`数据4`）真实旅程：欢迎尚未开始流式输出时发送，Hermes 依次记录两个入站回合，真实模型 `read_file`→`write_file`，文件逐字一致，节点库中欢迎、用户消息与回复各自归属正确，停止/启动/退出均通过。截图：[发送时](evidence/local-desktop-welcome-send-composer.png)、[结果](evidence/local-desktop-welcome-send-chat.png)；机器结果：[local-desktop-welcome-send.json](evidence/local-desktop-welcome-send.json)。

## 待处理的发现

- 取消原因原先直接显示内部代码 `cancelled`，已改为本地化文字（截图为修正前）。

## 未验或仍待验

- 全新 Windows 用户账户；下载过程中真实断网后的重试。
- macOS、Ubuntu 桌面：无验收环境，未运行。
- macOS/Linux桌面操作、系统权限拒绝与恢复待验；Windows记事本输入保存与任务停止已通过。
- 本地 Node 自动更新：本次 bundle 为开发构建，不触发更新。

## 本机桌面操作：真实运行（2026-11-04 12:2x）

- 用户同意后运行 `integration_test/local_desktop_control_test.dart`（运行环境2/数据2，真实模型、官方 Hermes）。
- **关闭时**：Bot 被要求只用 computer_use 操作屏幕，实际没有任何工具调用，回复 `NO_DESKTOP_TOOL`。三次运行一致。
- **开启后**：同一次客户端运行中的第二条消息没有保存、也未到达 Hermes（三次复现：等待 15 秒、切换工具集后重启本机节点均如此，节点无错误日志），因此尚未让真实模型实际操作记事本；目标文件保持为空，无记事本进程残留。
- 上述当时推测已被下述复验推翻：这是测试输入焦点问题，不是消息丢失，也不是欢迎回合问题。
- 快照中的 `desktopControl` 在首次后台检查完成前显示“not checked”；Bot 详情会实时查询，不受影响。

## 接手复验：第二条消息与真实桌面（2026-11-04）

- 环境：Windows 11 本次源码候选、隔离 Relay 4459、既有本机 Node 24.22.1、官方 Hermes v0.22.6，真实模型 **gpt-6.1-sol**。
- 根因：桌面按钮夺走焦点后，integration_test 再次 enterText 没有恢复原生编辑器连接；实际 draftLength=0，发送按钮禁用。改为像用户一样点击输入框再输入，并校验文字；不改聊天产品逻辑，不使用等待15秒或重启节点的绕行。
- 同一会话连续三轮通过：关闭时 NO_DESKTOP_TOOL；开启后真实 terminal 启动记事本，computer_use 定位、输入唯一测试标记、保存；磁盘内容确实包含标记；第三轮停止后 computer_use:cancelled，活动回到 idle。03:05 完成。
- 独立文件旅程也通过（01:35）：真实 read_file/write_file/patch、第二条消息获真实回答，停止后进程0，重启历史不变且没有重复消息，退出后进程0。
- 修正旅程的目录指针，每次明确选择对应隔离目录，避免其他旅程改变指针后误用别的账号运行环境。
- 先前“欢迎期间发送”产品修复仍成立；此次连续消息问题与其不同。
- 日志仅留在 .runtime/local-desktop/handoff-control-focus.log 和 handoff-journey.log，公开证据只保留脱敏结果。

## 2026-11-04 接手修复：安装取消、账号冷启动与双端真实回归

- 修复下载取消需等下一块数据的问题：使用现有 http AbortableRequest，取消立即中断等待并关闭文件流。全新运行环境6在 Node 下载中点击取消，显示取消；点击重试重新下载成功，官方安装阶段全部完成。
- 真实复现 PowerShell 5.1 继承其他 PowerShell 运行时 PSModulePath 后找不到 Get-FileHash。仅安装子进程使用系统5.1模块目录，不改全局 shell，不改 Hermes 脚本；同一主机新目录复验 prerequisites 通过。
- 真实复现新账号的 Hermes PM 环境首次准备超过 gateway 健康检查窗口。源码确认每个账号数据根拥有各自 PM 状态；安装的 account 阶段先运行官方 hermes pm install --extra all 并展示输出/允许取消，不再把依赖下载藏在 gateway 启动里；不增加超时重试引擎。
- runtime6完成共享安装、首次账号启动失败现场保留；修正后以同一共享运行环境和全新数据7/账号重跑，account准备19.5秒，gateway上线11.6秒。GUI建Bot、欢迎期间排队、真实 read_file/write_file、第二条消息、停止/重启不重跑均通过。
- Windows 候选保持节点在线，固定 Android NekodotNativePhase3/emulator-5554 同账号真实登录，读取电脑上的中文文件并收到原生工具记录和流式模型回复，返回会话列表通过。隔离 Relay 4459 + 官方 Hermes v0.22.6 + gpt-6.1-sol，不是生产/公网或 Android 真机验收。
- Android首次尝试发生连接中断，下一次脚本抢在列表渲染前滚动失败；保持失败日志，等待实际列表后重跑通过，不修改消息执行逻辑、不自动重发任务。旅程改用内存测试凭据存储，不清除已安装客户端登录。
- Windows 最后退出后所属进程0；原生桌面操作的两次成功结果见前节及 local-desktop-handoff.json。启动失败现在立即反馈，不额外等待客户端6分钟。
- Flutter analyze 无问题，24项 Flutter 辅助测试；Node24全量38文件69项辅助测试、TypeScript与触及文件ESLint通过。不部署、不push；测试值和凭据留在忽略目录。

## 2026-11-04 接手补齐：跨平台宿主与候选包

- 增加Flutter macOS/Linux宿主，复用业务界面和Rust桥接；修正Linux实际构建发现的缺少Rust目标，增加Apple Silicon/Linux x64。
- 本机入口、窗口/托盘、目录导入、系统通知和退出扩展到三个桌面系统；Mac系统退出先停止所属节点，Linux使用GTK单实例；Mac使用原生Keychain，不开启App Store沙箱，不绕过系统权限。
- 更新按实际OS选择EXE/APK/DMG/DEB，无该平台包时明确提示；仅在用户同意停止本机任务后打开安装器，取消退出不会抢先安装。
- 构建脚本支持本机Mac/Linux，POSIX不注入Windows SDK路径；增加DMG/DEB打包与Relay可选平台下载。Mac可接现有签名/公证凭据，但未签名不宣称正式发布。
- 已构建Windows release+未签名NSIS EXE、沿用项目签名的Android arm64 APK，以及WSL Ubuntu24.04的Linux release/DEB。Linux动态库无缺失，包依赖包含GTK和Secret Service；WSLg仅启动冒烟，缺托盘watcher/Secret Service，不能代替Ubuntu桌面验收。
- 产物位于D:/nekodot-app/dist/native：nekodot_0.3.0_x64-setup.exe、nekodot_0.3.0+6_android-arm64.apk、nekodot_0.3.0+6_linux-x64.deb。版本仍为候选0.3.0+6，未发布或更新正式服。
- Mac没有设备，未构建DMG、未验系统授权；Ubuntu桌面安装和真实工具待设备。不能宣称三平台验收完成。
- 构建入口：node scripts/build-native.mjs windows|android|macos|linux；在目标桌面系统构建，Android传既有私有signing/Firebase配置。未删除任何用户文件。
