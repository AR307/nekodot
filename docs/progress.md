# Phase 0 进度

| 模块                  | 状态                         | 证据                                                       |
| --------------------- | ---------------------------- | ---------------------------------------------------------- |
| 0.0 参考归档          | 已完成；原 HTML 视觉核对受限 | 两份原件、参考索引；私有 GitHub AR307/nekodot-app 初始归档 |
| 0.1 工程骨架          | 已完成                       | Node 24 workspace；基础页桌面/手机实际浏览器截图           |
| 0.2 协议              | 已完成；按实测定稿           | Zod、导出类型、业务输入样例；裁切依据见 hermes-notes       |
| 0.3 真实 Hermes spike | 已完成                       | 五项真实场景通过；持久现场确认；七项调查与 CDP 连接证据    |
| 0.4 测试回放服务      | 已完成                       | 六类真实 HTTP 接口、13 项场景检查与真实 fixture            |
| 0.5 整体验收          | 工程与真实接入验收完成       | 全新检出安装、lint、类型、13 项测试、构建和浏览器复验通过  |

## 最终验收 / 2026-10-27

- 全新本地检出基于提交 `5e98c3006c56c0abdb5e9b4a0435a3ecae18a985`，目录为
  `D:/nekodot-app/.runtime/acceptance-20261027-175647`。没有复制 `.env` 或既有 node_modules。
- 使用 Node 24.22.1、pnpm 10.34.5，依次执行 `pnpm install --frozen-lockfile`、
  `pnpm lint`、`pnpm typecheck`、`pnpm test`、`pnpm build`，各命令独立退出码均为 0。
- 3 个测试文件、13 项场景通过：协议业务输入、真实 SSE 分块读取、HTTP 文本/工具/
  审批允许与拒绝/执行中停止/等待审批时取消/profile 隔离。HTTP 回放使用真实录制资料。
- `pnpm test:e2e` 在实际 Microsoft Edge 中通过 1 个完整旅程：桌面基础页、3 个模块、
  中英切换、390×844 手机布局与无横向溢出。重新查看两张截图，内容完整、布局正常。
  截图为 `docs/evidence/foundation-desktop.png`、`docs/evidence/foundation-mobile.png`。
- 全新检出构建的 Node 入口实际启动并正常退出；Relay 实际启动后 GET `/health` 返回
  `{service:"nekodot-relay",phase:0,status:"ok"}`，随后结束本次验收进程。
- 真实模型五项结果见下文及 `docs/fixtures/spike-report.json`；它们独立于回放验收。
  最终 spike 于 2026-10-27 09:49:59 UTC 完成，再次进入 WSL 后现场及审批文件仍保留。
- 产品运行入口不导入 fake-hermes；`.env`、临时现场、失败尝试和全新检出均保持忽略。
  Git 跟踪文件未发现本地三项 provider 配置的实际值。初始私有归档之后的模块只做本地提交。
- 剩余限制只有原 HTML 的视觉核对，详见末节；未将其写为通过。

## 真实结果

- 自定义 API 精确回复 NEKODOT_PHASE0_OK。
- terminal printf 返回 NEKODOT_TOOL_OK，工具 start/completed 带相同 tool_call_id。
- once 后真实 AGENTS.md 增加标记；deny 后保持原内容，没有重试或换路径写入。
- sleep 工具执行中停止，最终 run 为 cancelled；真实 stop 响应为 stopping。
- gateway 启动后新增 profile 无重启可访问。
- 自有 Chromium CDP 实际 Browser.getVersion、Target.getTargets 成功。
- 0.3 最终持久现场在 WSL 重新进入后确认存在，两份文件内容与报告相符。

## 原参考的视觉核对

HTML 九块已静态解析，完整原件保留。查看通道拒绝原稿执行后，未改用别的通道执行该文件。
原稿视觉核对仍待获准查看方式；独立基础页已用实际 Edge 浏览器验证桌面、语言和手机尺寸并留图。
完整参考界面还原属于 Phase 1，不把基础页截图当成原参考视觉核对。

# Phase 1 进度

| 模块             | 状态   | 验证                                                                                    |
| ---------------- | ------ | --------------------------------------------------------------------------------------- |
| 1.1 Relay        | 已完成 | 实际 HTTP/WS 注册、登录、配对、路由、归属隔离、解绑通过                                 |
| 1.2 Node 基础    | 已完成 | 真实 CLI 配对、凭证与 SQLite 持久化、WS 重连和节点重启恢复通过                          |
| 1.3 提供方与 bot | 已完成 | 真实网页配置自定义 API、hub 模型目录、热建 bot、唯一私聊；OpenRouter 托管文件配置通过   |
| 1.4 私聊运行     | 已完成 | 真实网页文本、允许/拒绝、同 run steer、取消、节点重启通过；详见 phase1-live-report.json |
| 1.5 Web 与同步   | 已完成 | Edge 完整私聊、刷新恢复、断线重发、snapshot 回退、双节点隔离与响应式截图                |
| 1.6 整体验收     | 已完成 | 全新检出安装及六项命令通过；17 项场景、2 个 Edge 旅程和真实 API 验收分别记录            |

## Phase 1 当前验收结果 / 2026-10-27

### 真实模型与文件结果

`docs/evidence/phase1-live-report.json` 记录真实整栈验收；2026-10-27 14:44:15–14:48:08 UTC，passed=true，无浏览器 pageerror。

| 场景       | 实际观察                                                                           | 证据                                                |
| ---------- | ---------------------------------------------------------------------------------- | --------------------------------------------------- |
| 首次使用   | Edge 注册 → CLI 配对 → 网页配置 API → 热建 bot → 真实流式文本                      | live-report 的 registration-pair-provider-bot、text |
| 允许与刷新 | 等待审批时刷新，恢复待办；允许后 AGENTS.md 增加指定一行                            | phase1-live-allow.sse / state                       |
| 拒绝       | 文件未变化，read_file 后只有一次被拒绝 patch，没有其他写入                         | phase1-live-deny.sse / state                        |
| 原生 steer | run_4744af9c8cbc4e19a8c17b8166a49941 不变，terminal 与文件效果各一次，最终指定回复 | phase1-live-steer.sse / state                       |
| 停止       | 网页 stop 后真实 run 为 cancelled                                                  | phase1-live-stop.sse / state                        |
| 节点重启   | 停止并重启真实 Node，原 bot、会话和历史可见                                        | live-report 的 node-restart-history                 |

真实执行与 fixture 回放是两组独立验收。OpenRouter 仅验配置及文件切换，未声称其真实模型调用通过。

### 自动化与视觉

- Node 24.22.1：lint、typecheck、7 文件共 17 项测试、所有 workspace 构建通过。
- 实际 Microsoft Edge：2 个完整旅程通过；账号页面含中英及 390/768/1440px。
- 完整私聊旅程覆盖：首次注册配对、提供方与 bot、流式光标、工具展开、审批允许/拒绝、停止、同 run steer。
- 中途恢复覆盖：首次消息已接受但 RPC 响应断开后保留原 clientMsgId 重发且只有一个 run；审批刷新及 NodeApplication 关停重开；工具中断线重连。
- 同步覆盖：超过 1000 条未收到事件触发 snapshot；55 条新增历史后分页；两台独立 SQLite 节点切换不混用 bot，解绑后重登仍保留正确节点与归档结果。
- 主题、语言、reduced-motion、手机输入框边界与聊天内容无横向溢出已在浏览器实际检查。
- 截图在 docs/evidence/phase1-*.png：账号、团队、配对、新建 bot、流式私聊、展开工具、审批、设置和浅深色；live-chat 系列为真实历史的最新 WSL 构建复验，未新增模型调用。
- 视觉复验发现并修复手机聊天裁切、窄屏按钮重叠；双节点旅程发现并修复无 body 的 DELETE 请求误声明 JSON。

### 范围与保留资料

- 原 PDF/HTML 未删除或修改。HTML 只做静态解析及字体资源提取，没有换通道执行被拒绝的原稿；不能声称完成原稿逐屏视觉对照。
- 群聊、PWA 安装、远程一键安装、屏幕接管均不在 Phase 1；computerUse=false，网页无对应入口。
- 所有模块只在本地 commit，不推送。私有运行资料、模型配置、Node/Relay 数据及临时检出均在忽略目录，未清理现场。

### 全新检出终验

- 基于最终代码提交 `3816562395d700527b57f5018da705e2ae22fa2d`，新建
  `D:/nekodot-app/.runtime/phase1-clean-20261027-231530`；没有复制凭证、根 .env 或既有 node_modules。
- Node v24.22.1、pnpm 10.34.5；2026-10-27 15:15:31–15:16:35 UTC 完成。
- `pnpm install --frozen-lockfile`、`pnpm lint`、`pnpm typecheck`、`pnpm test`、`pnpm build`、
  `pnpm test:e2e` 六条命令退出码均为 0；7 个测试文件的 17 项场景和 2 个实际 Edge 旅程通过。
- 终验设置 CI=true、PLAYWRIGHT_WEB_PORT=4328，使用新检出的 Vite 服务；没有复用正在运行的 4318 开发页面。
- 实际报告保存在 `docs/evidence/phase1-clean-checkout-report.json`，检出现场与依赖仍保留。
- 检查全部 Git 跟踪文本，未发现本地 endpoint、model、API key 的实际配置值；真实截图中的模型标签已遮罩。
- 本次终验仅使用已录制资料回放，没有新增付费模型调用；真实模型结果保持独立报告。

# Phase 2 进度

| 模块        | 状态   | 验证                                                                             |
| ----------- | ------ | -------------------------------------------------------------------------------- |
| Node / 接力 | 已完成 | SQLite v2、CRUD、群 session、队列、上限、错误继续与恢复；19 项当前场景通过       |
| Web         | 已完成 | 群列表/面板、成员选择、作者、交接标签、接力计数、停止；Edge 群旅程与截图复验通过 |
| 整体验收    | 已完成 | 真实自定义 API 与全新检出分开验收；frozen install、四项检查和 3 条 Edge 旅程通过 |

## 2026-10-28 / Node 与真实群聊

- 真实网页完成注册、CLI 配对、自定义提供方、Researcher/Writer profile 和群聊。
- 真实 lead、多个成员按序、Bot 接力、自身/非成员提及忽略、六回合停止、同 run steer 与 stop 均通过，见 `phase2-live-report.json` 与 group fixtures。
- steer 保持 runId，工具执行和测试文件效果各一次；stop 后 cancelled，未执行成员未启动。Node 重启后历史存在。
- `group-failed.sse` 来自隔离连接故障的真实 `run.failed`；此前无效模型请求在上游 503 重试期间超出浏览器等待，现场保留，不能将该超时写为一次成功的即时验收。
- 已使用 Node 24 跑通 19 项场景与构建，包含 Phase 1 数据库实物升级、原私聊回归、群编辑/归档、成员顺序、错误继续、六回合、原 run 恢复、steer 和停止。
- 原 HTML 继续只作静态参考，没有改用其他通道执行原稿；新页面视觉验收独立进行。

