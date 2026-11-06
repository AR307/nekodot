# Hermes 后端运行包验收

日期：2026-11-06。上游 v0.22.6，产品运行包 v0.22.6-r1，真实模型 gpt-6.1-sol。

## 结论与范围

后端运行包、Flutter 本机安装、VPS 安装脚本、Relay 下载及本地发布材料已接通。用户端不再 clone Hermes 或构建其前端；管理 HTTP、canonical WS、Python 后端及原生工具保留。

本轮在 Windows 原生候选与 Linux VPS 隔离环境完成下列真实旅程。**不是全平台验收完成**：macOS 无实机，低内存 VPS 屏幕被原生资源检查阻止，公网 HTTPS 完整安装及更新仍待验。不发布、不 push、不修改正式服务。

## 体积与安装测量

| 项目               |                   Windows x64 |                     Linux x64 |
| ------------------ | ----------------------------: | ----------------------------: |
| Hermes 压缩包      | 770,308,773 字节（734.6 MiB） | 642,321,596 字节（612.6 MiB） |
| 包内文件内容字节   |  2,097,369,468（约 1.95 GiB） |  1,895,229,717（约 1.77 GiB） |
| 构建用时，已有缓存 |                        502 秒 |                      102.6 秒 |

- 压缩包不包含 Nekodot 的 Node 24、后装插件、账号数据和 Linux 系统屏幕库。没有 Git、测试环境、官网、Electron/TUI/Web 前端；`hermes_cli/web_server.py`、`tui_gateway/ws.py` 仍在包内。
- Windows 两份主要下载材料为 Hermes + Node 24：808,056,837 字节；另有约 2 MB Node 产品 bundle。全新运行目录在安装插件前约 3,013,522,003 字节，包含保留的压缩下载包，不含账号数据。
- Windows 原生候选从安装到 online 71 秒；第二账号复用运行包为 9 秒。Hermes 下载来自 loopback Relay，Node 来自公网；不能作为一般用户 WAN 冷安装速度。
- Windows 取消/续传安装中，候选客户端、后代及运行环境进程的采样 RSS 合计峰值 1,113,296,896 字节。含共享页重复计数，采样间隔还包含进程扫描耗时；不是操作系统精确峰值或 Release 客户端基准。初次采样漏匹配客户端的旧记录不作完整峰值依据。
- Linux VPS 第二次独立目录解压 28.75 秒，`tar` 最大 RSS 2816 KiB，`du` 为 1,939,304 KiB；这些只反映解压，不冒充完整安装器的耗时和峰值内存。
- 当前旧 Windows 验收目录：runtime 文件内容 3,449,414,232 字节、data 775,878,630 字节；去重硬链接后分别为 3,156,459,555、482,917,988 字节。它包含旧缓存和历史环境，并非用户反馈的那台约 7 GB 安装。
- 新环境装过插件后，runtime 已增长至 3,479,691,871 字节，两账号 data 为 764,450,313 字节。缓存和账号可变环境会增长，不能把初始运行包大小等同于永久总占用。没有旧流程完整下载量/耗时/峰值记录，因此不报告未经测量的节省百分比。

结构化测量见 `evidence/hermes-runtime/metrics.json`；计数口径为普通文件长度，不跟随 junction，硬链接另作去重，不等于 Windows 磁盘簇占用。

## 真实旅程

验收链路为实际 Node/Relay/Hermes 和真实模型。Relay 仅绑定 loopback，VPS 通过本轮 SSH 反向转发访问；标为 **HTTP/WS**，不称为公网 HTTPS。

| 场景                | 结果与证据                                                                                                                                                                                                                                                |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Windows 新安装      | 原生 7 步进度、下载/解压、配对、真实读写文件、第二次对话、停止与重启通过。重启不新增消息；退出后本次进程为 0。完整旅程 5 分 17 秒，含模型等待。                                                                                                           |
| Windows 第二账号    | 共用运行包但不同 Node/profile，9 秒 online；真实读写、二次对话与重启通过。初始两个账号均未创建额外 PM generation。                                                                                                                                        |
| Windows 中断续传    | 第一次续传及后续聊天/重启通过，但取消状态被 `File closed` 覆盖；修复后复测得到 `cancelled`，续传安装 70 秒 online。该次后续模型目录因 Relay 暂断失败，不把第二条整旅程标绿。                                                                              |
| Windows 桌面        | 关闭工具时真实返回不可用；开启并授权后，模型通过 computer_use 在记事本输入标记、保存，实际文件已核对；停止另一电脑操作通过。中间一次启动记事本的 terminal 超时，随后模型完成操作，界面保留 1 个失败步骤。                                                 |
| Windows 插件与隔离  | 官方 PM 安装依赖 humanize 的测试插件；本账号产生 1 个 generation，另一账号环境未变，发行基线不含 humanize。                                                                                                                                               |
| Windows 运行包切换  | 同一个 r1 包更换目录，保留 72 条旧消息及 Node 身份；修复 PM 同步后真实插件输出 `1,234,567`，聊天、文件、重启均通过。4 分 08 秒，全旅程通过。第二账号另验证共享 ready 路径，保留 9 条旧消息、插件真实调用及重启通过，2 分 34 秒全绿；不是跨版本升级验收。  |
| Linux 常用工具      | 真实 skill_view、web_search 找到 Python pathlib 文档、Chromium browser_exec 读取标题、execute_code 计算均值 7、write_file/read_file；VPS 实际结果文件已核对。                                                                                             |
| Linux 插件/MCP      | 官方插件管理目录可读取；PM 安装 humanize 4.16.0 后，真实 runtime_probe 返回 `1,234,567`；独立 MCP 工具对 `[4,9,17]` 求和返回 30。切换运行包目录并同步 PM 后两项重新调用通过。                                                                             |
| Linux Cron          | Windows 原生候选连接 VPS：聊天设置时段规则、允许一次、拒绝、自动允许、普通及选定结果追问完成。3 次原生执行，实际文件仅 2 行；任务最终暂停。末尾测试脚本点击暂停时 finder 失效，RPC 收尾和独立读取确认暂停；不称整条脚本全绿。                             |
| Linux Webhook       | 原生候选完成创建、任务详情、复制和保密交付。App 测试按钮正确拒绝 HTTP QA URL，未放宽 HTTPS 要求。另通过隔离 HTTP 入口实际收到 202，真实模型结果为 `RUNTIME_WEBHOOK_NATIVE ROUTINE_NATIVE_UI_OK`，仅 1 条执行记录。公网 HTTPS/App 测试按钮完整闭环未通过。 |
| Linux 重启/目录切换 | 同 r1 包新目录恢复 50 条被追踪历史、3 个任务及 4 条原执行记录；任务均暂停。没有因恢复重跑。停止通知和主动发起的新会话/插件验证会新增消息，不以最近 50 条 ID 完全相等判断丢失。                                                                            |
| Linux 屏幕          | 实际启动被 Hermes 拒绝：1967 MB 总内存、305 MB 可用，原生要求 1536 MB；swap 后续约 1.8 GiB 已用。驱动/依赖已安装，但屏幕未运行。不改阈值、不杀其他进程、不降低屏幕能力。                                                                                  |

