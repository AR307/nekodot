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