## 2026-10-28 / Web 与整栈复验

- Edge 群旅程完成建群、编辑与归档、成员选择器、作者身份、Bot 接力、审批刷新/节点重启、断线、同 run steer 和停止；390/768/1440px、中英、浅深色及 reduced-motion 已实际检查并留图。
- 首轮全量回归的私聊测试在首个回复终止前发送下一条，实际走 steer；修正该场景等待空闲。另修正底层 Hermes 错误码不属于 RPC 枚举的问题；群旅程验证 HTTP 401 控制请求失败时保留草稿，再发后同 run 成功。
- 8 个文件的 19 项场景通过，另有 3 条完整 Edge 旅程通过；补验一个群等待审批时另一群完成、成员修改后节点重启仍使用原快照队列、后续消息使用新成员。
- 真实故障的最终 failed 与后续 Writer completed 已在网页复核。两次故障分别超过原页面 240/120 秒等待，延迟与观察过程保留在真实报告，不将超时标记为即时成功。
- 最新 WSL 代码再次完成真实定向回复、刷新、群编辑/主答变更及归档；新截图无个人路径或 provider 配置值。全新检出结果见下方终验记录。
- 真实 `group-nonfinal-mentions` 录制包含进度说明和工具命令的 @writer，最终无提及且只有一个 run；Node 将工具前文本归为 commentary，Web 不显示错误交接标签。旧消息不重写。
- 取消流程的真实 SSE 先发送 tool.completed(error=true) 再发送 run.cancelled；修正工具卡状态与回放序列，用户停止后的工具显示已停止。
- 最新 WSL 代码再次真实停止 sleep 工具：一个 cancelled run，未启动后续成员；工具卡及刷新后均显示已停止，证据为 `group-stop-latest` 和 `phase2-live-stop.png`。

## 2026-10-28 / 全新检出终验

- 基于最终代码 `d96712fec7fdcf9bd9ad5f62d3526912f27b878c` 创建独立本地检出；未复制根 .env、凭证或既有 node_modules。现场和命令日志保留在忽略目录。
- Node v24.22.1、pnpm 10.34.5；2026-10-28 07:59:20–08:00:13 UTC，六条命令的退出码全部为 0：frozen install、lint、typecheck、test、build、test:e2e。
- 8 个测试文件的 19 项场景与 3 条实际 Microsoft Edge 旅程通过；CI=true、PLAYWRIGHT_WEB_PORT=4358，使用新检出的独立网页。详细结果见 `docs/evidence/phase2-clean-checkout-report.json`。
- 真实模型结论仍独立记录在 `docs/evidence/phase2-live-report.json`；上游故障等待限制与最终接力结果均如实保留。回放未替代真实模型验收。
- 已人工查看新建群组、流式接力、工具/审批、真实失败继续、非最终提及、停止及三尺寸截图；中英、浅深色、reduced-motion 和无横向溢出通过。
- 检查全部 Git 跟踪及本次新增资料，未发现本地 endpoint、model、API key 的实际值；Phase 2 fixture/报告未发现个人目录。未删除参考、profile、历史、日志或检出现场；未推送任何 Phase 2 提交。
- 原 HTML 的逐屏视觉对照限制继续保留；产品本身的 Edge 视觉验收已完成。

## 2026-10-28 / Hermes 原生单 agent 边界

- 已核对产品调用链：`bots.ts` 为每个 Bot 创建独立 Hermes profile；`app.ts` 将私聊原文交给该 profile 的 `HermesApi.createRun`，会话使用 `nk_dm_<conversationId>`。产品不直接调用模型，也不实现 agent 或工具执行循环。
- 官方源码中 `gateway/platforms/api_server.py` 创建 `AIAgent`，`api_server_runs.py` 调用 `agent.run_conversation`。nekodot 的 SSE、审批、steer 与停止只是该原生运行的界面和控制入口；群聊只增加成员路由和上下文传递。
- 移除产品新建 profile 的 `--no-skills`，使用 `hermes profile create <botId> --no-alias` 的官方默认技能初始化。架构约定已写入 AGENTS.md、README 和 Summary.md。
- 在 WSL Ubuntu 24.04 / Node v24.22.1 中通过 `runHermesCli` 与官方 PM runtime 实际创建两个隔离 profile：均有独立 `.env`、SOUL、会话、记忆和技能目录，各包含 58 个技能，均无 `.no-bundled-skills` 标记。验证脚本及原始 CLI 日志保留在本地忽略目录；既有 profile 未修改或删除。
- `pnpm lint`、`pnpm typecheck`、`pnpm test`（8 文件、19 项场景）及 `pnpm --filter @nekodot/node build` 通过。本次修改只影响新 profile 的初始化，未新增模型调用；此前真实私聊和群聊证据保持独立记录。

# Phase 3 进度

## 2026-10-29 / Bot 跨私聊与群聊上下文

- 根因：Node 分别用 `nk_dm_<conversationId>` 和 `nk_grp_<groupId>_<botId>` 调 Hermes Runs；Hermes 自然把两者视作独立 session transcript。
- 修复：群聊每次调用对应成员 Bot profile 时，改用该 Bot 私聊 conversation ID 组成的同一 `session_id`。Hermes Runs 从原生 session transcript 续接上下文；Node 仍只负责群聊路由，不复制聊天历史或实现记忆机制。
- Node 集成场景先私聊、再群聊接力、归档后再私聊，检查 lead 同一 Hermes session，其他 Bot 使用自己的私聊 session。Edge 使用真实浏览器完成相同旅程，验证 run 的 profile/session ID；两项目标测试通过。
- 旧版群聊 session (`nk_grp_*`) 与产品聊天历史保持原状，不自动搬运到私聊；修复对发布后的新回合生效。

## 2026-10-28 / 浏览器私聊发送恢复

- 同步修复 Bot 弹窗滚动/固定操作区、侧栏与节点切换器、模型目录选择、双语布局及 Hermes 工具审批等级；Edge 完整私聊和群聊旅程覆盖这些操作。
- 根因：页面显示的是 Relay 报告的节点在线状态；发送却要求浏览器到 Relay 的 WebSocket 已就绪。页面恢复时两种状态短暂不一致，`callNode` 会立即报 “Computer is not connected”。
- 修复：发送等待当前 WebSocket 完成 hello；短暂断线时保留草稿并等待重连。每次重连捕获各自 socket，旧连接 close 回调不会清理新连接；浏览器 WebSocket 关闭不再冒充节点离线。
- 真实场景验证：Edge 页面唤醒后立即发送，等待浏览器 WebSocket 重连，消息到达 Node 一次；模拟 Node 回复断线后草稿保留并可重发。Node 24 下 `pnpm lint`、`pnpm typecheck`、`pnpm test`（21 项）及完整 3 条 Edge E2E 通过。

| 模块               | 状态         | 验证                                                                                                                             |
| ------------------ | ------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| 3.1 Relay 与分发   | 已实现并部署 | 本地构建并更新镜像；VPS 健康、含 `libatomic.so.1` 前置检查的 `/install.sh` 与 Node 下载均正常；既有 `/data` 挂载保留             |
| 3.2 本地开发入口   | 已实现并启动 | `pnpm dev:remote` 提供 4318 同源页面，复用已有健康隧道；`--lan` 绑定 LAN 可达，页面 HTTP 200                                     |
| 3.3 节点安装与服务 | 主要旅程通过 | 新 Ubuntu 24.04 x64 专属用户首次安装、systemd linger、真实私聊、服务重启历史保留通过；当前 Relay 通路依赖验收用反向 SSH 隧道     |
| 3.4 配对与多端恢复 | 主要旅程通过 | Edge 页面恢复重连并完成同步；两客户端私聊/群聊、30 秒离线恢复及新 VPS 节点恢复通过；真实手机后台恢复未测                         |
| 3.5–3.6 整体验收   | 部分完成     | frozen install、lint、typecheck、21 项测试、build、3 条 Edge E2E 及真实 API 私聊/群聊通过；手机与长期服务器间 Relay 通路仍待验收 |

## Phase 3 实际结果 / 2026-10-28