截图与脱敏记录：`evidence/hermes-runtime/`。原始日志留在忽略的 `.runtime/hermes-lean/qa/`；不提交账号、凭据、原生配置或完整模型响应。

## 本轮修复

1. **插件环境同步**：切换发行包安装身份后，旧插件配置仍在但 humanize 无法导入。账号准备调用官方 `hermes pm install --extra all`，新账号为 no-op，已有插件按原配置在账号内建立可变环境；Windows/Linux 真实复测通过。普通 start 也同步当前账号，避免第二账号因共享 ready 标记跳过插件环境准备；第二账号原生旅程通过。
2. **取消下载结果**：把用户主动取消的 HTTP/文件流异常统一显示为既有 cancelled 状态，仍保留分段文件供重试。
3. **验收脚本**：完整读取消息分页，远端文件不按 Windows 路径读取，Webhook 等待实际回执而不是已退出使用的进度控件。不改成功标准来掩盖 HTTP 拒绝或服务断流。

## 工程检查与本地产物

- Node 24：39 个文件 / 82 项辅助测试通过；typecheck、相关 ESLint/Prettier、Node/Relay bundle、安装脚本语法检查通过。
- 系统默认 Node 22 曾导致 SQLite 相关测试 worker 崩溃；按项目要求改用已安装 Node 24 后全量通过，没有修改全局 shell。
- Flutter analyze 无问题；36 项辅助测试通过。
- Windows Release 构建及安装器生成通过，未做 Authenticode 签名。
- Android arm64 Release 沿用原签名构建通过；本轮没有新增 Android 真机/模拟器验收结论。
- 全量 lint 的 ESLint 已通过；Prettier 的 6 份无关既有文档/证据格式问题未混入本轮处理，不能称全量 lint 全绿。
- 官方 Hermes 补丁测试本轮未完整重跑；当前发行快照上的实际 Cron、Webhook、Windows PM 行为已按上表验证。

本地文件：

- `dist/native/nekodot_0.3.1_x64-setup.exe`
- `dist/native/nekodot_0.3.1+7_android-arm64.apk`
- `dist/distribution/hermes/v0.22.6-r1/win32-x64.tar.gz`
- `dist/distribution/hermes/v0.22.6-r1/linux-x64.tar.gz`
- 对应平台 JSON、Node bundle、VPS 安装脚本已准备在本地分发目录。正式下载站尚无本轮运行包，不能把本地候选当作已上线版本。

## 未验及保留项

- macOS arm64 运行包、完整安装与所有真实能力：无实机，待验。
- Linux VPS 完整 `install.sh`/systemd 冷安装：未执行；同用户现有正式 service 名冲突，当前仅在独立目录运行候选，未覆盖该 service。完整 Linux 安装的下载量/耗时/峰值内存待单独测量。
- 充足内存 Linux 主机的真实屏幕；Windows 当前包的搜索、浏览器、MCP、Cron/Webhook 全矩阵；公网 HTTPS 的完整下载及 Webhook UI 闭环；真正跨版本运行包升级：仍待验。
- 旧安装没有自动清理。已只读列出 `.git`（288,895,674 字节）及前端局部依赖，root pnpm store 还存在共享关系，不能直接合并估计回收量。回收需另行授权并确认运行引用；profiles、浏览器资料、用户文件、历史、缓存和失败安装目录全部保留。
- Windows 原安装指针已恢复；Linux 本轮 QA Node 与隧道已停止，QA 目录内无残留运行进程；原服务 PID 和 active 状态未改变。本轮 loopback Relay 也已关闭，正式及其他验收服务不动。