- Relay 镜像在本地构建后上传到现有 VPS；仅重建 `nekodot-phase3` 项目容器，没有重启整机、Caddy 或其他项目。部署后 `/health`、`/install.sh`、`/downloads/nekodot-node.cjs` 均可用，数据库 bind mount 未变，账号可继续登录。
- 本机 `dev:remote` 在 4318 提供页面，浏览器 HTTP、WebSocket 和下载经同源代理。由于 WSL systemd SSH 隧道已占用本机 4329 且 Relay health 正常，启动器复用该隧道而未额外启动第二条 SSH 连接。独立 `--lan` 测试在 LAN 接口地址上返回 HTTP 200；未进行真机访问。
- WSL Ubuntu 24.04 x64 中重复执行从新 Relay 下载的安装器，无 `--pair` 参数。安装器保留已有 nodeId 与数据，发现 18642 已由 Phase 1 Hermes 使用后选择 18643；当前 nekodot Node 服务 `active/running`，Phase 1 进程未触碰。
- 新服务器基线为 Ubuntu 24.04 x64，原本没有 Hermes/nekodot；原有 Docker 应用和端口保持运行。首次 Hermes PM 安装发现缺少 `libatomic.so.1`，仅安装系统包 `libatomic1`（50.2 KB）；随后的 `cua-driver` 可选校验报告缺少 `libXi.so.6`，未安装图形库，因为本阶段不含屏幕控制。
- 根据该现场，安装器在 Node/Hermes 下载前检测 `libatomic.so.1` 并打印 Ubuntu/Debian 包名。重建并只更新既有 Relay 容器后，`/health`、`/install.sh` 和 `/downloads/nekodot-node.cjs` 均返回 HTTP 200；Node 下载实测 1,389,522 字节，Relay `/data` 绑定挂载未变。
- 追加页面恢复浏览器旅程后，修复了非法 WebSocket 关闭码及恢复同步后节点状态仍显示离线的问题。Edge 实际触发 `pageshow` 后重新建立 `/ws/client` 连接、完成 Node 同步且无 pageerror；独立检出顺序执行 frozen install、build、3 条 Edge E2E，结果 3 passed。
- 使用专属 `nekodot` 用户和 linger 安装真实 Node/Hermes，服务 `active/running` 且重启计数 0。Edge 在新节点创建独立 profile 并收到真实自定义 API 回复 `NEKODOT_PHASE3_NEW_VPS_OK`；主动重启该 Node service 后，网页重新登录仍显示原消息。
- 新服务器没有到 Relay 的预置 SSH key。验收使用本机建立的 loopback 反向 SSH 隧道；关闭 30 秒后 Relay 将 Node 标为离线，恢复转发后 Node 自动回到在线，刷新后历史不变。该临时链路不等于服务器间持久 Relay 连接，验收后续使用仍须保留隧道或配置专用服务器间认证。
- 目标机预检时 `systemd-networkd-wait-online.service` 已失败，未改动该状态；只重启新建的 nekodot Node user service，既有 Docker 容器没有重启。
- Edge 使用本地已有账号登录，没有重复注册或消费配对码。真实自定义 OpenAI-compatible API 的私聊回复成功；第二个 Hermes profile 在群聊收到非主答成员的 @handle 定向请求并成功回复。
- 两个独立 Edge 客户端看到同一私聊及群聊记录；私聊第二客户端离线 30 秒期间由第一客户端发送，恢复后同步到新消息。真实截图为 `phase3-live-chat.png`、`phase3-second-device-390.png`、`phase3-group-390.png`；初次配对界面为 `phase3-pairing-live.png`。
- 实际命令：`pnpm install --frozen-lockfile`、`pnpm lint`、`pnpm typecheck`、`pnpm test`（9 文件、21 项）、`pnpm build`、`CI=true PLAYWRIGHT_WEB_PORT=4358 pnpm test:e2e`（3 条 Edge 旅程）。另实际构建隔离 Docker 镜像并验证其不含源码目录，安装器和单文件 Node 下载 HTTP 均成功。
- 未完成项：最新版本全新 WSL 配对、手机真机后台恢复，以及不依赖本机验收进程的持久服务器间 Relay 通路；开发脚本自建 SSH 隧道重连分支也未单独触发。Phase 3 不整体标记为全部验收完成。
- 证据文件 `docs/evidence/phase3-live-acceptance.json` 不记录账号、密钥、endpoint、model 名或 SSH 目标；既有 provider `.env`、账号、profile 和临时现场均留在本地。
- 提交 `fb5f8b6` 后另建独立本地克隆 `.runtime/phase3-clean-20261028`，不复制 `.env`、账号或 `node_modules`；Node 24.22.1 / pnpm 10.34.5 的 frozen install、lint、typecheck、21 项测试、build 和 `CI=true PLAYWRIGHT_WEB_PORT=4368 pnpm test:e2e` 均通过。新检出现场保留。

### 2026-10-29 / Side Phase 原生管理与记忆

- 增加 loopback 官方 `hermes serve --isolated` 管理进程，复用项目 home、PM runtime 和显式 profile；聊天仍走原 Runs API。Node 管理模块为 `hermes/management.ts`、`bot-management.ts`、`operations.ts`。
- 增加定时任务只读、三份原生记忆文档、原生 `/refine`、待审核操作及可轮询长操作；操作重启后标为中断并要求核对 Hermes 实际状态。
- 角色更新保留 SOUL 原生学习内容及托管规则；隔离 profile 的角色编辑保留场景已实测。
- 实际网页保存 USER 偏好、原生 memory 工具保存任务经验及 `/refine` 完成；独立原生会话读取偏好且另一 Bot 未读到该偏好。聊天创建的一次性任务在详情可读，Node 重启后任务文件仍只有一次写入。
- Node 24 当前工作区 lint、typecheck、21 项场景、build 和 4 条 Edge 旅程通过；完整清洁检出终验在后续提交记录。

### 2026-10-29 / Side Phase 文件交付与资料库传输

- 增加 `files.ts`、附件元数据和交付副本，按实际发送 Bot、会话和消息收录 MEDIA 与文件链接；历史补录按消息及引用去重，不合并同名新版本。
- Relay 通过既有 Node 出站连接分块转发认证上传和下载，Node 不新增公网监听，Relay 不保存文件正文。
- 真实私聊生成文本、SVG、PDF、二进制文件；真实群聊四类交付归属发送 Bot。Edge 已核对卡片、资料库、预览、下载、来源跳转、同名版本、补录去重和刷新。
- 修复消息查询时流式缓存丢弃附件标识的问题，群聊真实回复和刷新复验通过。修改原工作文件后交付副本未变；Node 重启后附件仍保留。

### 2026-10-29 / Side Phase Bot 详情、Skills 与插件

- Bot 详情面板提供只读 Hermes 定时任务与执行历史、SOUL/MEMORY/USER 原生文档编辑、`/refine` 操作状态和待审核记忆/技能变更；Bot 角色编辑与 SOUL 共用保存内容。审核动作复用 Hermes 原生命令，按钮文案明确为“应用变更”。
- 应用导航增加节点隔离的 Skills 和插件目录；展示官方/社区/本地来源、说明、平台与依赖、Bot 安装状态及 Hermes 返回的生效信息。支持官方/Git 安装、本地 SKILL.md/目录/ZIP 导入、多 Bot 安装、原生启停、插件配置和所需密钥输入。
- Edge 验证覆盖 Bot 详情、记忆保存、文件预览/下载、Skills 内容/停用、800+ 插件目录和 390/768/1440px 无横向溢出；截图保留在 `docs/evidence/sidephase-*.png`。此前真实 Hermes 验收截图记录了 `/refine`、记忆审核、定时任务、技能脚本与插件工具运行。
- Node 24.22.1 下本轮 `pnpm test` 为 9 个文件、21 项通过，`pnpm typecheck`、`pnpm build` 及 4 条 Edge E2E 通过。格式检查发现摘要/进度 Markdown 未符合 Prettier，本轮统一格式后复验。

# UI 改版进度

| 模块                    | 状态   | 验证                                                                                                                                 |
| ----------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| 0 画板导出              | 已完成 | 九块画板静态展开后由 Edge 截图为 `design/01-home.png` … `09-tokens.png`                                                              |
| U1 基础层               | 已完成 | tokens 层级、按钮与图标按钮、状态点、群色点、分段控件；lint/typecheck/Edge 旅程通过                                                  |
| U2 首页与侧栏           | 已完成 | 桌面侧栏、手机首页卡片与新建菜单、⌘K 命令面板、会话预览；三尺寸、中英、深浅色截图与 4 条 Edge 旅程通过                               |
| U3 消息流（私聊与群聊） | 已完成 | 顶栏、作者分组、时间分隔、Markdown、工具与审批卡、状态条、自适应输入框、回到最新；4 条 Edge 旅程首轮通过                             |
| U5 新建/编辑面板        | 已完成 | 手机底部面板可下拉关闭、桌面居中弹窗；bot 头像实时预览、色块滑动选中环；群组成员卡片与主答标记；全站表单字段统一；4 条 Edge 旅程通过 |
| U6 添加电脑             | 已完成 | 画板 05 布局、选择卡滑动描边、编号步骤、深色命令框高亮配对码、倒计时环与过期重生、连接成功庆祝；4 条 Edge 旅程通过                   |
| U7a 设置与登录          | 已完成 | 卡片式设置、提供方滑块切换、主题开关、底部解绑确认；左右分栏登录页；并入原生通知设置与剪贴板；4 条 Edge 旅程通过                     |
| U4 屏幕面板视觉         | 已完成 | 按画板 06/07 改为常深色面板：实时徽标、成员胶囊、控制条与接管呼吸描边、圆角画面框、键盘卡片；接管逻辑不变；4 条 Edge 旅程通过        |
| U7b 详情与扩展中心      | 已完成 | bot 详情改为右侧滑入卡片面板与分段标签；Skills/插件标题、卡片悬停、详情弹窗与资料库文件卡统一；全部检查与 4 条 Edge 旅程通过         |

## 2026-10-29 / 画板导出

- 用户将 Web UI 开发交由新的实施方，并要求在原稿基础上重新设计得更高端、大气、简洁、可交互性强，并配合恰当动效。计划外决定：视觉在原稿的颜色、字体、猫耳头像与气质上延展，PDF 第 11 节的 tokens、数值与动效规格继续作为下限。
- 原 HTML 为两层打包页面；逐块解出模板，按模板自带示例数据静态展开，未执行原稿脚本。字体使用产品已有的 Nunito / JetBrains Mono 本地文件，Edge 2x 截图。
- 九张截图已人工查看：首页、私聊、群聊、新建 bot、添加电脑、实时画面、桌面三栏、动效（第 1 秒画面）、颜色字体头像均完整渲染。长期记录的"原稿视觉核对受限"由此解除。

## 2026-10-29 / U1 基础层

- `tokens.css` 在 PDF 第 11 节色值之上增加 `--raised`、`--ink-3`、悬浮/按下色、遮罩、三级阴影、`--radius-panel` 与 `--ease`；浅深色两套同步定义。
- 按钮统一为墨色主按钮（悬浮上浮 1px + 阴影）、1.5px 描边次按钮、轻量按钮；按下统一缩至 0.97。图标按钮改为 12px 圆角，新增带描边的 `bordered` 变体；“需要你”标签与快捷键标识成为通用样式。
- `ui.tsx` 新增 `StatusDot`（在线外圈脉冲、重连琥珀旋转环、离线静止）、`GroupDots`、`Segmented`（选中块弹簧滑动）、`Kbd`，并补齐设计稿图标（返回、屏幕、搜索、文档、终端、勾、警示、复制、成员、bot 等）。Logo 文字去掉句点，与画板 07 一致。
- 所有循环动效仍受 `prefers-reduced-motion` 约束；分段控件在减少动态效果时直接切换。

## 2026-10-29 / U2 首页、侧栏与命令面板

- 桌面侧栏（`features/sidebar.tsx`、`styles/shell.css`）：`--surface-2` 底，Logo + 设置；电脑状态胶囊（在线脉冲 / 重连旋转环 / 离线）；“搜索或跳转”入口；聊天 / Skills / 插件分段控件。Bot 行显示最后一条消息、时间、思考中三点（取该 bot 头像色）、“需要你”标签；在群里工作的 bot 显示“在群「…」回复中”。选中行是一块随切换弹簧滑动的浮起卡片；悬停时猫耳抖动一次。
- 手机首页（<1024px）沿用画板 01：28px“团队”标题、节点状态行、白色 bot 卡片（名字、时间、角色、最后消息）与 `--surface-2` 群卡片；右下角橙色新建按钮旋转 45° 展开“新建 bot / 新建群组”两枚胶囊，带遮罩。点开会话从右侧推入、返回从左侧滑回，动画只由导航触发，缩放窗口不会重放。
- ⌘K / Ctrl+K 命令面板（`features/command-palette.tsx`）：搜索 bot、群聊和操作（新建、Skills、插件、设置、添加电脑、切换语言），方向键移动、Enter 打开、Esc 关闭，选中高亮滑动跟随。
- 修正首页列表一律显示“还没有消息”：同步完成后为尚未加载的会话各取最近 6 条用于预览（`relay-connection.tsx`），打开会话时仍完整加载 50 条。store 新增浏览器 WebSocket 就绪状态，驱动“重连中”显示。
- 验证：本地演示环境（`.runtime/ui-stage.ts`，回放 Hermes + Relay + 预置中文 bot/群/消息）在 Edge 中截取 390/768/1440px、中英、浅深色及命令面板、新建菜单，证据为 `docs/evidence/ui-u2-*.png`，无横向溢出、无页面错误。
- 群聊与扩展两条 Edge 旅程加载 `apps/web/dist` 构建产物，需先 `pnpm --filter @nekodot/web build` 才会测到新界面；按此重建后 lint、typecheck、21 项测试、build 与 4 条 Edge 旅程全部通过。E2E 会重写旧阶段证据截图，已还原为原记录。
- 首轮 E2E 发现：手机推入动画若绑定在显示切换上，视口从 1440 改为 390 时也会播放，测得输入框瞬时越界 18px；改为由导航触发后通过。

## 2026-10-29 / 产品 README 草稿

- 交付 `README.draft.md`，采用面向使用者的产品说明顺序：定位与主图、功能与工作场景、响应式界面、首次使用、架构与数据、开发部署及当前进展。现有 `README.md` 保留。
- 使用并人工查看 `ui-u2-sidebar-1440.png`、`ui-u2-home-390.png`、`ui-u2-palette-1440.png` 三张已入库截图；明确它们来自开发版实际页面与演示数据，不作为新的真实模型验收结论。
- 内容核对现有开发说明、架构约定与阶段证据，保留 Hermes 原生 profile 边界和未完成的平台、App、PWA、屏幕接管及真机验收说明，不引入新的功能承诺。
- 草稿 14 处本地图片、文档与章节引用核对通过；本轮仅文档变更，不改动产品代码、不触及配置或运行现场，不重新执行真实模型任务。

## 2026-10-29 / 公开仓库 README

- `README.md` 改为公开仓库首页，底稿为 `README.draft.md`（草稿文件保留，未删除）。删去“验收”“阶段”等内部用语，补充与云端 agent / 原版 Hermes 的差异、开发者预览说明、自托管 Relay 五步上手、路线图、致谢与许可证占位；新增 `docs/assets/nekodot-mark*.svg` 两版 Logo。
- 工程细节移入 `docs/development.md`，并补充“群聊与扩展 E2E 读取 `apps/web/dist`，改界面后需先构建”的注意事项。
- 核对：环境变量、`dev:remote` 参数、安装器平台限制、Relay 仅 loopback 部署均与代码一致；修正草稿中“HTTPS”与“6 轮接力”的不准确表述。README 与开发说明共 16 处本地链接全部可解析，Prettier 通过；本地渲染截图人工检查版面。
- 公开前检查：Git 跟踪文件未发现密钥、私人 IP 或本机路径；fixtures 中的两个邮箱来自第三方插件目录公开元数据。仓库没有 LICENSE 文件，CI 徽章需仓库公开后才能显示。

## 2026-10-29 / U3 消息流（私聊与群聊）

- 聊天样式独立为 `styles/chat.css`，`chat.tsx` 重写渲染层；发送、补充指令、停止、审批、分页及节点重连逻辑不变。
- 顶栏：头像（群聊为成员色点）+ 名称 + 状态行。状态行在空闲时显示 `@handle` 或成员数，运行时显示“正在回复 / 正在运行工具”并带三点，等待审批时用 `--accent-text` 加粗；群聊固定显示“主答: X”。右侧为详情按钮。
- 消息流：同一作者的连续消息合并为一组，头像只出现一次并在长回复中吸顶；群聊每组显示“名字 @handle”。会话开头显示介绍卡（头像、角色、`@handle · 模型`）；首条消息及间隔 30 分钟以上插入“今天 15:17”式分隔线。离开底部后不再强制滚动，出现“回到最新 / n 条新消息”浮动按钮；加载更早消息时保持阅读位置。
- Bot 回复按安全子集渲染 Markdown（标题、列表、引用、行内代码、粗体、链接、代码块带复制），不注入 HTML；流式光标保持在最后一行文字末尾。悬停回复可复制全文。群聊中的成员 @ 在用户气泡和回复里加粗高亮。
- 工具卡：按工具类型显示图标格、等宽工具名与参数，完成显示耗时与对勾，进行中为 bot 颜色的旋转环，失败/停止显示文字；状态图标 150ms 交叉淡入，点开以 spring(400/32) 展开“输入 / 结果”。
- 审批卡：待处理时 accent 描边并轻微呼吸外发光；“允许一次”主按钮与“拒绝”次按钮等宽，本会话/始终允许收为下方胶囊；处理后卡片转为中性并显示结果标签。
- 输入区：状态条在运行时滑出（头像 + “小研在等你确认 / 正在回复”+ 停止胶囊）；胶囊输入框随内容增高至 168px，Enter 发送、Shift+Enter 换行、输入法组合中不发送；@ 成员浮层支持方向键、Enter/Tab 选择。接力进度改为 6 段进度条 + “接力已进行 n / 6 轮”，交接标签带被 @ 成员头像上跳。原计划 U4 的群聊消息部分已在本模块完成，群组编辑面板并入 U5。
- 首页预览去除 Markdown 标记。演示环境补充 Markdown 周报、失败工具和较早的会话。证据：`docs/evidence/ui-u3-*.png`（390/768/1440、浅深色、英文 + 减少动态效果、工具展开）。重建 web 后 lint、typecheck 与 4 条 Edge 旅程通过，旧阶段截图已还原。

## 2026-10-29 / U5 新建与编辑面板

- 新增 `features/sheet.tsx`：手机（<768px）为画板 04 的底部面板，顶部拖拽条可下拉关闭（位移 >120px 或快速下滑）；更宽屏幕为居中弹窗。Esc 与点击遮罩关闭，打开/关闭 320ms 同消息曲线。样式在 `styles/sheet.css`。
- Bot 面板：88px 头像实时预览，换色时弹性回弹并带同色柔光，下方显示名字与 `@handle`；8 个颜色圆点，选中环用共享布局在色块间滑动，按钮带颜色名称；“它负责什么？”附提示语；@ 名称输入带前缀并说明规则。新建时底部为整宽主按钮“创建 <名字>”（PDF 11.3），编辑时为归档 / 取消 / 保存。
- 群组面板：已选成员的色点随勾选弹入弹出，成员改为可点选卡片（圆形勾选、`@handle · 角色`、主答标签），主答选择附说明。
- 全站表单基础样式改为零优先级 `:where()`：标签 14px 级粗体墨色，输入框 46px、12px 圆角、悬停加深边框、聚焦墨色描边 + 3px 柔和外环，下拉统一自绘箭头；组件自身样式始终优先。
- 计划外决定：按 PDF 把新建按钮文案改为“创建 <名字>”，两条 E2E 中对应的按钮名称同步更新，其余选择器不变。
- 证据 `docs/evidence/ui-u5-*.png`；重建 web 后 lint、typecheck 与 4 条 Edge 旅程通过，旧阶段截图已还原。

## 2026-10-29 / U6 添加电脑

- 页面按画板 05 重排（`styles/pages.css`）：返回 + 三段步骤条“第 2 步，共 3 步” + 语言；28px 标题与无需开放端口的说明；“这台电脑 / 云服务器”两张卡片，选中描边用共享布局在两卡之间滑动；编号步骤随目标切换。
- 命令框在浅深色下都保持终端深色，配对码以 accent 底高亮、不折行；纸色“复制命令”按钮复制后变为对勾“已复制”。
- 等待卡显示“配对码 XXXX-XXXX · m:ss 后过期”与随剩余时间收缩的倒计时环；过期后整卡变为提示色并就地提供“重新生成”。新电脑上线时等待卡交叉淡出为成功卡：新头像 0.6→1.08→1 回弹、8 个头像色小点向外散开（600ms），约 1.4 秒后回到团队。已配对电脑以状态点列表显示。
- 原 `.pair-*`、`.choice-*`、`.command-*`、`.copy-button` 旧规则从 `style.css` 移除，设置页共享规则保留到 U7。证据 `docs/evidence/ui-u6-*.png`；重建 web 后 4 条 Edge 旅程通过，旧阶段截图已还原。

# Phase 4 进度

## 原生能力与安装 / 2026-10-29

- 已实现 profile 作用域的 display 状态、生命周期、观察和 lease 调用；Node 不持久化屏幕状态，不增加 agent 引擎。
- 在独立 Linux 验收目录与端口安装官方 driver 0.21.0、TigerVNC/Xfce，启动两个独立 1440×900 屏幕；未覆盖原 profile 或重启其他服务。
- 新安装发现依赖顺序和 Chromium 缺少音频库，安装器已据实修正，说明见 `docs/hermes-screen-notes.md`。重复安装及无权限分支仍需继续验证。
- `docs/fixtures/display-native.json` 为真实原生状态；typecheck、21 项原有场景、构建通过。真实模型、桌面输入、恢复与全新检出尚未整体完成。
- Phase 3 的长期 Relay 通路与真机恢复待验收项目继续保留，本阶段不将其标为完成。

## Relay 通道 / 2026-10-29

- 认证票据及两段 WebSocket 转发已实现。真实 Edge 可看见 Linux 原生 Xfce，通过两个独立浏览器上下文轮流接管并交还。
- 实际路由测试通过：另一账号不可申请、离线拒绝、票据单次使用、双向二进制、原生 4000、主动 1000、异常 1006、重连和解绑。未开放 VNC/CDP 公网端口。
- 真实状态回放只测试适配与路由，不替代 Linux 画面和输入验收。

## Web 与接管 / 2026-10-29

- 完成私聊、详情、群聊入口，noVNC 只读/控制、键盘、粘贴、常用按键、缩放、操作进度和安全上下文说明；480px 侧栏与窄屏全屏已在 Edge 打开。
- 真实 Linux Edge 旅程通过：两个 viewer 接管与交还、断网禁用输入、同身份恢复、人为丢失身份后强制交还、刷新和主动关闭后交还，390/768/1440 无水平溢出。验收脚本需本地私有账号文件，日常测试不会调用真实模型。
- 原生模型的同一 run 内完成浏览器导航/填写 → 人工接管输入 → 交还 → 校验原值 → 一次提交；测试服务收到正确的两个字段。未 stop 或重开该 run。
- 另一 profile 的真实 computer_use 经过原生审批使用 Xfce Terminal/nano 输入、保存测试标记；服务器文件核对正确。未用文件写入工具替代桌面操作。
- Node 24 lint/typecheck、23 项测试、构建通过；独立全新检出、SSH/Node 恢复、profile 浏览器资料保留及完整安装器仍继续验收。

## 整体验收与恢复修正 / 2026-10-29

- 完整下载安装在独立 Linux 用户通过；官方 screen → driver → PM Chromium 顺序生效。重复安装保留 nodeId、不消费无效码；权限不足显示原生命令并保留数据；`--uninstall` 仅停禁用服务。独立安装用户目前保持停用，验收文件未删除。
- 真实模型同 run 接管的表单结果、原生 nano 文件和后续只读 GUI 复核通过；profile 的测试 cookie/localStorage 相互隔离，Node 重启后同 profile 资料保留。
- 真实 SSH、管理后端与 Node 服务重启恢复通过，消息/run 数量和文件不变，自动新增 run 为 0。修复节点断线时 Relay 清除屏幕会话造成身份无法续接的问题。
- 实际 Edge 完成双 viewer、断网禁用输入、身份保留、丢失身份强制交还、主动关闭、刷新、群聊成员选择及 12 种尺寸/语言/主题组合；reduced-motion 和窄屏焦点检查通过。
- 屏幕 Operations 完成后同步更新面板状态，避免下一次启动/停止一直禁用；真实 Linux 停止/再启动通过。当前工作区 lint/typecheck、23 项测试、build、4 条常规 Edge 旅程及独立真实屏幕旅程通过；全新检出复核继续记录于下方。
- 原始桌面 run 在 gateway 重启后不再可查，没有补造 SSE；保留真实工具记录、文件、截图与后续只读 GUI 核对。真实接管 SSE/state 已脱敏入库。
- 使用说明、图片与限制集中在 `docs/phase4-acceptance.md`。Hermes 稳定版可能关闭已结束回合的浏览器窗口，资料保留与窗口常驻分开记录。手机真机、HTTPS、其他平台屏幕、内存耗尽场景未标为通过，Phase 3 遗留项不变。

## 最终代码检出复核 / 2026-10-29

| 项目                     | 结果                                                                                                 |
| ------------------------ | ---------------------------------------------------------------------------------------------------- |
| 独立检出                 | 原始独立 clone 未复制 `.env` / `node_modules`，更新至最终代码 `cabd55a`；依赖在检出内安装。          |
| frozen install           | Node 24.22.1 / pnpm 10.34.5 通过。                                                                   |
| lint / typecheck / build | 全部通过；Vite 现有主 bundle 体积提示不影响构建。                                                    |
| 自动化场景               | 11 个文件、23 项通过。                                                                               |
| 常规 Edge                | 4 条旅程通过；独立端口启动该检出页面。真实屏幕项因无私有账号文件明确 skip。                          |
| 真实 Linux 屏幕 Edge     | 单独 1 条旅程通过，包含接管/交还、离线、双 viewer、刷新、身份丢失、强制交还、主动关闭及停止/再启动。 |
| 真实模型                 | 同 run 浏览器人工接管、一次提交、原生桌面文件、profile 隔离与重启资料保留均通过，详见真实旅程记录。  |

- 结果文件为 `docs/evidence/phase4-clean-checkout-report.json`；真实接管 fixture 为 1 个 run、5 个工具开始/完成和 1 个 completed，未用回放替代真实结论。
- 历史阶段截图未被新 E2E 结果覆盖；本轮回归画面保留在私有验收目录。所有 profiles、历史、参考资料和安装测试现场继续保留。
- Phase 4 当前范围已完成；手机真机屏幕、HTTPS、其他平台屏幕以及 Phase 3 长期连接和真机恢复项目继续待后续验收。

# Side Stage 2 进度

## 客户端基础 / 2026-10-29

- Tauri 2 共用现有 React 代码，Windows/Android 使用随包资源；新增统一 Relay 地址、系统文件接口、PDF.js、应用恢复和进程内草稿。Android 原生桥接使用官方 Firebase SDK，Windows 使用托盘、单实例及窗口状态插件。
- Windows NSIS 调试安装器编译通过，实际页面 origin 为安全的本地应用 origin；关闭不结束进程，二次启动恢复同一窗口且仅保留一个客户端进程。
- Android x86_64 调试 APK 编译、安装和覆盖安装通过；独立 Android 15 模拟器实际打开，安全上下文、原生桥接及窄屏无水平溢出已核对。模拟器不代替真机结论。
- 本轮实际 Node 24 类型检查、12 个文件/24 项自动化场景通过；最终 lint、全新检出及完整回归仍继续。截图为宿主验证，尚未通过公网域名登录产品环境。
- 缺少域名/DNS、Firebase 配置与凭据、Google 服务真机；正式 HTTPS、真实推送、双端远程 App 和真机屏幕不标记通过。原测试环境与 Phase 3 遗留项继续保留。

## 产品服务与通知 / 2026-10-29

- 独立产品 Relay 容器、数据库、Node 系统用户与 Hermes home 已部署；Relay 为 loopback 4349，Runs/管理为 loopback 19042/19043。产品 Node 使用同机 Relay，既有 Caddy 配置和其他产品服务未重启。
- 产品首次账号通过原有配对流程绑定独立节点。真实 API 已保存并完成私聊、两个不同 profile 的定向群聊；Node 服务重启后 2 个 Bot 和已有历史保留，再次私聊/群聊通过。具体脱敏结果见 `evidence/side-stage-2-server-smoke.json`。
- 最小通知经认证 Node WS 发给 Relay，持久待确认与重复投递去重已接入；实际私聊完成 1 条、两成员群链结束 1 条。设备注册、另一账号不可注销、通知归属与重复确认使用真实 HTTP/WS 自动化检查。
- Firebase 服务端凭据显式从私有配置文件读取；未配置时状态接口明确不可用。尚未实际发送 FCM，不以最小通知路由通过替代推送通过。
- 生产下载固定提供 Windows x64 EXE 与 Android arm64 APK 路径；缺包返回 404，未上传测试占位包。独立 HTTPS 路由模板已准备，域名/DNS 未提供，因此没有修改现有 Caddy 或新增公网端口。

## 原生平台抽查 / 2026-10-29

- Windows 测试宿主实际保存 `nekodot-中文验收.txt` 并通过官方 fs 插件写入和读回；本地安全 origin、单实例恢复及关闭留驻已实测。干净用户安装、开始菜单、托盘退出、覆盖安装与 Windows 10 尚待正式包验收。
- Android 15 / x86_64 独立模拟器实际安装和覆盖安装，系统保存/选择中文文件并核对内容；进入后台再返回后进程与无害登录表单输入保留，收到 pause/resume。此处未登录产品账号，不将表单输入保留声称为真实聊天草稿验收。
- Android 原生桥接在缺少 Firebase 配置时返回明确错误；截图与状态见 `evidence/side-stage-2-android-*`。尚未完成 arm64 release、签名 APK、真机后台推送、真实屏幕触摸及双端远程旅程。

## 原生构建与平台补验 / 2026-10-29

- Android x86_64 与 arm64 调试 APK 编译通过；arm64 包实际仅包含 arm64-v8a 的 `libapp_lib.so`。已通过标准 `scripts/build-client.mjs android --debug --target aarch64` 入口构建，不依赖私有替代构建流程；调试宿主缺少 Firebase 时明确不可用，release 仍要求配置与签名。
- 模拟器实际按系统返回键后进入后台、再次打开保留进程；系统分享 chooser 正常弹出，未选择任何接收应用。结果见 `evidence/side-stage-2-android-interactions.json`。
- 本地 Android 发布密钥和对应四项环境参数已保存在 `.runtime/side-stage-2/private/nekodot-release.p12` 与 `android-signing.json`，没有进入 Git、日志或聊天。该密钥尚未用于正式发布包。
- 最新产品 Node 更新后，首次探测早于 Hermes 冷启动完成而显示离线；服务随后正常在线，重新真实私聊和两成员定向群聊通过，已有 2 个 Bot、历史及 profile 保留。未新增产品重试机制或重跑未完成用户任务。
- 用户回复域名与 Firebase 稍后提供，因此公网 HTTPS/WSS、FCM、Windows 正式安装器与 Android 签名 release、真机及双端旅程继续待联调。没有将此阶段整体标记完成。

## 独立检出与交付状态 / 2026-10-29

最终可执行代码 `fa6e675` 在独立检出复核。检出内自行 frozen install，没有复制 `.env`、账号、签名资料、原 `node_modules` 或 native target。

| 检查                            | 结果                                                           |
| ------------------------------- | -------------------------------------------------------------- |
| frozen install、lint、typecheck | 通过                                                           |
| 自动化场景                      | 12 文件、24 项通过                                             |
| Web / Relay / Node / 分发构建   | 通过                                                           |
| Edge                            | 4 条通过；真实屏幕项因无私有现场 skip，不视为 App 屏幕验收     |
| Windows x64 调试 NSIS           | 独立检出标准构建通过，生成 0.1.0 安装器                        |
| Android arm64 调试 APK          | 独立检出标准构建通过；arm64-v8a，0.1.0 / versionCode 1         |
| 真实模型                        | 产品 loopback 环境实际私聊、两成员群聊和 Node 重启历史保留通过 |
| 正式公网与双端 App              | 待域名/DNS；未发布测试占位地址安装包                           |
| 真实 FCM 与 Android 真机        | 待 Firebase 和设备，未将模拟器或路由测试作为替代               |

完整说明、原生截图与待办见 `side-stage-2-acceptance.md`；机器结果为 `evidence/side-stage-2-clean-checkout-report.json`。Android 私有发布密钥已准备但未用于发布测试包，Windows 未做 Authenticode 签名。现有 UI 修改与所有历史/验收现场继续保留，所有提交均只在本地。

## 2026-10-29 / U7a 设置与登录（基于原生客户端版本）

- 在 GPT 完成的 Windows/Android 原生客户端、屏幕接管与通知基础上继续 UI：设置页（`features/settings.tsx`）改为 640px 单栏卡片，依次为模型提供方、已连接的电脑、外观、通知（仅原生端）、账号。提供方切换为分段滑块；电脑行带平台图标与状态点，当前电脑标 accent 小点；主题为带日/月图标的开关（`role="switch"`）；解绑改为底部深色确认条，说明解绑后数据仍留在该电脑。
- 原生通知设置沿用 `NotificationSettings` 的逻辑，只调整为与其他卡片一致的标题 + 操作结构；已开启时不再显示按钮。设置页 CLI 复制、Markdown 代码块与消息复制统一改用原生安全的 `writeClipboard`。
- 登录/注册页（`features/auth.tsx`）改为左右分栏：左侧 `--surface-2` 品牌区，四只猫耳 bot 弹入后缓慢漂浮（工作中的那只摆耳），标题、说明、三条要点与链路标签；右侧 380px 表单，注册/登录切换时标题交叉淡入；手机端品牌区收窄为头像 + 标题。
- 旧设置、登录与配对相关规则从 `style.css` 移入 `styles/pages.css`，`style.css` 只剩全局基础与共享组件。修正 U5 统一表单后扩展页与资料库筛选栏中下拉框过宽的问题。
- 证据 `docs/evidence/ui-u7-*.png`（设置 390/1440/深色，登录 390/1440/768 深色）。重建 web 后 lint、typecheck 与 4 条 Edge 旅程通过；`screens-live` 需要真实 Linux 节点，按设计跳过。旧阶段截图已还原，GPT 留下的未跟踪 phase4 证据未改动。

## 2026-10-29 / U4 屏幕接管面板视觉

- GPT 完成的 noVNC 屏幕面板（`features/screen.tsx`）只改外观与外层结构，连接、接管、交还、键盘输入和重连逻辑不变。
- 面板在任何主题下都是画板 06/07 的深色：在 `.screen-panel` 内重设 tokens，按钮、下拉框和操作进度卡自动跟随。桌面 ≥1280px 为右侧 480px 栏并从右侧滑入，较窄屏幕为全屏面板从底部滑入（280ms），关闭按钮在全屏时改为下拉箭头；减少动态效果时不播放。
- 头部显示 bot 头像（屏幕由 bot 控制时摆耳）、“Bot 屏幕”、运行时的 accent “实时”脉冲徽标；群聊成员切换由下拉框改为头像胶囊单选组。
- 控制条为深色卡片；自己接管时整条变为 accent 底，画面外框加 2px accent 描边并以 1.2s 呼吸。画面框按 1440:900 比例、12px 圆角；未启动/未安装/不支持状态为居中空状态卡片；键盘输入改为可折叠卡片，按键为等宽小按钮。
- 演示环境在 `.runtime/ui-stage.ts` 中为两只 bot 伪造“运行中 / 未启动”的屏幕状态（仅开发脚本，不进入产品），以便在 Windows 上设计；真实画面与接管仍以 GPT 的 Linux 实机验收为准。
- 证据 `docs/evidence/ui-screen-*.png`。lint、typecheck、build 与 4 条 Edge 旅程通过；`screens-live` 需真实 Linux 节点，未在本机运行。

## 2026-10-29 / U7b Bot 详情与扩展中心

- Bot 详情面板宽 560px，从右侧滑入，遮罩改为统一 `--scrim`（去掉毛玻璃模糊）；头部 20px 标题 + 等宽 `@handle · 模型`，屏幕与关闭两个图标按钮。详情 / 记忆 / 资料库改用与侧栏相同的 `Segmented` 滑块；各区块改为白色卡片，原生信息卡、记忆编辑器、操作进度卡、空状态统一 14–16px 圆角；SOUL / MEMORY / USER 文档切换为胶囊，选中为墨色。
- Skills / 插件页标题 28px 粗体，说明 13px；卡片悬停改为上浮 2px + 阴影（不再变 accent 描边），名称加粗、说明 13px 三行截断；插件详情和导入弹窗改用面板圆角与三级阴影；资料库文件卡同步圆角和悬停。
- 移除侧栏旧导航遗留的 `.app-navigation` 样式；屏幕面板的离线条样式限定在面板内，不再覆盖详情面板。
- 证据 `docs/evidence/ui-u7-details-*.png`、`ui-u7-memory-1440.png`、`ui-u7-skills-*.png`、`ui-u7-plugin-detail-1440.png`。lint、typecheck、24 项单测、build 与 4 条 Edge 旅程通过；旧阶段截图已还原。

### UI 改版收尾

- U0–U7 全部完成：画板导出、基础层、首页侧栏与命令面板、消息流、屏幕面板、新建编辑面板、添加电脑、设置登录、详情与扩展中心。原 U4 的群聊部分并入 U3，屏幕面板在 GPT 完成功能后按画板 06/07 补做视觉。
- 未覆盖：真实 Linux 屏幕下的接管态视觉（演示环境只能显示连接中状态）、Windows/Android 原生壳内的实机观感，需在对应设备上复核。

## 2026-10-29 / Side Stage 2 公网联调增量

- 用户补齐域名、Firebase 文件及发送所需 IAM 权限。正式 HTTPS/WSS、HTTP→HTTPS、App CORS 与 Firebase API 均实测通过；其他服务和既有站点保持运行。
- Windows x64 release 与 Android x86_64 模拟器从内嵌页面直接登录产品服务并完成真实模型回复。真实任务的完成通知经 Node→Relay→FCM 到达 Android 后台，实际点击后回到对应会话。
- Windows release NSIS 与 Android arm64 签名 release APK 0.1.0 已发布到产品下载入口。Windows 未做 Authenticode 签名，Android arm64 未在手机安装；不将它们标为完整平台验收。
- 修正 Android 15 状态栏覆盖标题的原生安全区问题，实际截图确认；当前模拟器使用硬件输入浮动工具栏，完整软键盘仍待验收。
- 起始全仓 lint、typecheck 与 12 文件 / 24 项测试通过；收尾全仓 lint 被并行新增的未跟踪 `apps/site/main.js` 的 49 项浏览器全局/空代码块错误阻断，本轮不修改该网站。未重新跑过完整 Edge 或独立检出。仍需真机权限/锁屏/划掉、双端完整审批/steer/停止/文件/屏幕与恢复、Windows 安装和休眠旅程，详见 `side-stage-2-acceptance.md`。

## 2026-10-29 / 官网

- `apps/site` 为纯静态页面（`index.html`、`styles.css`、`main.js`、`assets/`），无构建步骤，可部署到任意静态托管；本地预览 `python -m http.server 4390 --directory apps/site`。
- 内容：首屏标题与产品窗口（群聊截图、浮动审批卡、交接胶囊、手机叠放）、接入方式条、四个理由、现场演示、五组功能（私聊工具、群聊接力、原生记忆、实时画面与接管、Skills）、九格能力、浏览器/App → Relay → Node → Hermes 原理图、三步开始与命令复制、路线图、页尾。
- 演示窗口按真实界面复刻两个剧本：私聊（思考 → 搜索/读取工具 → 审批“允许一次” → 终端 → 流式回答）与群聊（主答起草并 @ 交接 → 接力 1/6→2/6 → 浏览器核对）。进入视口后自动播放、两个剧本交替，可点选和重播，切换语言时重新开始。
- 交互：滚动渐入、导航高亮当前段落、首屏窗口随滚动回正、浮动猫轻微起伏；减少动态效果时全部静态。中文写在 HTML，英文字典在 `main.js`，按浏览器语言选择并记住；主题同理，切换时同步替换截图与 theme-color。
- 截图由 `.runtime` 演示环境（假 Hermes 与演示 bot/群组，仅开发脚本）中的真实网页界面以 2x 截取后转 WebP；记忆页为演示 SOUL，不含真实账号或数据。字体（OFL）与图标随站点自带。
- eslint 为 `apps/site/**/*.js` 声明浏览器全局与 script 模式；三处 localStorage 读写合并为一个辅助函数，存储被禁用时偏好只在本次访问有效、页面不受影响。上一条记录中被官网阻断的全仓 lint 现已通过。
- 验收：本地 http 下以 Edge 检查 1440/768/390、浅色/深色、英文，无横向溢出、无控制台错误；私聊剧本结束后状态条隐藏，群聊剧本的交接胶囊与接力进度正确。全仓 lint 与 prettier 通过。
- 未覆盖：未部署到公网；GitHub 链接沿用 README 的 `AR307/nekodot-app`；尚未选择开源许可证，页尾如实说明。

## 2026-10-29 / 0.1.0 官网部署与开源准备

- 正式官网已通过产品 Relay 发布，默认首页为 Claude 设计的双语站点；下载入口、中英说明与 MIT 许可证已补齐。
- Edge 的 390/768/1440px、中英、浅深色与 reduced-motion 共 12 组通过；脚本和图片无错误，布局无横向溢出。证据为 release-0.1.0-site-* 及 JSON。
- 全仓 lint/typecheck/test/build 通过，12 文件 24 项测试、4 条 Edge 旅程通过；真实 Linux 屏幕测试明确 skip。公网 HTTPS/WSS 登录、节点在线、snapshot 与真实模型回复再次通过。
- GitHub 原 Hermes 分支已保留为 hermes-reference；用户确认此次改为公开仓库。发布包和最终上传状态将在下一个模块记录。

## 2026-10-29 / 0.1.0 发布验收

- 最新 Windows x64 安装器与 Android arm64 签名 APK 均构建成功，MIT 元数据与标准 LICENSE 入库。官网 Edge 实际下载双端安装包成功；Windows 无发布者签名，Android v2 签名与单 arm64 ABI 已确认。
- 独立源代码导出通过 frozen install、lint、typecheck、12 文件 24 项测试、build、4 条 Edge 旅程；真实 Linux 屏幕回归因缺少此轮私有现场跳过，不冒充真实屏幕验收。
- 官网 12 组 Edge 布局、真实公网模型回复、产品节点在线和既有 API 均正常。其他产品容器没有被重启；旧安装包另存，数据与 profiles 保留。
- GitHub AR307/nekodot 已公开，默认 main 为 nekodot 产品，原 Hermes 代码保留为 hermes-reference。官网、下载、MIT、功能和当前平台待验收范围均在 README / release notes 中列出。
- 机器记录为 docs/evidence/release-0.1.0-{site,packages,downloads,verification}.json；Android 真机与 Windows 完整安装等既有未验收项目继续保留，不因 0.1.0 发布改写为通过。

- GitHub Actions 对官网 / MIT 发布准备提交的 lint/test/build 工作流实际完成且结果为 success；最终发布记录提交将另触发同一工作流。

## 2026-10-29 / README 发布徽章

- 修正 GitHub README 中状态徽章缺图：原 Shields 源返回 200/SVG，但 Edge 的 GitHub 页面中图片未显示。改为版本化、随仓库提供的 release v0.1.0 SVG；发布后在实际 GitHub 页面复核。

## 2026-10-30 / 0.1.1 配对等待与真实 Linux 安装修复

- 新配对码有效期延长至 30 分钟；新增经账号认证的原码延长接口及「延长 30 分钟」按钮。未使用的过期码也能恢复，不改变正在执行的安装命令；其他账号及已消费的码不能延长。
- 绑定页可以返回无节点首页并继续绑定。修正无节点 selector 每次新建对象引发的 React 循环渲染，以及切换语言重新启动账号引导的问题。
- 用户安装日志定位到系统 pip 镜像缺少上传时间元数据，导致 Hermes PM 的 release-age 检查无法解析 setuptools / psutil。安装器及项目专属 launcher 显式使用官方 PyPI，沿用 Hermes 原生安装与检查，不修改全局配置或 Hermes 核心。
- 独立 Ubuntu 用户中故意设置不可用的 PIP_INDEX_URL，真实官方 Hermes 安装、配对、systemd 服务及上线通过。随后使用公网安装器重复安装，节点身份保持不变且服务恢复；现场和原始日志私有保留。
- lint、typecheck、13 文件 25 项测试、build 通过；4 条 Edge 旅程通过，真实屏幕因缺少本轮现场明确跳过。配对页在 390 / 768 / 1440px 实测延长、原命令保留、返回及重新进入，并保留截图。
- Relay 已通过独立候选实例校验后仅更新产品容器，其他三个服务的身份、启动时间与重启次数不变。本机 Docker Desktop 无法启动，因此将本地预构建 Relay 注入既有生产依赖镜像，在服务器组装新镜像；没有远程源码构建或新增依赖。
- 双端修复版本为 0.1.1，Android versionCode 2 且沿用原签名；Windows 安装器未做 Authenticode 签名。官网和 GitHub 的发布结果另记；旧包、历史和 profiles 保留。
- 证据：docs/evidence/pairing-fix-{live,deployment,packages}.json 及 pairing-fix-{390,768,1440}.png。Android 真机、Windows 干净用户完整安装和真实屏幕等既有未验收范围继续保留。

### 0.1.1 下载交付

- 官网已替换为 0.1.1 双端包，Edge 实际点击并下载两个包成功。Android manifest 已核对应用标识、versionName 0.1.1、versionCode 2、arm64 ABI 与 v2 签名；旧包在服务器另存保留。
- 本次只做本地源码提交，不自动推送或创建 GitHub Release。README 的最新下载链接直达官网，原 v0.1.0 GitHub Release 保持不变。原生真机 / 干净用户安装未重新验收；本轮 UI 结果来自真实 Edge 旅程。

## 2026-10-30 / 节点安装后的真实上线确认

- SSH 实测确认用户节点安装后约 48 秒才完成 Hermes 启动并连接 Relay，现有 Windows 客户端随后显示「已同步」。原安装器在后台进程刚启动时就提示成功，造成启动期离线误判。
- 安装器改用 systemd Type=notify；Node 收到真实 hello.ok 后才通知就绪，安装命令随后显示已上线。隔离 Hermes 子进程的 NOTIFY_SOCKET，避免子进程抢先宣告父服务已准备。
- 补充启动期提示、连接错误和关闭原因日志；Hermes 初始化失败时结束受管子进程。启动失败显示日志并保留已安装程序、节点身份和历史。
- 独立 Linux 用户真实重复安装与配置错误预检通过，身份保持不变；恢复配置后重新上线。26 项测试、typecheck、lint、build 及 Edge 私聊完整旅程通过。验收记录见 docs/node-install-readiness.md 和 docs/evidence/node-ready-install.json。
- 公网只更新安装器及 Node 单文件；没有重启用户节点、产品 Relay 或其他服务，没有更新双端客户端包，也没有修改 Hermes 核心。源码只做本地提交，不推送。

## 2026-10-30 / Side Phase 3 原生提问与输出恢复

- 原生 clarify 普通选项不再被审批枚举拒绝；问题、审批分别保存，恢复依据实际 pending_controls。回答、刷新和 Node 重建保持同 run，不把回答转成普通发送。
- 隔离 WSL 的真实模型提问 Amber / Teal，回答 Amber 后同 run 实际完成；已保存脱敏 fixture。Edge 完整私聊验证刷新、重建、草稿、回答及后续审批/steer/停止；新增问题截图单独留存。
- 本轮 typecheck、15 文件 27 项测试、Flutter analyze 通过；完整 Edge 4 passed / 1 skipped，跳过项为需要真实 Linux 屏幕的既有测试。原生 Flutter 构建和设备旅程尚不能标记完成，外部 SMTP 等待用户准备，不部署未验收账号变更。
- 实施记录见 docs/side-phase-3-progress.md；所有修改仅本地，不 push、不重启线上服务。

## 2026-10-30 / Side Phase 3 邮箱验证与会话基础

- 实现 6 位验证码注册、旧账号补验、密码重置/修改、30 天可撤销会话与服务端退出。Web 保持验证码、重置和退出可操作，4401 清登录态而非无限重连。
- 真实 loopback SMTP/HTTP/WS 验证错误/重发/重放、旧 userId 保留、重置后旧 token 失效、退出关闭屏幕 viewer 和 node，旧票据不能使用；两个账号的既有节点/文件/屏幕隔离测试继续通过。
- 最新 15 文件 / 27 项测试通过。实际外部邮箱和生产可信代理仍待验收，没有部署 SMTP 缺失版本。报告见 docs/side-phase-3-accounts.md。

## 2026-10-30 / Side Phase 3 外部 SMTP 收码

- 使用真实邮件服务和用户实际收取的验证码，在独立 Relay 完成注册、密码登录、重复验证码拒绝、退出后原 token 401；没有从数据库提取验证码。
- SMTP 域名验证问题已由用户修正，TLS 保持开启。脱敏证据 `docs/evidence/side-phase3-smtp.json`，凭据和邮箱不提交。
- 线上服务未更新；外部密码重置/旧账号补验和生产可信代理继续待验收，不把本项等同整个账号模块安全检查完成。

## 2026-10-30 / Side Phase 3 Flutter 原生基础

- 新增共用 Flutter Windows / Android 工程与原生 RFB 屏幕；不使用 WebView，不运行本地 Hermes。HTTPS/WSS、系统安全存储、snapshot/since/offset、进程内草稿及导航继续复用服务端。
- Windows x64 与沿用既有签名的 Android arm64 release 构建通过；独立 Android 模拟器真实登录、流式回复、完整屏幕、只读/接管/交还和返回导航通过。实际远端表单文件核对 NEKODOT_NATIVE_INPUT_OK。
- 修复 Rust TLS/native-assets feature 缓存与 RFB 有界通道积压造成的局部白屏。Flutter analyze 与账号表单 widget 测试通过，真实旅程和截图见 docs/side-phase-3-native.md。
- 本项仅为基础闭环，不代表全部页面、Windows 安装或 Android 真机/后台推送验收。新提供方等后端仍待完成；不替换 Tauri、部署、上传候选包或 push。

## 2026-10-30 / Side Phase 3 通知预览与归属修复

- 通知改为真实 Bot/群组名称和最终回复纯文本预览；保留群聊整链一次及停止不提醒，新增等待回答提醒。Relay 根据 UTF-8 载荷截断，不持久保存或记录正文。
- 两个认证账号实测复现设备绑定可被其他账号覆盖，修复返回 409；2 文件 / 2 项 HTTP/WS 与业务数据测试、typecheck 通过。详见 docs/side-phase-3-notifications.md。
- Flutter 原生权限/显示/点击代码已接入，但 Google 服务不足的模拟器不能替代真机推送；真实 FCM 与 Windows toast 完整验收尚未完成，不发布或部署。

## 2026-10-30 / Side Phase 3 扩展说明与原生返回

- 原生实际 SKILL.md / README、仓库、图标和文件列表已接入；简介直接展示，完整内容左推 / 返回保留筛选。修正显示标题误作稳定标识、插件正文误走技能接口的问题。
- 隔离 WSL Hermes 管理接口及产品适配器实际核对通过，脱敏录制进入测试依赖。Edge 一项完整扩展旅程通过，覆盖 390 / 768 / 1440px；独立 Android 模拟器通过真实 RPC 完成阅读、完整页、详情 / 列表返回与关闭连接。
- 修复设备旅程复现的 setState Future 回调与已释放客户端回调；Flutter Windows 目录导入入口和 Web 80ms 搜索反馈已实现。原生文件选择 / 安装、真机及完整视觉仍待验收。
- 详见 docs/side-phase-3-extensions.md；截图为实际运行画面，管理回放与真实 Hermes 结果分别标明。未切换线上产品、未分发测试 APK、不 push。

## 2026-10-30 / Side Phase 3 Bot 原生欢迎

- 创建 Bot 后由对应 Hermes profile 在原私聊 session 生成介绍和任务询问，不伪造用户气泡；刷新、重连与 Node 恢复不重复启动。失败显示原因，Web / Flutter 提供显式重试，仍使用既有 run、SSE、停止与 steer。
- 隔离 WSL 的真实自定义模型完成一次欢迎回合；实际创建数为 1、用户消息数为 0、恢复及同步后新增执行数为 0。录制与脱敏报告见 `docs/side-phase-3-welcome.md`。
- Node 24 lint/typecheck、17 文件 / 29 项测试与 build 通过；完整 Edge 4 通过 / 1 跳过，跳过项需本轮真实 Linux 屏幕现场。Flutter analyze、2 项 widget 测试及专用 Android 模拟器介绍 / 重连 / 失败重试旅程通过，截图已核对。
- Android 创建表单仍须等多来源后端接入后验收；没有将本轮 RPC 创建等同于表单通过。Windows 完整旅程、Android 真机与后台通知继续待验收。未部署线上、未分发候选包、未 push；保留其他未提交截图与既有数据。

## 2026-10-30 / Side Phase 3 Hermes 多来源与模型信息

- 新增 Providers 模块，直接管理 Hermes 原生授权目录、自定义来源及 profile 模型路由；移除单一全节点提供方及 OpenRouter 专用产品路径。Web / Flutter 设置不再选模型，Bot 表单选择来源与模型；Key 留在节点，OAuth grant 由 Hermes 原生继承刷新。
- 持久隔离 WSL 的真实验证通过：两自定义来源回复、OpenAI Codex 用户设备授权与真实回复、共存以及 Node/Hermes 重启后继续回复；没有复制 grant 或修改 Hermes 核心。原生上下文、最大输出与压缩结果如实展示，未知不猜测、不实现额外压缩。
- Edge 来源与建 Bot 旅程、390/768/1440px 截图及 Android 专用模拟器原生表单/欢迎/重连通过。收尾 Node 24 lint/typecheck、18 文件 / 30 项测试、build 通过，完整 Edge 5 通过 / 1 真实 Linux 屏幕跳过；Flutter analyze、2 项测试及双端 release 构建通过。
- 详见 docs/side-phase-3-providers.md。本轮只是模块收尾，不是 0.2.0 发布；全新检出、Windows 安装、Android 真机及共享用户记忆等仍待验收。仅本地提交，不部署、不分发、不 push；其余历史截图与私有现场保留。

## 2026-10-30 / Side Phase 3 同账号共享用户记忆

- Relay 保存账号 USER 文档、修订、已确认原件和冲突记录；Node 通过已有认证出站连接同步实际 profile 文件。按原生条目合并独立修改，同条目冲突明确显示，不静默覆盖；普通 Bot 文档保存不再直接写 USER。
- 真实 WSL 中原生 memory 工具写入，另一节点 Bot 独立会话正确读取；原生文件写入的监听传播、其他账号隔离、Node 重启不重跑及 SOUL / MEMORY 保持独立均通过。
- Node 24 lint/typecheck、19 文件 / 31 项测试和 build 通过；完整 Edge 6 通过 / 1 跳过，另复跑共享记忆与扩展 2 项通过。390/768/1440px、中英、浅深色与 reduced-motion 留图。Flutter analyze、既有 2 项测试及双端 release 构建通过，原生旅程单独记录。
- 报告为 docs/side-phase-3-user-memory.md，真实模型的脱敏记录为 docs/evidence/side-phase3-user-memory-native.json。自动化回放与真实调用分开记录；未部署、分发或 push。
- 专用 Android 模拟器的原生共享编辑/保存、另一节点读取、返回、刷新及重连草稿保持已通过；官方 driver 续接同一测试进程取回结果和截图，初始连接失败如实记录。真机仍待验收。

## 2026-10-30 / Side Phase 3 原生产品旅程与安装候选

- 补齐双端 Flutter 私聊、群聊、审批、提问、同 run steer、停止、失败恢复和文件旅程；修复审批设置误覆盖、发送中草稿清空、重连选项丢失及 Windows 列表 Material 断言。真实 Node/Relay 加 Hermes 录制回放通过，不冒充新模型验收。
- 新增 Windows 每用户 NSIS 安装器与 app-local runtime；隔离目录覆盖安装、单实例和托盘恢复实测，旧 Tauri 保留。Android 候选沿用产品签名并按官方 ABI 分包，Flutter 0.2.0+4 的 arm64 APK versionCode 为 2004。候选包仅保留本地，未部署、发布或 push。
- 独立源码 frozen install、Node 24 lint/typecheck、19 文件 / 31 项测试及 build 通过；完整 Edge 最终 6 通过 / 1 真实 Linux 屏幕跳过。Flutter analyze、4 项 widget 场景和原生旅程结果与未覆盖范围见 docs/side-phase-3-native-product.md。真机通知、外部邮件重置/补验、扩展导入与干净用户安装仍未完成。

## 2026-10-30 / Flutter 客户端界面重构

用户反馈 GPT 版猫形象和界面不好看，要求砍掉多余按钮与说明，先试透明黑白毛玻璃；看过后要求电脑版改纯黑白、布局参考 Grok Bot，手机版保留毛玻璃第一版。

- 样式：`apps/native/lib/ui/design.dart` 的 `Tone` 有 flat 和 glass 两组，`appTheme` 默认按平台选择（Android 为 glass，其余 flat）；`lib/ui/parts.dart` 的 `Panel`、`AppPage`、`RoundButton` 等共用组件随 `Tone.glass` 变化，少数页面（首页、聊天、Bot 详情、扩展）有两种布局分支。
- Windows：隐藏系统标题栏，`WindowChrome` 绘制窗口按钮并为页面头部留位，`WindowDrag` 让头部空白处可拖动。宽度 ≥1000 时 Bot 详情显示为右侧面板，较窄时推入页面；Skills / 插件合为一个弹窗，窄窗为页面。设置和退出账号移到左下角账户菜单，添加电脑移到电脑下拉菜单。
- Android：底部悬浮栏与第一版一致，设置页保留退出账号。内容在磨砂顶栏和输入框下滚动；毛玻璃只用在有内容经过的表面。
- 文案：去掉登录标语、添加电脑说明、模型容量与压缩的解释段、记忆说明、聊天空状态提示等；未知数值显示为 —。限制和前提若仍需告知，靠控件状态或错误信息表达；添加电脑保留 `Linux x64 · WSL2`。
- 猫头像由 SVG 改为 `CustomPainter`，工作时耳朵轻摆；减少动态效果时静止。应用图标、托盘图标与 Android 启动画面同步重绘。Nunito 和 JetBrains Mono 以静态 TTF 随包（OFL），未改 Hermes、协议或客户端数据层。
- 调试构建不再占用单实例互斥量，便于与已安装的客户端并存；Release 行为不变。新增 `integration_test/ui_tour_test.dart`，走查主要页面并输出截图，用于设计复核，依赖开发用的演示环境。
- 真实旅程：`product_journey_test` 对真实 Node / Relay 与录制的 Hermes 事件，在 Windows 和 API 35 x64 Android 模拟器上都通过（私聊、审批、提问、steer、停止、失败恢复、文件、群聊接力）。这是回放，不是真实模型验收。其余旅程只同步了被改动的文案和入口，本轮未重跑：`providers`、`user_memory`、`extensions`、`welcome`、`live`。Flutter analyze 与 4 项 widget 测试通过。
- 过程发现：手动 `connect()` 后 `ready` 不复位，握手完成前发出的 RPC 可能因断开报错。这是连接层已有问题，不在本轮范围，旅程测试里加了等待来避开，未修改 `client.dart`。
- 未覆盖：Android 真机与性能（毛玻璃在低端机的帧率）、Windows 安装包实际观感、真实屏幕接管画面。Web、Tauri 与官网未改，官网截图仍是旧界面。未构建发布包，未部署，未 push。
- 证据：`docs/evidence/native-ui-desk-*.png`（Windows 走查）、`native-ui-android-chat-*.png`（模拟器实拍）与 `native-ui-android-home-light.png`、`native-ui-android-settings-dark.png`（手机尺寸走查）。

## 2026-10-31 / 重连竞争、运行动画与头像形象

- 竞争：`NekodotClient.connect()` 原先不复位 `ready`，手动重连后 RPC 可能赶在 `hello.ok` 之前发出，连接被断开后报“连接断开”；旧连接上未完成的请求还要等满 30 秒。现在 `connect()` 开始时复位 `ready` 并让旧请求立即失败。`test/client_reconnect_test.dart` 用本地 WebSocket 服务复现，修复前失败、修复后通过；旅程测试里的临时等待已去掉。代价：应用恢复前台触发重连时，会短暂显示离线。
- 运行动画：Flutter 的 `CatAvatar` 按网页版参数恢复耳朵摆动（±8°，0.6 秒交替）、眼睛扫动（3 单位，1.6 秒交替）、空闲每 4–7 秒眨眼、列表悬停抖耳；幽灵上下浮动，花瓣慢转。聊天在 Bot 思考或工具运行且没有流式内容时显示工作中的头像和跳动圆点（`ThinkingRow`）。减少动态效果时全部静止。
- 性能修复：`main.dart` 每次客户端通知都新建 `ThemeData`，主题里有闭包导致比较不相等，会重启 200ms 主题动画；上一轮引入，现改为只构建一次。
- 头像：协议 `avatarSchema.shape` 由 `dot` 扩展为 `dot/bear/bunny/puppy/mochi/flower/ghost/antenna`；颜色调色板统一为 16 种，已有 Bot 的旧颜色继续有效。Flutter 和 Web 都能显示、选择和保留形象，Web 编辑时不再重置形象；Flutter 新建 Bot 默认随机形象和颜色，Web 默认猫。浅色头像用深色眼睛保证对比度。
- 兼容：旧版 Node 的协议只接受 `dot`，新形象需要 Node 升级后才能保存。部署时先升级 Node，再分发客户端。
- 验证：Flutter analyze 与 8 项 widget 测试、全仓 vitest 32 项、typecheck、eslint、prettier 通过；`product_journey_test` 在 Windows 与 Android 模拟器通过（回放 Hermes，去掉等待后不再复现竞争）。Edge 实测网页版：选择幽灵形象、保存，节点接受，侧栏和消息同步更新。
- 未覆盖：Edge E2E 未重跑，它会改写 `docs/evidence` 里其他人未提交的截图；Android 真机上的动画帧率未测；未打包、未部署、未 push。
- 证据：`docs/evidence/native-ui-avatars.png`、`native-ui-android-editor-light.png`、`native-ui-desk-light-editor.png`、`web-ui-avatar-editor.png`。

## 2026-10-31 / Flutter 客户端密度调整

- 用户反馈按钮太高太胖、AI 味重。对照 impeccable 的 craft-floor、mode-operate、layout 与 android 规则调整；只读其文档，未安装其钩子和检测器。
- 尺寸：`Tone` 增加 `control`、`corner`、`icon`（电脑 32 / 8 / 18，手机 40 / 10 / 22），手机保留 48 dp 触控区。按钮改小圆角并按内容宽度靠右或靠左，只有登录按钮全宽。输入框电脑约 34、手机约 42 高。正文电脑 14、手机 15，行标题 500/600，页面标题 700。转场缩短到 200ms。
- 结构：标签移到框外（`LabeledField`）；图标统一为线性或无圆头版本；`IconAction` 取代带边框和阴影的圆形按钮；工具调用在电脑版改为无底色单行；输入框两端合用一套；侧栏 248、详情面板 320。提示条抬到手机底部栏和输入框上方，原先会盖住“+”。
- 测试：`providers_journey` 的两个字段标签在上一轮改文案后已过期，本轮修正。
- 验证（真实 Node / Relay，Hermes 为回放）：最终代码上 Windows `product_journey`、Android `providers_journey` 通过；Android `product_journey` 在最后两处小改（转场时长、提示条位置）之前通过。Flutter analyze 与 8 项 widget 测试通过，Android 模拟器实拍已核对。
- 未覆盖：用户要求尽快收尾，电脑版输入框高度的修复没有重新截图，只跑了功能流程；`extensions`、`welcome`、`user_memory`、`live` 旅程未跑；`providers_journey` 的截图步骤不支持 Windows；真机未测。未打包、未部署、未 push。
- 证据：`docs/evidence/native-ui-density-android-light.png`、`native-ui-density-android-dark.png`。
