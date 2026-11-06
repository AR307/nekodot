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

## 2026-10-31 / 全量回归与提示条

- 提示条改为 `showNotice`：水平居中，宽度跟随文字（最宽 420），高度约 34，不再通栏；短提示 2 秒消失，长提示和错误 4 秒。位置在手机底部栏和输入框上方。电脑版输入框提示字按中文字形做了光学对齐。
- 全部旅程在最终代码上重跑。Windows 与 API 35 x64 Android 模拟器：`product`、`providers`、`extensions`、`welcome`、`user_memory` 全部通过（真实 Node / Relay，Hermes 回放）。Flutter analyze 与 9 项 widget 测试通过。
- Edge E2E：6 通过，1 跳过（`screens-live` 需真实 Linux 屏幕）。之前提到的 `private-chat.spec.ts` 按位置点色块未受影响。运行前快照了 `docs/evidence`，结束后按字节恢复，他人未提交的截图保持原样。该项运行后只改了 Flutter，Web 代码未变。
- 测试修正：多处假设“手机推页面”的返回逻辑改为兼容电脑版侧边面板；启动占位页带上主题；截图步骤只在 Android 执行；等待转场、提示条和懒加载列表，避免慢速模拟器上的时序失败。修过程中发现并修复一个真实问题：提示条曾盖住手机底部的“+”。
- 未覆盖：`live_journey`（配置指向生产环境 nekodot.com，会调用真实模型并接管屏幕，未经确认不跑）、`screens-live`、真机通知与性能。未打包、未部署、未 push。
- 证据：`docs/evidence/native-ui-notice-*.png`、`native-ui-density-desk-*.png`。

## 2026-10-31 / Node 更新 1：协议与发布工具

- 增加时间戳版本、签名清单和 node.update 通知；hello 保持已有宽松版本字段。发布工具只读取发布者提供的 Ed25519 私钥，生产私钥不生成、不入库。
- 普通分发构建把旧清单移入私有回收目录，避免新 bundle 配旧清单；不删除文件。隔离测试实际执行盖章脚本，验证签名及缺少密钥/占位符时拒绝。该模块尚未接产品自更新链路。

## 2026-10-31 / Node 更新 2：Relay 发布通知

- Relay 每次 Node/客户端 hello 后从磁盘重新读取发布清单，仅向时间戳旧版本发送 node.update；1.0.0 旧 Node 不收未知消息，/api/me 返回一次手动更新命令。替换同一节点连接时保留新 socket 的版本。
- HTTP/WS 场景通过：旧版本保持在线、同版本不通知、更换 downloads 后客户端连接触发更新、缺失/非法清单返回 404；typecheck 通过。未部署生产。

## 2026-10-31 / Node 更新 3：空闲切换

- 安装版 Node 校验签名、版本、32 MB 下载上限、内容摘要及 CommonJS 语法；下载后等待私聊、欢迎、群聊接力及管理操作空闲，再保存上一版、写入待确认标记并切换，以 75 退出交给服务重启。失败保留当前服务，冷却 10 分钟。
- hello.ok 回收启动标记；标记只移入 bin/recycle，不删除。开发版或非安装路径不更新。Node 24 typecheck、更新器及连接 2 项场景测试通过；真实安装与 systemd 升级/回滚仍待后续验收。
- Node 24 对 `.cjs.next` 直接执行 `--check` 会按未知扩展名拒绝，实测后改为通过 stdin 使用 `--check --input-type=commonjs`，仅检查、不执行下载代码。测试通过真实 HTTP 下载与测试 Ed25519 密钥检查拒绝篡改、忙碌等待、等待中发布变化以及切换标记。

## 2026-10-31 / Node 更新 4：安装器与回滚

- 手动安装先完成下载再原子替换；旧启动标记移入私有回收目录。生成的 launcher 在新版本首次启动留下 tried，未获 hello.ok 又重启时恢复 previous 并记录 rejected，保留身份、历史及 Hermes 资料。
- 补齐签名发布、私钥备份、Relay/Node 先于客户端、固定 runtime 和数据库可回滚的部署说明。WSL bash 语法检查通过；完整真实安装与服务回滚尚待隔离验收，不部署生产。

## 2026-10-31 / Node 更新 5：双端手动更新提示

- Flutter 与 Web 仅为当前在线的旧 Node 显示简短命令和复制按钮，保留现有双端改版布局。握手及节点恢复在线后刷新 /me，完成一次手动升级后提示自动消失；不替用户执行命令、不新增更新状态。
- Flutter analyze、11 项测试与专用 Edge 复制/替换连接旅程通过。隔离 WSL 已用真实旧提交 bundle、官方 Hermes PM 和下载的安装脚本启动独立用户服务；完整自动升级和实际客户端截图继续验收中，尚未发布。

## 2026-10-31 / Node 更新 6：真实服务旅程

- 独立 WSL 用户实际安装、旧提交 bundle 保持连接、手动升级、真实工具忙碌等待、签名崩溃回滚、跳过拒绝版本及篡改拒绝均通过；更高有效版本可继续更新并保存非 dot 头像。Node 身份、profile 和真实回复历史保留。
- Windows Flutter 与 Edge 已实测复制命令、同客户端恢复后提示消失并留图；补充可复用原生集成旅程。修正实际发现的安装器相邻管理端口遗漏检查。新增无效语法、大小上限和冷却场景通过，Flutter analyze 无问题。独立检出整仓回归继续进行，结果与边界见 docs/node-auto-update-acceptance.md。

## 2026-10-31 / Node 更新收尾

- 独立源码 frozen install、lint、typecheck、23 文件 / 36 项测试及 build 全部通过；完整 Edge 7 通过 / 1 既有真实屏幕专项跳过。全部回归截图写在独立检出，不覆盖主工作区他人图片。
- 真实 Edge 表单在更新后保存 ghost 头像、收到模型欢迎并刷新保留；补齐脱敏服务日志、工具次数和截图证据。实现与本地验收完成；未生成生产私钥、未部署、未 push。现有 Hermes 核心、旧 UI 改动及其他验收范围保持原样。
- 具体边界：复用 Hermes 官方源码/下载缓存后由 PM 准备独立环境，不声称无缓存首次安装；Windows 本次为实际 Debug 集成测试窗口，未构建新发布安装器；Android 真机、屏幕、生产切换及原 Side Phase 3 遗留项未在本次标记完成。发布需要发布者提供及备份生产 Ed25519 私钥，并按部署文档先 Relay/Node、后客户端。

## 2026-10-31 / 官网与 README 更新

- 设计依据：只读 impeccable 仓库的 Persuade、craft-floor 与 new-work 文档，没有运行它的下载器和 concept-seed；用户已指定配色，因此沿用客户端的视觉，不走随机方向流程。
- `apps/site` 重写：去掉小标题、卡片格、分节淡入和路线图；头像几何对齐 `design.dart`；首屏下载按 UA 把 Android 访客的 Android 按钮放到第一位；屏幕接管没有新版实拍，继续用标明「示意图」的画面。
- 截图：`ui_tour_test` 在 Windows 上对 `.runtime/ui-stage.ts` 实拍，导出到 `apps/site/assets/shots/`。手机截图是 Windows 上按手机尺寸渲染的毛玻璃界面，不是 Android 设备实拍。演示节点补了版本号、中文欢迎语和更长的对话，这些改动只在 `.runtime`。
- 验收：Edge 1440 / 768 / 390、浅深色、中英文、减少动态效果均无横向溢出和控制台错误；实际点击语言与主题切换、头像选择、三个回放场景、功能窗口滚动、导航和 Android 下载顺序通过。`eslint apps/site` 和 Prettier 通过。下载链接只核对了地址，本地静态服务没有安装包。
- 未做：未部署、未 push。线上 `/downloads` 仍是 0.1.1，部署新官网前要先上传 0.2.0 安装包，否则页面和下载内容不一致。`desk-report-*.webp` 已不再使用，按约定保留，未删除。

## 2026-10-31 / 0.2.0 发布构建与候选验收

- 本轮统一根版本与部署镜像为 0.2.0，Flutter 为 0.2.0+5；Windows release/NSIS 和 Android arm64 signed release 通过，实际 versionCode 2005，Android 签名证书与旧包一致。Node 生产发布号 20261031080359，生产私钥未入库或上传。
- 本地 Docker 构建的镜像脱离源码运行，发布清单及 argon2 可用；补齐 `.dockerignore` 的清单声明。服务器候选使用生产 SQLite 的独立副本，不修改正式账号；SMTP TLS/认证、旧密码进入补验、新登录/WS 和退出撤销通过。
- 工作区 frozen install、lint、typecheck、23 文件 / 36 测试、build、Flutter analyze 和 11 项测试通过。Edge 390/768/1440、中英、浅深色/reduced-motion 的 12 组官网图片、布局及交互通过。
- README、官网与发布说明明确为开发者预览版。生产切换、公网旅程和 GitHub 发布继续进行；Android 真机、后台通知及干净 Windows 用户等未验项目仍保留，详见 `release-0.2.0-acceptance.md`。

## 2026-10-31 / 0.2.0 线上部署与官网缓存修复

- 本地构建的 Relay 镜像、生产签名 Node、Flutter Windows / Android 包与官网已部署，原账号、节点、profiles、历史及浏览器资料保留。首次安装被项目 PM 输入目录旧属主阻断，保存现场后仅修正输入子树属主，重跑官方流程上线；其他三个产品容器身份、启动时间和重启次数不变。
- 独立源码 frozen install、lint、typecheck、test、build 通过，Edge 7 通过 / 1 真实屏幕专项跳过。公网 HTTPS/WSS 真实回复 `NEKODOT_020_RELEASE_OK`、流式文本与重复消息去重通过；只使用短期内部 QA 会话且已撤销，未冒称重新完成邮箱登录。官网下载两包及 Node 发布号已核对。
- 用户截图与实际 Edge 标签确认 CDN/浏览器旧缓存导致新 HTML 使用旧 CSS、JS、截图。统一为资源增加 `?v=0.2.0`，包含主题切换的动态截图；只发布三个站点文件，保留旧文件，不重建或重启服务。用户原标签普通刷新后白底、猫 logo、8 个头像及新 Flutter 主图均正确。
- `www` 曾出现 TLS 错误，已追加规范域名重定向并 reload Caddy，四种入口最终均到 HTTPS 官网。没有重启共享服务器或其他应用。
- 新增脱敏公网模型、下载与实际缓存修复截图证据；GitHub 发布后补最终版本信息。Android 真机/后台 FCM、Windows 干净用户与完整原生视觉矩阵继续待验。

## 2026-10-31 / 0.2.0 公开交付

- 产品 main 已正常 fast-forward 推送，保留 Hermes 参考分支与原 v0.1.0；v0.2.0 使用开发者预览版标识。GitHub 双端资产已上传并核对大小，与官网的 Flutter 0.2.0 包一致。
- 官网、仓库主页、README 与 Release 链接统一，继续 MIT。Windows 未做发布者签名、Android 原签名及既有真机验收边界均保留说明。
- 本轮没有提交私有配置、签名密钥、原始日志或他人未提交的历史截图，没有重启其他产品或整机。
- GitHub 两个公开资产完整下载成功，v0.2.0 标签 CI 通过。同源码另一轮群聊测试先看见等待区、后收到配对码，原测试立即读取造成空匹配；对齐既有私聊测试，等待配对码文本再提取。隔离 Edge 群聊完整旅程 1 项通过，eslint 通过。main 补此测试修正，发布标签与二进制不改动。

## 2026-10-31 / 0.2.0 正式发布

- 用户确认改为正式版；现有 GitHub v0.2.0 已取消 prerelease 并设为 Latest，名称为 `nekodot 0.2.0`。核对 Release ID、两份安装包的资产 ID 与大小保持原样，保留既有 tag。
- 官网中英文、README、Release 正文及当前验收说明统一为正式版；为更新后的 `main.js` 使用 `?v=0.2.0-release`，保留此前的截图和样式缓存修复。旧站点文件另存，服务没有重启。
- Edge 原标签普通刷新确认中文「0.2.0 正式版」、英文「0.2.0 release」和下载入口；GitHub latest API 返回 v0.2.0。eslint 与针对性格式检查通过。本次只调整发布标识及文案，既有未验收事项不改结论。
- 证据：`docs/evidence/release-0.2.0-official.json`、`release-0.2.0-official-site.json` 及同名官网截图。

## 2026-10-31 / 执行中断后无法继续聊天：本地修复

- 已确认源码缺陷：Node 将 Hermes 原生 `unknown` 当作失败终态，而原生会话仍等待确认；后续任务可能继续被 `unknown_execution` 拒绝。依据为 Hermes 的 `api_server_authority_runs.run_projection/resolve_unknown_run`，不是对用户 VPS 日志的推断结论。
- Node 保留中断的 run 和输出，停止按钮直接使用原生 `/v1/runs/{run_id}/resolve-unknown`，携带原生返回的 admission/generation。确认请求失败时不结束回合、不丢群聊队列，成功后取消本次接力。不调用新会话、不改写 Hermes 数据库、不重新执行原任务。
- Web / Flutter 展示“执行中断，待确认”，保留草稿；确认前禁用发送，仍可点击停止。中断的 Bot 不再播放工作动效。窄屏提示换行，停止按钮可见。
- 验证：Node 24 lint/typecheck 和全部 24 文件 / 38 测试通过；Node/Web 构建通过；Flutter analyze 与 12 项测试通过。私聊和群聊用例覆盖重启、确认失败后重试、保留输出、清队列及同 profile 的后续新任务。
- Edge 实际运行隔离的 Relay → Node → 原生状态契约/已录制 Hermes SSE，验证 390/1440px、草稿保留、一次确认、一次后续新 run；截图为 `unknown-execution-390.png`、`unknown-execution-1440.png`、`unknown-execution-recovered.png`。这些是 Web 回放界面证据，不能替代 Android 真机或用户故障 VPS 的验收。
- 部署状态：仅本地提交，不 push、不替换已发布资产。现有产品环境未找到此次故障会话；用户仅确认使用 VPS，尚待提供准确 SSH 地址或 App 节点名称。实际故障日志、原生未确认及排队执行仍待该节点核对，未执行任何会话恢复或服务器变更。

## 2026-11-01 / 实际故障 VPS 已恢复

- 用户补充准确 SSH 目标后，只读核对实际节点。一个原生 admission 在旧 owner epoch 中断后仍为 unknown，四个后续 admission 为 queued；Node 将本地记录提前置 idle。实际状态返回 `execution_generation: null`，造成第二条 unsupported event 错误，已在现场确认。
- 保留 SQLite 现场副本、私有原始日志及旧 Node 程序。使用原生 `/stop` 取消四个 queued run，之后对唯一 unknown run 调用 `/resolve-unknown`，结果为 terminal/interrupted；没有直接修改 Hermes 数据库，没有重放更新任务，待执行数量归零。
- 协议接受原生尚未取得执行代次时的 null；Node 遇到失败 SSE 时以原生 queued 状态为准，保留回合和停止入口。新增真实契约场景覆盖 unknown_execution SSE、null generation、停止队列及不自动重跑。同步修正 spike 对空代次的检查。
- 本地 25 文件 / 39 测试、typecheck、针对性 eslint/Prettier 通过。独立构建并部署受影响 Node 版本 `20261031155700`，复用既有发布方式，不替换公开下载资产。只重启本项目 Node 及其托管的 Hermes 后端；Relay、其他项目和整机未重启。
- 真实验收：同 Bot、同原生 session 在恢复后及服务重启后均完成真实模型请求，回复匹配 `NEKODOT_RECOVERY_OK`，没有执行工具。使用修复后的 HermesApi 读取实际终态 SSE，8 个事件正常解析，末事件为 run.completed；此前排队的取消状态及 null generation 也正常解析。
- 最终服务 active、Relay 已连接、原生待执行数 0；Bot、会话和聊天记录数量与恢复前一致。仍保留旧失败气泡，不自动重发之前的消息。Android 真机没有在本次操作中直接控制；本次证据为实际节点服务、真实模型和真实 API/SSE，不冒充手机端手动验收。
- 脱敏结果：`docs/evidence/hermes-execution-recovery.json`。原始备份、凭据、SSH 目标与私有日志均不入 Git；代码仅本地提交，不 push。

## 2026-11-01 / Bug 修复：登录窗口

- 原因：隐藏系统标题栏后，AuthPage 没有提供 WindowDrag，表单滚动层占满窗口。现将顶部 44px 原生拖动区放在其上，保留语言与窗口控制按钮的命中区域。
- auth_window_test 实际分发 Flutter 手势，确认调用 window_manager 的 startDragging，邮箱仍可输入，语言按钮不与窗口控件重叠；专项测试通过。
- 隔离 Windows 窗口已验证双击最大化与还原；Computer Use 的拖动未取得坐标变化证据，真实位移仍需人工复核。不把代码测试替代为完整实窗移动验收。未发布或 push，不动用户现有进程、其他 UI 改动及截图。

## 2026-11-01 / 原生聊天输入能力

- 增加 commands.list/execute，目录及分发来自 profile 绑定的 Hermes 管理接口；群聊可选择成员。实际节点核对目录及 `/profile`、`/plan` 响应，测试使用脱敏录制。终端和原生会话切换类命令明确不可用，不另造会话或打断机制。
- `@everyone` 原位展开当前群成员并去重，保持原六回合上限；Flutter 与 Web 均补选择项。
- 复用 imports 分块转发实现 Flutter 文件/图片发送，附件可单独发送并在历史预览，中文文件名正确。Node 保存副本并向目标 profile 提供原生文件路径/图片输入；用户附件不进入 Bot 发件资料库。运行中附件明确提示原生 steer 仅支持文字，失败不清草稿。
- 已复现并修正发送附件后提前离开会话造成已发送附件留在草稿的问题；专项用例先失败，修复后通过。新的编辑内容不被旧发送确认清除。
- 实际 Windows Flutter 旅程完成 `/profile`、经真实 Relay/Node 上传并发送 txt/PNG、打开预览、建群、选择所有成员并收到两名成员回复；Hermes 回复使用实际录制，不冒称真实模型。系统文件选择器另以 Computer Use 选中中文文件。新截图使用 composer-native 前缀，没有覆盖既有用户截图。
- 真实模型另在实际节点隔离原生 session 中完成中文 UTF-8 文档精确标记读取，以及红色方块/蓝色圆形的颜色、形状和左右识别；使用候选 FileLibrary 原生输入，无旧任务重放。结果见 `docs/evidence/composer-real-files.json`，原始资料留在私有现场。
- lint/typecheck、服务端 27 文件/41 测试、Flutter analyze/14 测试、Node/Relay/Web 构建、Windows release 和 Android arm64 signed release 通过。Android APK v2 签名有效。Edge 七个非屏幕旅程中首批 6 通过、提供方超时，其独立复测 14.7 秒通过；未隐藏首批失败，未为该偶发超时改产品逻辑。
- Android 真机的新入口、实际 Windows 鼠标位移及真实 Linux 屏幕本轮未完成；构建和回放不能替代这些结论。候选未部署、未发布、不 push，完整范围见 `docs/composer-update-acceptance.md`。

## 2026-11-01 / 屏幕内存占用：实际节点只读调查

- 实际机器 1967MiB RAM，可用约 380–452MiB；1987MiB swap 已使用约 1501MiB。原生依赖齐全、屏幕未运行，display.status blocker 指向 bot_desktop.min_free_memory_mb 的 1536MiB 要求，不是 Relay 路由或 UI 超时。
- systemd 项目 cgroup 当前约 500MiB、记录峰值约 792MiB；smaps_rollup PSS 分别约为 Node 9MiB、gateway 253MiB、serve 228MiB。节点还有其他服务和独立 Hermes 安装，未擅自停止或修改。
- 核对官方源码：gateway 已有管理 HTTP/WS，但通过原生私有控制连接签发单次票据，不是现有 API_SERVER_KEY 的替代 URL。没有为省一个后端增加 Python 桥、复制管理接口或修改 Hermes 核心；此路线尚未完成整套管理/屏幕回归，不作为已上线优化。
- 即便完整省下当前 serve 的 228MiB PSS，仍不足以解决本机可用内存缺口。降低分辨率只影响较小帧缓冲，swap 也不等于物理可用内存；没有任意降低原生门槛或关闭浏览器沙箱。
- 建议屏幕放到更空闲的节点或独占约 4GB 以上实例，并核对启动前约 1.5GB 可用。这是本机容量建议，不是对所有共享 VPS 的保证。本轮只完成定位和精简路径研究，未完成小内存节点屏幕成功启动。
- 报告见 `docs/screen-memory-investigation.md`。私有日志保留，不提交 SSH 目标、凭据和个人路径；不重启整机、其他产品或当前项目服务，不部署、不 push。

## 2026-11-01 / 用户查看候选与真实验收原则

- 直接启动本地完整 Windows release 目录中的原生客户端；Computer Use 观察到窗口、已登录的真实账号及其 VPS/Bot 列表。构建默认 Relay 为产品 HTTPS，未使用 fake-hermes、回放账号或演示进程。
- 用户明确要求此后以真实客户端/Hermes/模型验收为准，必要的真实模型调用无需考虑费用。已写入项目开发约定；单元测试与回放仍用于辅助定位，不能替代真实产品验收。
- 没有自动发送用户任务、改写安全存储或生产部署。客户端展示成功不等于新 RPC 已在远端上线；完整新功能闭环仍须匹配服务端版本后逐项记录实际结果。

## 2026-11-01 / Side Phase 4：原生任务、Relay 与凭据

- 实现动态 webhook/既有 cron 关联、CLI+skill 插件、私有 socket、加密凭据、保密卡及结果 outbox。账号检查沿用 Relay 节点归属；公网只转发到已登记任务。
- Node 从 Relay 握手取得公网地址，同机 loopback 连接不会生成不可访问 URL；原生接收回执与完成结果分开展示/保存。
- 实际跨 profile admission 的上游错误已先复现，获用户授权后以最小 listener-home 修复单独提交，未修改产品 Hermes。隔离 canonical 13 测试和官方13检查通过，公网同请求从503恢复为202及真实模型完成。
- 真实 Windows 候选闭环、外部401、暂停403、旧钥401、跨账号forbidden、原生ignored/duplicate通过；真实 Agent 创建一个 cron 并成功由关联 webhook 执行。实际定时、helper、恢复、Android及构建仍在验收，不以辅助测试替代。
- 服务端 lint/typecheck、29文件44测试及构建通过；现场和临时QA路由有明确保留/撤回边界。详见 `docs/side-phase4-routines-acceptance.md`，未发布、未 push。

## 2026-11-01 / Side Phase 4：原生 admission 结果采集

- 实际无效模型的 webhook 已接收202，但初始化失败不会触发旧 session hook。以此真实问题替换旧采集路径：插件只读目标 profile 的原生 admission/结果，Node 按 session 收录。没有增加调度、执行、重试或核心修改；旧现场文件原地保留。
- 原失败 session 在 Node 重启后补回 failed，并产生对应私聊消息；未重跑原事件。Bot 归档后入口403。实际组合任务的 direct/builtin 两种触发均完成，验收后仅暂停QA定时部分。
- 真实 Agent 经文件工具创建脚本、终端执行 `hermes routine send`，通过凭据引用调用公网并完成模型回复，没有向模型或脚本交付明文密钥。
- 关闭顺序调整为先收集后关闭 Hermes 管理后端；启动会更新已有项目 profiles 的插件。当前 lint/typecheck、29文件44测试、Flutter analyze/15测试通过；最终双端与恢复继续验收。

## 2026-11-01 / Side Phase 4：Flutter 页面与双端候选

- 原定时任务区域改为例行任务，复用原生Flutter导航，增加详情、编辑、保密复制/交付、Webhook启停、轮换、JSON测试、接收回执和执行记录。任务与保密聊天卡仅保存标识；结果入口定位原生session。
- Windows候选和Android模拟器均完成真实聊天建任务→卡片→复制→授权→公网202→模型完成→暂停403→旧钥401→返回聊天。Android实测暴露的加载时null转换已修复；使用产品Ambient背景重新验收，不使用叠层的早期截图。Android真机与通知未宣称通过。
- 真实Agent创建并执行helper脚本；前台终端等待期间触发独立webhook，前台runId保持一致且继续完成；追问读取已有后台结果，不增执行。阶段截图为真实原生App，不是浏览器手机尺寸或录制回放。
- 既有指令栏、其他UI和历史截图改动保持原状，不纳入本模块提交。最终工程、服务恢复与独立检出继续记录；不发布或push。

### Side Phase 4 — 例行任务页面实拍修正

- 在 Android 真正运行的候选 App 中复现长记录覆盖透明顶栏；仅给新任务详情、设置页面固定滚动边界，保留其他页面的 UI 改动。
- 双端真实旅程增加页面视口断言；最终安装包和截图将使用这一修正后的提交重新构建和验收。

### Side Phase 4 — 复制操作验收修正

- 不再以固定 pump 时间猜测复制完成：等待 URL/密钥的实际完成提示，再比对目标任务和剪贴板内容；只输出布尔结论，不在失败日志展开密钥。
- 因错误剪贴板产生的 401 轮次不记为暂停验证通过；最终双端串行复测，继续保持暂停必须 403、轮换后旧钥必须 401 的真实断言。

## 2026-11-01 / Side Phase 4：最终真实验收和本地候选

- 独立检出基线 `866ee2de56` 的 Windows 原生旅程1分33秒、Android模拟器旅程3分34秒均通过；使用真实模型和公网入口，覆盖创建、保密交付、复制、结果、暂停403、轮换旧钥401及返回。Android详情/执行实拍已更新，未混作真机验收。
- 同一原生cron的定时与事件执行、真实helper脚本、私聊工具运行期间的后台任务、后续追问、原生拒绝、失败、离线503及独立服务重启恢复均有实际证据。权限拒绝核对原生execute_code工具记录；没有新增执行/重试引擎。
- 最终检查7个实际文件、21个当前凭据无明文命中；脱敏汇总不含密钥、endpoint及原始私有日志。
- 全新检出frozen install、lint/typecheck、29文件44服务端测试、服务构建、Flutter frozen pub get/analyze/14测试通过。Edge最终7通过1跳过，跳过项为未配置的旧真实屏幕旅程；此前超时、bad port、复制未完成和构建失败均保留记录。
- Windows EXE与Android arm64 APK构建通过；APK官方签名校验通过，EXE未做Authenticode签名；沿用0.2.0+5，仅本地候选，不发布或push。
- 公网QA路由已撤回，Caddy校验并reload，官网/产品health200、原QA hook404，其他容器启动时间不变。仅隔离Hermes使用最小修复，产品服务和原数据未替换，隔离现场全部保留。
- Android真机、真实通知/FCM及新页面完整视觉矩阵仍待完成；后续部署须单独安排。报告见 `docs/side-phase4-routines-acceptance.md`，证据见 `docs/evidence/side-phase4-routines-real.json`。

## 2026-11-01 / Side Phase 5：canonical gateway transport 基础

- Node 新增按 profile 缓存的 Hermes gateway-v1 连接。使用官方 `gateway ensure --json` 发现本机 loopback endpoint，通过 Hermes 私有控制 socket 申请短期单次票据，未暴露给 App。
- 连接器接收最早的 `gateway.ready` 首帧，支持 JSON-RPC 调用、gateway event、服务端反向请求应答与断线清理。自动化本地 WebSocket 旅程检查三种帧，覆盖真实可见的传输契约。
- 验证：Node TypeScript 全量 typecheck、目标 ESLint、gateway/runtime 3 项测试通过。测试为协议辅助验证，不等同真实 Hermes 服务验收。
- 未完成：现有 Node 聊天仍使用 Runs API；会话身份/历史、工具事件、原生审批与提问、steer/stop 尚未迁移，旧聊天控制接口尚未移除；未在真实候选客户端、远程 Node/Relay 和真实模型上验收。本条只记录基础层，不代表 Phase 5 完成。

## 2026-11-01 / Side Phase 5：canonical 会话与命令路径

- Node 私聊与群聊执行迁移到 Hermes `hermes-gateway-v1`：profile-scoped canonical session、持久 stored session ID、prompt admission、事件恢复、原生历史/提示、审批/提问、steer、停止与 unknown admission 查询均走 Gateway。群聊仍按 nekodot 路由，但各 Bot 的回合与私聊共用其 Hermes profile session。
- `commands.catalog` 显式指定 profile；`slash.exec`、`command.dispatch`、`/refine` 和记忆审核改为对应 profile 的 Gateway session，self-improvement 监听 `review.summary`。Session 创建/恢复及 SQLite 映射收敛到 `apps/node/src/hermes/session.ts`。
- 产品 runtime 不再暴露 Runs API 客户端入口。Hermes 原生 API server 仍用于官方 profile 管理、文件/工具能力；健康检查改为直接探测 loopback health，不再构造旧聊天客户端。
- 验证：Node 24 全仓 typecheck 通过；Vitest 30 文件 / 45 场景通过；本模块 ESLint、Prettier 和 Node 构建通过。独立 WSL Ubuntu 24.04 使用实际 Hermes 与真实模型，通过欢迎消息和 `/profile` Gateway 命令；真实 session 恢复及 snapshot/since 后消息数稳定，模型 run 仅 1 次，结果摘要保存在忽略目录 `.runtime/side-phase-5/canonical-session-welcome.json`。
- 曾有一次真实旅程脚本因把新增系统命令消息排除在恢复前基线外而误报重复；修正基线后完整复测通过。Windows/Android 候选客户端和远程 Node/Relay 的匹配版本真实验收尚未完成；回放与本地 WSL 结果不代表完整 Phase 5 通过。

### 2026-11-02 / Side Phase 5：Hermes profile 设置

- Bot 详情新增设置页，按 Hermes schema 动态展示分类、说明、当前值和选项；支持布尔、数字、文本、select、JSON list/object 编辑。保存只调用官方 profile 配置 API，不另建设置数据库；模型与上下文长度只读展示，继续由 Bot 模型设置管理。
- Node 对 Bot/profile 做存在检查，按 schema 校验字段和类型；敏感键只返回 configured 状态，通用设置不回显或覆盖凭据。设置 RPC 不增加 Relay/客户端专用传输通道。
- 自动化验证：Node 24 typecheck；31 个 Vitest 文件 / 46 项通过；Node bundle build；目标 ESLint/Prettier；Flutter analyze、全部 Flutter tests 和新增 390px 设置场景通过；Windows Flutter debug build 成功。真实 WSL Hermes 版本为 v0.22.5。
- 真实接口边界：Hermes schema/API 来源已核对，但隔离服务启动被 PM 环境缺少 `ruamel.yaml` 阻断，无法完成真实 profile 写入/读回；未通过 fixture 冒充真实服务验收。匹配版本的真实 Windows/Android 客户端、Node/Relay 与真实模型旅程待后续继续。
- 全仓 `pnpm lint` 的 ESLint 阶段被 `opus-video/nekodot-hello` 的 16 个已有浏览器全局/变量错误阻断；本模块目标 ESLint 通过。未部署、未发布、未 push。

### 2026-11-02 / 官网：极早期开发版本提醒

- `apps/site` 下载说明中英文改为极早期开发版本、可能会有很多 Bug；`main.js` 资源版本改为 `0.2.0-early`。
- ESLint 与 Prettier 忽略社媒视频工程 `opus-video`，解除它对全仓 lint 的阻断。
- 验证：本地 HTTP 服务配合 Edge 在 1440 与 390 宽度核对中英文文案，无页面错误、无横向滚动；全仓 ESLint 和目标 Prettier 通过。未部署线上官网，未 push。README 和 GitHub Release 仍写正式版。

### 2026-11-02 / 真实验收准备：回收旧产物、固定模拟器

- 用户已明确同意所列回收范围；旧 Tauri target、Flutter build、两份旧 node_modules、重复 SDK/ZIP 和 `NekodotSideStage2` 已移入私有回收目录，未永久删除。pnpm junction 跨盘中断的剩余部分改为同盘保留，并记录恢复位置；未动当前候选、源码、profiles、历史、凭据和证据。
- 实测 D 盘可用空间约由 15GB 增至 36GB；C 盘约 31GB。空间数字仅为本次整理时读数。
- 新增 `native:emulator` 入口及开发约定，固定复用 `NekodotNativePhase3`；实际返回 `emulator-5554`、boot completed=1。`PiMobileQA` 属其他项目，保持不动；没有新建或清空 AVD。
- 使用已有项目 Flutter SDK 和官方 Hermes PM 入口；隔离 Ubuntu 24.04 的 v0.22.5 已启动，真实 Node/Relay 已上线。设置及聊天的双端真实旅程另行记录，不把环境准备算作功能验收通过。

### 2026-11-02 / Side Phase 5：设置模块双端真实验收

- 本次 Flutter Windows 与固定 `NekodotNativePhase3` Android 模拟器均连接真实持久化 Node/Relay、干净官方 Hermes v0.22.5 和实际 gpt-6.1-sol，完成详情进入、908 字段读取、搜索、模型只读提示、压缩开关、select 保存/取消/显式清空、第二 profile 不变及真实流式聊天；最终旅程分别约22秒、26秒。
- 设置取消 bug 有真实红/绿结果：修复前选清空再取消使 Hermes 读回 null；修复后取消保留 node24，仅明确保存才清空。Android 第四个设置标签被默认留白挤出的实拍问题也已修复并通过原生点击验证。
- 原生连接重建、snapshot/历史读取后消息标识不重复；真实重启隔离 Hermes 后设置和历史不变，canonical `/profile` 完成；隔离 Node/Relay 进程停止再启动后设置及12条消息标识保留，未再次配对或新建 Bot。
- Node 24 typecheck、31文件46测试、全仓ESLint/Prettier及Node bundle通过；首次在Android冷构建期间并行测试有1项超时，后续单worker全量通过，没有放宽超时。canonical gateway两个文件只作格式修正。Flutter analyze与16项Flutter tests通过，后者为辅助检查，不替代实际模型旅程。
- 预置已验证QA账号不算SMTP或注册UI验收；候选包含保留的其他UI工作区改动，不冒称全新检出的release包。真机、推送、完整视觉矩阵、生产VPS匹配版本及其余Side Phase 5能力仍待验收。
- 报告及真实截图：`docs/side-phase5-settings-acceptance.md`；脱敏结果：`docs/evidence/side-phase5-settings-real.json`。未改Hermes核心、未部署生产、未发布或push。

### 2026-11-02 / Side Phase 5：命令薄适配与手测候选

- 手测 `/history` 报错已定位到目录与 canonical slash 支持不等价；改用原生 `session.history`，接入工具、子 Agent/进程和技能重载等明确 RPC，以及已有设置/模型/插件 App 页面；保留官方别名和动态扩展命令。
- 分清“App 适配 / 原生可执行 / 服务器终端 / 待接入”，不可用命令折叠展示；会话切换、分支、撤回等有用能力仍待后续适配，不再误标为可执行。原生拒绝 detail 不丢失，不用 shell、Runs 或任意 URL 代理补功能。
- Windows 与固定 Android API35 x64 模拟器完成真实原生 UI + Node/Relay + 官方 Hermes v0.22.5 + gpt-6.1-sol 旅程，验证流式回复后 `/history` 能查到同一结果且不新增模型/用户回合；`/tools`、`/tasks`、`/v`、`/reload-skills`、`/config` 和重连无重放通过，最终旅程约32/35秒。
- Node typecheck、lint、32文件48测试及bundle、Flutter analyze与17项测试通过；初次真实自动化的输入焦点步骤问题已修正并重新完整运行。目录分类152条不等于152条命令全部实测。
- 清理仅移动此前授权的三个旧安装包；没有永久删除或清空 AVD。匹配版本的 Windows/Android 私有手测候选另行拉起，生产、发布和push均未执行。报告：`docs/side-phase5-command-acceptance.md`；结果：`docs/evidence/side-phase5-commands-real.json`。
- 真机、生产匹配版本、完整视觉矩阵、运行中子 Agent 控制及未列出的命令适配继续保留为待验收。

### 2026-11-02 / Side Phase 5：原生命令扩展，模块一（Node）

- 接入 canonical 会话操作、后台问答与子 Agent/进程控制，以及固定官方管理 API 的工具配置、日志、备份、profile archive 和 Git worktree；学习历程、宠物、订阅仍以 Hermes 为准，未新增 Agent 引擎。
- Windows 真实模型旅程完成后台问答不污染主上下文、工具启停、新会话、worktree 创建/切换、备份下载、导出后经 App 导入新 Bot并保留记忆/真实欢迎。固定 Android 模拟器也完成主机/导入旅程；完整双端复测在下一模块继续。
- 运行中真实验证子 Agent tail/steer/interrupt、暂停/恢复派生、真实后台进程 kill、私聊 slash steer 与独立 Stop、真实模型压缩。发现并修正后台完成帧被错配到下一次用户 admission，复测原场景通过；不是用录制结果替代模型。
- 目录 152 条，其中 App 适配 52、原生 97、终端设置 2、未支持 1；另完成 55 个调用场景，调用成功不冒充所有参数/外部集成都通过。当前尚未完成的真机、语音采集、队列入队/排序等边界见实现文档。
- 新增与真实问题对应的事件归属、原生参数、profile 配置写入和会话 receipt 辅助测试。未改生产、未删除数据或新建 AVD；本模块本地 commit、不 push。

### 2026-11-02 / Side Phase 5：原生命令扩展，模块二（Flutter）

- 补齐原生会话选择/历史、学习条目编辑、宠物与订阅页面、profile archive 导入；本机图片/剪贴板、显示偏好、电量和退出不再套用服务器终端行为。附件草稿不会因执行 slash 被清空。
- 双端真实候选旅程完成会话切换/分支/撤回/重试、原生后台问答、工具启停、新 worktree、实际备份下载、导出后导入与真实欢迎；运行控制旅程真实调用子 Agent、进程、steer/Stop 及模型压缩。
- Android 长于一分钟的真实旅程发现电量刷新 setState 返回 Future，已修正并复跑；实拍修正用户时间戳低对比度与新页面顶栏重叠。`/help` 和指令栏显示 App 真正接受的参数，移除 CLI-only 用法误导。
- 当前 152 条目录分类为 App 53、原生/动态 96、终端 2、canonical 不支持 1；55 个真实命令调用结果只证明对应调用，不代表全部参数及外部账号均验收。App 麦克风、队列写入/排序、缺图像服务的孵化和无账号订阅仍明确保留。
- 固定复用原 Android 模拟器，未新建或 wipe；未改生产、未发布或 push。最终工程与系统保存/退出实测继续记录。

### 2026-11-02 / Side Phase 5：队列、语音入口与原生后台结果

- 原生 FIFO 队列接通入队/list/rm/edit/steer，保留输入卡的实际状态，取消/编辑/steer 不生成虚假回复。真实复现 pending.steering 被当成独立 started 回合，修正后双端真实审批/重连/队列旅程通过。
- 增加本机 PCM16 麦克风、原生 wake/feed 与转录入口，离开页面或后台停止采音，转录可编辑后明确发送。双端仅通过原生依赖提示；QA Hermes 未配置 STT 且缺 numpy，不宣称音频唤醒或转录成功。
- 只读观察 Hermes 原生自动回合 admission/review.summary，复用已有消费/恢复和消息通路；Windows 真实 loop 结果已进入聊天。/refine 与详情页共用原生操作，等待真实完成；无参数状态插件 JSON 解析修正，双端调用通过。
- 官方 v0.22.5 local heartbeat 真实保存却不执行，源码确认原生 local adapter 分支提前返回。产品保留查询/暂停/停止，创建/恢复明确提示不可用；未修改核心或增加调度引擎。
- Windows 实际系统保存 JSON/Markdown/HTML（中文文件名）及双端 /quit 后服务器任务继续完成已核对。新增 /init /learn /review /refine 完整旅程未通过；后续模型返回余额不足403，已请求用户恢复，不以 fake/回放替代。
- 当前 typecheck、35文件57服务端测试、Flutter analyze通过；最终独立检出检查和构建另记。未删除数据、未改生产、未发布或push。

### 2026-11-02 / Side Phase 5：MoA 原生单回合与扩展命令复测

- 余额恢复后实际完成 Windows 的 /init、/learn、/review、/refine，读回真实技能并核对另一 profile 未安装；Windows 与固定 Android 模拟器的 goal/subgoal/loop 及48条状态命令已通过。Android 学习完整旅程继续验收，不以启动回执计通过。
- 新增真实 MoA/blueprint/cron 旅程，发现 slash MoA 虽应答却只执行普通模型。改为官方 canonical prompt.submit.model_override，随原生 admission 保存；群聊只作用于所选成员的本回合，不改变后续接力或普通模型。忙碌时明确拒绝此单回合命令，避免被当成 steer。
- Windows 修复后已核对原生参考输出、实际 token 用量与汇总输出；普通后续回合恢复正常模型。实际蓝图建任务及 cron 创建/修改/启停/立即执行完成，读取原生执行会话确认真实回复；测试任务暂停并保留。
- 当前 typecheck和35文件59项辅助测试通过。最终独立检出检查、Android MoA及学习复测和脱敏矩阵另行记录；未改 Hermes 核心、生产服务，未删除数据、发布或push。

### 2026-11-02 / Side Phase 5：命令逐项真实验收收尾

- 补充余额后，Windows 与固定 Android 模拟器均完成真实 /init、/learn、/review、/refine、goal/subgoal/loop、MoA、blueprint 和 cron 旅程；读回实际学习文件、原生执行记录与模型输出，不再以先前额度不足作为当前阻塞。MoA 原生 trace 确认参考和汇总都实际执行，使用同一已配置模型，不宣称多供应商验收。
- 双端逐项操作状态/目录命令、本地诊断、权限开关和四级输出切换；恢复开关与输出设置，原生历史未增加模型回合。Windows 54个动态技能均实际加载并由真实模型确认，未据此标记外部完整工作流通过。
- 当前目录152条：55 App适配、94原生/动态、2纯终端、1 canonical不支持。逐项结果及参数见 `docs/side-phase5-command-matrix.md`，真实证据与限制见 `docs/side-phase5-command-acceptance.md`；原生 heartbeat、缺STT语音、外部账号和Android真机仍明确保留。
- 产品快照 `4e503403bf` 的独立检出通过 frozen install、lint、typecheck、35文件59项服务端测试、build、Flutter frozen pub/analyze/18项测试和双端release构建；本次追加旅程脚本后 Flutter analyze 再通过。Windows安装器未做Authenticode签名，Android沿用既有签名。未改生产、删除数据、发布或push。

### 2026-11-02 / Side Phase 5：用户确认结项

- 用户在知悉已通过的核心真实旅程、已列明限制与待验边界后，明确确认本阶段“已验证完成”；Side Phase 5 据此结项。
- 原生 heartbeat / handoff 限制、语音闭环、Android 真机/推送/完整视觉矩阵与缺配置外部工作流继续保留为后续事项，不改记为通过、不再阻塞本阶段。详细范围见 `side-phase5-command-acceptance.md`。
- 本次只更新结项文档，不修改产品代码、服务或用户数据；本地提交，不发布或 push。

### 2026-11-02 / Bot 历史会话与 GUI 切换

- 顶栏与详情页直接进入会话列表，支持搜索、预览、新建和切换，不再要求用户手输 /sessions、/new 或 /resume；保留当前 Bot 的原生 profile、记忆、技能及旧历史。
- 双端真实原生候选 + 真实持久化 Node/Relay + 官方 Hermes v0.22.5 + gpt-6.1-sol 完成新建与切换、原生 session_search 读历史、正确上下文回忆、预览不调用模型/不切换、草稿与重连、另一 Bot 不变及恢复原会话。最终 Windows/Android 旅程约61/75秒；Android 为固定模拟器，不冒充真机。
- 修正真实发现的预览返回刷新 Future/setState 异常，完整复测通过；Flutter analyze和18项辅助测试通过。主聊天日志仍保留，按会话的原生上下文通过预览查看；没有删除、迁移或重写历史。
- 实现与边界见 `bot-sessions-gui-acceptance.md`，脱敏结果及实际截图单独保留。未改 Hermes 核心或生产服务，不发布、不 push。

## 2026-11-03 · 0.3.0 正式发布准备

- 用户授权直接发布正式服，并确认 Android 验收已完成；不重复要求真机验收。
- 版本更新为 0.3.0+6，更新官网、README、安装包版本与产品 Relay 镜像标签；保留 Claude 的官网设计及早期产品风险说明。
- 包含原生 canonical 会话、能力/指令接入、Webhook 例行任务和 Bot 历史 Session GUI。
- 正式服务上线及构建结果另记 docs/release-0.3.0-acceptance.md；保留账号、节点身份、profiles、历史、现场和既有未提交改动。

## 2026-11-03 · 0.3.0 候选构建与发布前验证

- 独立检出完成服务端 frozen install/lint/typecheck/59 项测试/build，Flutter frozen pub/analyze/18 项测试及双端 release 打包。
- Android 保留首次 Kotlin 缓存失败记录，使用已验证的单次 Gradle 参数重试成功，未清理文件或重建 AVD。
- 候选 Relay、SMTP、分发与官网 12 组 Edge 检查通过；Windows release 原生页面已实际打开观察。
- 附上已有授权的最小 Hermes Webhook 补丁及自部署说明；不让安装器静默修改第三方节点的 Hermes 核心。
- 用户进一步明确授权同步发布 GitHub，已准备非 prerelease 的 0.3.0 Release 草稿与双端安装包，尚未公开。

## 2026-11-03 · 0.3.0 正式服上线

- 正式 Relay/Node 与官网、Windows EXE、同签名 Android APK 已切换；保留账号、Node 身份、profiles、历史、浏览器资料及完整回滚资料。
- 正式公网 gpt-6.1-sol 流式聊天与 Webhook 独立执行/回投通过，错误密钥 401、正确事件 202、重复 delivery 不重复执行；QA 入口已暂停、临时会话已退出。
- 其他产品与 Caddy 未重启；只更新 nekodot 产品服务。正式官网 12 组 Edge 和安装包公网下载通过。
- 用户要求不再追加检查、快速发布；不等待额外 Windows Session GUI 重跑，不据此宣称新一轮原生 GUI 验收完成。Android 验收记录为用户确认完成。
- 根据追加授权同步 GitHub 正式 v0.3.0，保留 MIT 及未做 Windows Authenticode 签名的说明。

### 0.3.0 公开发布完成

- GitHub main 与 v0.3.0 标签已推送，正式 Release 已公开（非草稿、非预览），双端安装包已上传；官网正式服和下载已生效。
- 按用户要求不再追加检查。先前启动的额外 Windows GUI 复验在 QA 账号邮箱补验处退出，未进入会话测试，不记为通过、不修改验证标记或继续重试；其余已完成真实结果见发布记录。

## 2026-11-03 · Node offline 现场修复

- 故障源为网络断流后的 WebSocket 握手无超时，连接卡住约 11 小时；重启现场节点恢复在线后，以 ws 原生 30 秒超时补齐重试触发。
- 使用真实 TCP 代理和 Relay 验证首次握手卡住、第二次认证成功、在线状态及 snapshot；Node 24 测试、TypeScript、限定文件 ESLint/Prettier 和 Linux 单文件检查通过。
- 已分发 Node `20261103022508` 并更新故障 VPS，保留旧 bundle、账号身份、profiles 与历史；无需新 APK，不重启 Relay 或其他产品。范围及证据见 docs/node-relay-handshake-fix.md。

## 2026-11-03 · Bot 创建与默认代号修复

- 根因为创建协议要求非空 handle，表单没有名称默认值。新建 handle 改为可省略，Node 从名称生成中文/英文代号，重名追加序号；手动代号与已有 Bot 的代号保留。
- Flutter 候选已实现名称自动填入，修正群聊中文 @路由，RPC 参数错误指向实际字段，不记录输入或密钥。
- 固定 NekodotNativePhase3 Android 模拟器 + 真实持久 Node/Relay + 官方 Hermes v0.22.5 + gpt-6.1-sol 完成创建、真实欢迎和指定 Bot 群聊回复；缺模型时保留表单并显示 params.model，补填后成功。Android 真机未在本次复验。
- 4 文件 11 项辅助测试通过（含真实 TCP/Relay 握手恢复），TypeScript、限定 ESLint 和 Flutter analyze 通过。早期测试驱动的定位/等待及模型固定文本断言失败保留在私有现场，不记作产品通过。
- 已发布 Node `20261103042820` 至现有分发入口，并在无活跃任务时更新故障 VPS；确认 active/running、NRestarts=0、online=true。保留身份、profiles、历史、备份和其他服务；未发布新 App 包、未 push。详情见 bot-default-handle-fix.md。

## 2026-11-03 · 保密交付模块 1–2：原生请求、插件、加密保存

- 实现 Bot 专属密钥、密文提交、精确用途匹配、原生技能请求/取消、CLI/skill 和 SecretSource；Node 只应用卡片中明确展示的目标。
- 配置交付与原生继续使用固定请求 / submission 标识；群聊卡片包含接收 Bot，值和可用凭据不会通过群聊上下文转交其他 Bot。
- 首轮辅助测试 3 文件 4 项通过，TypeScript 通过。真实隔离 Node/Relay、官方 Hermes v0.22.5 与 gpt-6.1-sol 已实际请求卡片；尚未完成双端交付及浏览器登录验收，不标记整个功能通过。

## 2026-11-03 · 保密交付模块 3：Flutter 卡片与管理

- 原生聊天内表单、Bot 专属元数据管理及 X25519/HKDF/AES-GCM 提交已接入；输入提交后、取消、路由离开与后台时清空，不进入持久草稿或离线队列。
- Windows 真实 API 配置与实际服务调用、Hermes 原生技能密钥请求通过；固定 NekodotNativePhase3 Android 模拟器真实提交多行私钥并继续任务，独立核对文件空格/换行完全一致。
- 当前隔离环境使用官方 Hermes v0.22.5 和真实 gpt-6.1-sol；服务端 36 文件 62 项辅助测试及 Flutter analyze 通过。原生网站登录、超时/取消、隔离与重启继续进行，Android 真机未验。

## 2026-11-03 · 保密交付模块 4：真实旅程与收尾

- Windows 和固定 NekodotNativePhase3 Android 模拟器、真实隔离 Node/Relay、官方 Hermes v0.22.5、gpt-6.1-sol 完成 API 配置与实际服务调用、双端临时 RSA 私钥真实签名验证及原样文件核对、原生技能密钥、原生取消/120秒超时、真实浏览器单次/保存登录和 OTP、精确用途复用、跨 Bot 与真实账号拒绝、双端重复提交及 Node 重启。真机和完整视觉/恢复组合仍保留待验，不用模拟器或单元测试代替。
- 真实发现并修正 vault identifier_type/站点聚焦、原生已交付与实际写入状态分离、管理替换不恢复聊天、跨端取消后的管理表单同步及 Android 长下拉项溢出；双端管理与实际 Android 后台输入清空复测。
- 修正前两模块记录：批量 SecretSource 已移出执行路径，不再把不同用途的保存资料注入 profile 全局环境；使用 Bot/profile 绑定引用与明确确认的目标配置。真实 native session、普通数据/记忆/日志扫描无专用测试值，已保存通用资料为密文，临时 vault 回收经实际 CLI 核对。
- 当前服务端 frozen install/ESLint/typecheck、36文件62项测试和 build 通过；Flutter frozen pub/analyze/18项辅助测试、Windows release 安装器及同签名 Android arm64 APK 已构建。全仓 lint 仍有3个既有文档 Prettier 问题，未冒充全绿或修改无关文件。
- 真实截图、机器结果和精确边界见 docs/confidential-delivery-acceptance.md。本轮未修改 Hermes 核心、生产服务、用户历史或无关 UI 现场，不发布、不 push；所有安装包为本地候选，Windows 未做 Authenticode 签名。

## 2026-11-03 代码复查：群聊真实论文旅程（模块一）

- 检查 Node 群聊路由、Bot 创建、canonical 会话、失败反馈及 Flutter 编辑/聊天入口。
- 修复：Bot 回复提及仍在队列的成员时重复排队，白白消耗 6 回合额度；仅对待执行队列去重，已经执行过的成员仍可再次接力。
- 修复：群聊原生回合启动前失败，没有保存该 Bot 的失败消息/原因；现在与私聊一样持久显示失败，并让剩余成员继续。
- 辅助回归覆盖 @everyone + 待执行成员提及，以及失效提供方来源的群聊继续。TypeScript 与 36 文件/63 项测试通过。
- 隔离 WSL 旧候选包启动报 YAML collection；从当前源码重建后恢复。当前源码未复现该异常，不把旧包问题计为新增源码修复。补充空 secrets 配置回归。
- 真实 Windows 候选正在创建 4 个 gpt-6.1-sol Bot，随后运行论文讨论；本模块不提前声称真实旅程完成。无生产部署、无 push、无文件删除。

## 2026-11-03 四 Bot 真实论文协作验收（模块二）

- Windows 原生候选通过实际编辑器创建论文统筹、文献侦察、方法设计、实验审稿，全部 gpt-6.1-sol，组名“大模型论文工作组 · 真实验收”。
- 实际模型 4 条欢迎 + 5 轮群聊完成；@everyone、待执行成员去重与已执行统筹再次接力均真实覆盖。Node 重启与客户端重开后保留相同消息，没有重复执行。
- 固定 Android 模拟器 NekodotNativePhase3 读回同组五条结果，真实界面检查通过；不等于 Android 真机或生产 VPS 验收。
- 产物：docs/research/rag-paper-concept.md、rag-group-discussion.md；完整环境、失败尝试、检查边界及截图见 docs/research-group-acceptance.md。文献原始页面已核对；论文实验与创新性仍待验证。
- TypeScript/ESLint/build、36 文件63项辅助测试、Flutter analyze/18项测试通过。全仓 Prettier 原有3个文件仍未过；不修改无关成果。只本地提交，无 push、生产部署或删除。

## 2026-11-03 Windows 托盘右键菜单

- 显式启用原生 rightClicked 菜单触发器，保留打开及退出入口；菜单和监听句柄随托盘保活，退出时释放。
- 实际原生菜单点击退出后候选进程结束，真实 Node/Relay snapshot 正常且研究数据保留。右击任务栏图标本体未自动化，原生配置/菜单/退出已验；详见 docs/research-tools-acceptance.md。
- 无生产部署、push、文件删除或其他服务重启。

## 2026-11-03 聊天 Markdown 与原生工具详情

- 统一聊天/会话历史的 GFM 渲染，修复真实中文粗体标点边界；表格支持水平滚动，保留代码和转义，不改写历史。
- 修复非 verbose canonical 工具 args/result 未显示；保留 secret scrub，显示真实退出码/错误并将失败工具标红。
- gpt-6.1-sol 实际执行成功及文件不存在两条工具命令，Windows/固定 Android 同步恢复、显示标题/中文粗体/表格/代码块通过，Android 横向拖动表格及展开工具通过。20项 Flutter 辅助测试、analyze 与服务端64项辅助测试通过。
- 本轮为隔离 debug 候选，无生产部署或发布。

## 2026-11-03 纠正自主工具验收并重新完成四 Bot 旅程

- 明确撤回上一轮预置论文链接的自主检索验收结论，旧资料保留。
- 全新四 Bot/profile（全部 gpt-6.1-sol），Windows 实际编辑器组队，未提供题目/论文/URL，自主搜索原始文献、写脚本、运行报错后修正，审稿及统筹独立复跑，共44次原生工具调用、5轮群聊完成。
- 固定 Android 模拟器恢复相同五轮，无新建实体或重发任务。7个论文原始入口另行核对；生成研究方案、源码和真实CSV，明确仅合成原型，不代表LLM研究效果或新颖性证明。
- docs/research-tools-acceptance.md、脱敏机器证据与双端截图已补齐；保留私有原始现场，无push、生产部署或删除。

## 2026-11-03 产品更新模块一：发布目录与 Relay 运维

- 新增产品发布清单、按版本下载、Relay 实际版本/构建号；沿用既有 Node 更新，不暴露账号级服务器重启接口。
- 发布脚本记录 APK 实际 versionCode，覆盖 Android split APK 的 ABI 偏移；完整产物准备后发布清单。
- 新增独立运维 update-relay.py：检查、下载镜像、仅替换 Relay、健康确认、保留数据和旧镜像。现有 Compose 可选择镜像，不触碰 Node 或其他服务。
- 真实隔离 Compose 在既有测试 VPS 完成 build 5 到 6 更新及真实 relay.db 保留；正式 Relay/Caddy/其他产品启动时间不变，验收容器已停止保留。
- 服务端 37 文件65项辅助测试、TypeScript、限定 ESLint 通过。操作说明：docs/product-updates.md。无 push 或正式发布。

## 2026-11-03 产品更新模块二：原生版本页面与安装入口

- Windows/Android 登录页及设置页增加版本与更新，读取系统实际版本，显示发布说明和实际 Relay/最新 Relay 版本。
- 流式下载完整安装包并显示进度，Windows 打开 NSIS 后退出客户端；Android 使用原生 FileProvider 与系统安装器，缺少安装权限时提供明确设置入口，不自动授权。
- Windows 和固定 Android 模拟器通过真实隔离 Relay 检查/下载旅程；Windows 已按用户授权打开安装器并退出候选，Android 安装权限页交由用户确认。完整覆盖安装与真机结果仍待验。
- Windows release 安装器、同签名 Android arm64 release APK 已构建；Flutter analyze、原有20项及新增1项辅助回归通过。细节和脱敏截图见 docs/product-updates.md。
- 本地候选仍用0.3.0 build6，正式发布前必须递增，不自动push、更新官网或正式服务。保留全部无关UI改动、profiles及测试现场。

- 后续用户手动确认 Android 权限并完成系统覆盖安装，实际 versionCode 从6变为7，重开到登录页；用户确认成功。Windows 被旧0.2.0客户端无法退出阻塞，另行修复。

## 2026-11-03 Windows 显式退出入口

- 旧已安装客户端缺少可用托盘退出入口，已仅停止核实路径的旧客户端，没有停止 Node/Relay 或服务器任务。
- 登录页、设置页增加 Windows 专属“退出应用”，复用 DesktopHost.quit，真正结束进程而非隐藏窗口；关闭按钮仍保留原托盘行为。
- 实际 release 候选中点击设置页退出，确认窗口及进程消失；登录/设置退出辅助回归与既有登录、版本回归共4项通过。
- 重建 Windows release 和 NSIS，已打开新安装器交由用户确认。完整 Windows 覆盖安装仍待确认，Android 用户确认的成功不受影响。
- 脱敏裁剪证据见 docs/evidence/product-updates-windows-quit-crop.png；没有 push、发布、服务端变更或文件删除。

# 本地电脑运行进度

计划与实现决定见 [local-desktop-plan.md](local-desktop-plan.md)。

| 模块                      | 状态                   | 验证                                                                |
| ------------------------- | ---------------------- | ------------------------------------------------------------------- |
| 1 Node 桌面托管           | 真实验收通过           | Windows 原生 Hermes v0.22.6：named pipe、gateway 停止、桌面托管启停 |
| 2 客户端本机运行模块      | 真实验收通过           | Windows：目录选择、官方阶段安装 6.3 分钟、Job 回收                  |
| 3 首次使用与生命周期界面  | 真实验收通过           | Windows GUI 首次使用、重新登录自动启动、退出                        |
| 4 Windows 真实闭环        | 主要旅程通过           | 见 local-desktop-acceptance.md；全新用户账户与真实断网重试待验      |
| 5 computer_use 与能力信息 | Windows真实旅程通过    | 关闭/开启、记事本输入保存、任务停止；Mac/Linux待验                  |
| 6 macOS / Linux 宿主      | 源码完成、部分构建     | Linux release/DEB通过；Mac未构建，二者真实桌面待验                  |
| 7 发布与交付              | 本地候选已构建，未发布 | Windows EXE、签名Android APK、Linux DEB；Mac DMG待设备              |

## 2026-11-04 / 模块一：Node 桌面托管

- `run --desktop`：stdin 关闭或收到 `stop` 行即优雅停止并退出；stdout 输出 `{"desktop":{"state":...}}`（starting / online / offline / stopping / stopped / failed）。信号处理移到 Hermes 启动之前，首次长时间启动中途停止也会回收 Hermes 子进程。
- `--hermes-launcher` / `NEKODOT_HERMES_LAUNCHER` 直接启动官方 launcher，不经 PATH 或 bash。
- 插件桥接地址统一由 `bridge.ts` 决定：POSIX 为节点目录 Unix socket（超过 sun_path 上限时放入私有临时目录），Windows 为每次启动随机命名的 named pipe；例行任务与保密插件共用同一段 Python 客户端，业务协议不变。
- gateway 控制通道在 Windows 按 Hermes `os.path.normcase` 规则连接 `\.\pipe\hermes-gateway-<hash>`；Windows 停止 gateway 先执行 `gateway stop --yes`，超时后才结束进程。
- 桌面托管节点不提供 Bot 独立屏幕；文件交付识别 `C:\…` 路径和 Windows file URL。
- 验证：TypeScript、ESLint、Node bundle；Windows 上全量 Vitest 38 文件 68 项通过，新增测试用系统 Python 实际经 named pipe 往返中文请求，并与 Python `normcase` 对照中文路径的管道名。尚未连接真实 Hermes，真实验收在模块四进行。

## 2026-11-04 / 模块二：客户端本机运行模块

- `lib/local/`：两个目录分别选择与检查（绝对路径、不在应用安装目录、本机固定磁盘、空文件夹或已有 nekodot 目录、剩余空间），新建目录设为仅当前用户可访问；系统应用数据目录只保存指针 `local-runtime.json`。
- 安装：Node 24.22.1 按内置 sha256 下载并解压；Hermes 安装脚本按 v0.22.6 提交下载并核对内置 sha256；依次执行官方 `prerequisites`→`complete` 阶段并解析结果帧，完成情况写入运行环境目录，重试跳过已完成阶段。`products` 由包装脚本加载官方 install.ps1 的函数后执行其源码构建，不执行发布命令与 PATH 改写。安装进程不继承用户的 `HERMES_*`、`NEKODOT_*`、`UV_*` 变量，uv 的 Python 与缓存放在运行环境目录。
- 进程：Rust 桥接新增受控子进程，Windows 用 `CREATE_NO_WINDOW` 与 kill-on-close Job Object，POSIX 用独立进程组；Dart 读取按行输出与退出码。Node 以 `run --desktop` 启动，stdin 发 `stop` 优雅停止，60 秒后结束整个进程树；退出码 75 时执行与服务器启动脚本相同的 pending/tried/rejected 回滚标记后重启。端口在 18642–18742 内取连续三个空闲端口。
- 账号：每个账号 `accounts/<userId>` 运行官方 `config` 阶段、从 Relay 下载 Node bundle，最后才申请配对码并以 `pair` 写入节点身份。
- 验证：Rust Windows 目标编译、flutter analyze 无问题、23 项 Flutter 测试通过。尚未进行真实安装，在模块四验收。

## 2026-11-04 / 模块三：首次使用与生命周期界面

- 桌面“添加电脑”先选择“在这台电脑运行”或“连接远程服务器”；Android 不变。本机页面显示两个目录与可用空间、逐步安装状态、真实错误、取消与重试；上线后自动选中这台电脑并回到首页。
- 设置页新增“这台电脑”卡片：运行状态、启动/停止、两个目录及打开入口。登录后自动启动该账号已配对的本机节点；退出账号先停止本机节点；退出应用先停止本机节点，本机有任务运行时先确认。
- 修正配对页在快速配对时把新节点当成旧节点、无法自动选中的问题。
- 验证：flutter analyze 与 23 项测试通过；真实界面旅程在模块四进行。

## 2026-11-04 / 模块四：Windows 真实闭环

- 真实 GUI 旅程：注册 → 在这台电脑运行（中文路径）→ 官方 Hermes v0.22.6 安装 6.3 分钟 → 自动配对并选中 → 创建 Bot → 真实模型欢迎；重新登录自动启动，真实模型以原生 `read_file`/`write_file` 读写中文路径文件并逐字核对；停止、启动、退出后所属进程 0 个，历史不变、不重复执行。
- 强制结束客户端 0.9 秒内所属 6 个进程全部回收；Relay 重启后节点自动重连；固定 Android 模拟器访问本机节点完成真实流式回复；退出后 Relay 显示离线。
- 修正：Windows 阶段输出改为 UTF-8；进程结束先回收进程树再读取输出；聊天不显示空白 commentary。POSIX `products` 包装脚本已写好，未在 macOS/Linux 运行。
- 未验：全新 Windows 用户账户、断网与取消重试、UTF-8 修正后的 GUI 全新安装、Android 真机。详见 docs/local-desktop-acceptance.md。

## 2026-11-04 / 模块五：本机桌面操作能力

- 协议：`sync.snapshot` 与新 `desktop.status` 返回 `host`（server/desktop）、`computerUse`（Bot 独立屏幕）与 `desktopControl`（computer_use 安装、就绪、可授权、说明）；新 `bots.desktopControl` 读取或切换 Bot 的原生 `computer_use` 工具集，均经 Hermes 官方 REST。
- 这台电脑上新建 Bot 默认关闭桌面操作；Bot 详情新增“操作这台电脑”开关并显示就绪情况；macOS 授权只在这台电脑上由客户端调用官方 `computer-use permissions grant`。
- 真实 Windows 节点验证能力返回与开关读写（Hermes CLI 读回）；新增 1 项 widget 测试。尚未让真实模型实际操作桌面。

## 2026-11-04 / 模块四补充：取消与重试

- 第二套全新目录中于依赖安装阶段取消，保留已完成阶段；重试跳过它们继续，4.4 分钟上线；UTF-8 修正后 GUI 日志中文路径正确。取消原因改为本地化文字。
- 发现：Bot 欢迎回复进行中发送的消息未保存也未送达（两次复现），欢迎结束后发送正常；记录为待处理，非本机运行专有。

## 2026-11-04 / 修正：欢迎回复进行中发送的消息

- 原因：新 Bot 的欢迎回合在 gateway 冷启动、尚未获得 Hermes 受理号时，`messages.send` 以 “The current run is starting” 拒绝，消息未保存（草稿保留，提示为英文）。只等受理后再 steer 也会失败：Hermes 受理后异步认领执行，立即 steer 返回 `stale_generation`（真实复现）。
- 修正：欢迎回合期间的发送先等待该欢迎的受理，再以原生 `prompt.submit` `queued` 跟在欢迎之后作为用户自己的回合（复用 `/queue` 路径），欢迎回复保持完整；同一 `clientMsgId` 在等待期间重发共享同一结果。普通运行中的发送仍走 steer，群聊未改动。
- 验证：新增辅助测试（受理前发送与重发 → 欢迎先提交、用户消息以 queued 提交一次、无 steer）；Node 29 文件 60 项、TypeScript、ESLint 通过。真实验收：隔离 QA Relay（4459）+ 本次源码 Node bundle，`local_desktop_journey_test.dart` 阶段 `first` 在全新目录 `运行环境4`/`数据4` 运行，发送时欢迎仍在进行（`thinking`/`streaming`），Hermes 记录两个入站回合，真实模型 `read_file`→`write_file` 逐字一致，停止、启动、退出后进程 0 个，全部通过。修正前的中间版本（等待后 steer）在 `运行环境3` 得到 `stale_generation`，已舍弃。
- 未验：Android 端在欢迎期间发送；macOS/Linux。

## 2026-11-04 / 模块五补充：本机桌面操作真实运行

- 关闭时 Bot 无桌面工具并如实回复，三次一致；开启后因同一运行内第二条消息未送达（与欢迎回复期间消息丢失同类，已交修复会话），尚未完成真实记事本输入、保存与停止验证。新增可原样重跑的 `local_desktop_control_test.dart`。

## 2026-11-04 接手复验：真实桌面与连续消息

- 查明“第二条消息未送达”实为集成测试失焦后输入未写入；修正测试的真实点击聚焦、文字断言与目录指针，不改聊天逻辑，移除15秒等待/重启绕行。
- Windows 本次候选 + 隔离 Node/Relay + Hermes v0.22.6 + gpt-6.1-sol：记事本真实输入和保存、关闭时无工具、任务停止通过；独立连续消息/文件读写旅程通过，停止及退出后进程0，重启不重跑。
- 更正早前模块一至三的日期笔误（应为11月4日），保留当时结果与本次更正。未部署、未push。

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

## 2026-11-04 本地安装顶部进度条

- 本地安装页最上方增加原生线性进度条和中英已完成步骤数，直接读取安装、账号准备、配对及启动的13个实际阶段；不模拟耗时百分比、不改安装流程。
- Windows当前源码构建原生客户端，复用已安装runtime6并使用全新隔离账号/数据：顶部9/13与实际步骤一致，截图人工检查布局通过；完成安装、上线、真实gpt-6.1-sol文件读取/写入、第二条消息以及停止/重启历史保留，退出后所属进程0。
- 隔离Relay为127.0.0.1:4459，Hermes v0.22.6；本次不是全量重新下载依赖，也未重复Android/macOS/Linux验收。证据：docs/evidence/local-install-progress-windows.png；私有完整旅程记录在.runtime/local-desktop/progress-20261104-141029/。
- Flutter analyze无问题、24项辅助测试通过；真实集成旅程增加顶部位置和阶段数断言，取消分支增加保留进度断言但本轮未重跑取消旅程。只做本地提交，不发布、不push，既有安装包未替换。

## 2026-11-04 0.3.1 发布准备

- 用户授权发布并 push：产品版本升为0.3.1+7，Android arm64 versionCode 2007；更新官网、README与发布说明。
- 发布范围包含已完成的本机运行、保密交付、更新入口、Markdown与托盘修复、安装顶部进度；不包含未提交的历史截图或设计草稿。
- Windows/Android构建与正式下载发布进行中，尚未宣称发布完成。macOS无构建设备，Linux未完成完整桌面验收。

## 2026-11-04 发布版本检查修正

- 独立构建发现Relay下载测试写死0.3.0，改为读取产品版本，实际HTTP版本与package.json保持一致；不是放宽运行校验。

## 2026-11-04 0.3.1 正式发布

- Windows/Android release及Relay镜像已构建；Android沿用签名、versionCode2007。独立服务端检查69项测试、Flutter analyze/24项测试通过。
- 官网和正式Relay已更新0.3.1/build7，Node按既有空闲机制更新20261104070530并上线；账号、历史、profiles和无关服务保留。
- 正式HTTPS/WSS真实gpt-6.1-sol回复与Webhook执行/去重通过；官网安装包实际下载正确。详情见docs/release-0.3.1-acceptance.md。
- GitHub源码/标签/正式Release按用户授权同步。macOS未出包、Linux未完整桌面验收、本轮无Android真机结果；没有把待验项目写成通过。

## 2026-11-04 UI 重构：主界面、Bot 详情与设置归类

- 主界面按 Ardot「Desktop - 1」：侧栏顶部节点名＋搜索/新建，群聊与 Bot 两个可折叠分组；会话为圆角卡片，选中抬起阴影、悬停浅阴影，显示角色说明与最近消息；底部为账号菜单与设置入口。
- 按钮统一为胶囊形，图标按钮为更小的圆形；卡片、分段控件、输入框与聊天顶部 Bot 标签统一圆角＋阴影；深色、Android 玻璃风格分别给出阴影与选中滑块颜色（新增 `thumb`）。
- Bot 详情：桌面右侧面板先以零宽渲染、两帧后再滑入（240ms 出、180ms 收）；手机从标题处放大淡入，同样两帧后开始，避免首帧构建耗时把动画直接跳到终点；尊重系统减少动画。标签改为贴合内容的滑块。
- Bot 设置按种类重排为模型、能力、记忆与学习、安全与隐私、语音、运行；Hermes 原生设置按 key 前缀归入对应种类，模型、操作这台电脑、保密资料、语音与唤醒等产品入口放进同一种类。
- 适用于所有 Bot 的设置（模型服务、消息平台、凭据、网络与代理、Hermes 界面、通用）移到应用设置「所有 Bot → 共用 Hermes 设置」，与模型来源、关于你、Skills 与插件同组。Node 新增 hermes.shared.get/set：写入根 profile 与所有 Bot profile（含已归档）并记录，新建 Bot 自动继承；Bot 级接口拒绝共用 key，共用接口拒绝 Bot key。
- 真实验收（QA Relay 127.0.0.1:4459、本机 Node、官方 Hermes；本轮只验界面与设置，未发起新的模型对话，聊天内容为此前真实对话）：Windows 当前源码 debug 客户端完整旅程通过——分组折叠、详情面板中间宽度 65/276px、Bot 设置六类与共用 330 项无重叠、能力页搜到 terminal.backend、界面切换 display.compact 后根 profile 与 4 个 Bot profile（含 2 个已归档）配置文件实际写入、之后新建的 Bot 继承、还原、Bot 级写共用 key 被拒；测试 Bot 已归档。Android 模拟器 NekodotNativePhase3 同一旅程通过，详情放大采到 0.962/0.989/0.999 三个中间帧。
- 深浅色截图逐张检查：docs/evidence/ui-refresh-*.png。node 52 项、Flutter 24 项辅助测试与 analyze、tsc、eslint、prettier 通过。未验：Android 真机、macOS/Linux、release 包流畅度（模拟器 debug 包推入详情时约 5 帧/秒）。只做本地提交，未 push。

## 2026-11-04 Hermes 设置与命令中文、Android 黑白配色

- 913 项 Hermes 原生设置（Bot 自身 583 项与共用 330 项）全部有中文名称和说明，命令面板 138 条命令（含 40 个默认技能）有中文说明，3 条 App 不支持的原因也有中文；依据固定版本 Hermes v0.22.6 的配置说明、默认值和命令源码写成，表在 `apps/native/lib/data/hermes_zh.dart`。
- 中文界面里设置以中文名打头，下面是说明、当前值和原始 key（小字，便于对照 Hermes 文档）；搜索可用中文名、说明或 key；编辑框标题与提示同为中文。英文界面不变。Hermes 新版本新增、表里还没有的项按 Hermes 原文显示。
- Android 改回纯黑白：保留手机的大尺寸控件、顶栏与底部 dock，去掉灰色渐变底和光斑，卡片改为不透明白/黑底加阴影，与 Windows 一致。
- 真实验收（QA Relay 127.0.0.1:4459、本机 Node、官方 Hermes）：Windows 当前源码客户端与 Android 模拟器 NekodotNativePhase3 的同一旅程均通过；真实节点返回的 913 项设置、138 条命令无一缺中文，底色为纯白/纯黑，命令面板与能力页实际显示中文，共用设置写入与继承照旧通过。截图：docs/evidence/ui-refresh-*.png。
- Flutter 25 项辅助测试（新增中文设置用例）与 analyze 通过。未验：Android 真机、macOS/Linux；用户自行安装的技能、插件命令仍是原文。只做本地提交，未 push。

## 2026-11-04 打开即显示每个会话的最新消息

- 原来启动后只同步会话列表，消息要打开会话才加载，所以没打开过的会话在列表里没有最新消息。现在 Node 首次同步（sync.snapshot 新增 `latest`）附带每个会话最新一条有文字的消息，客户端单独保存，不预加载整段历史；之后的实时消息照旧更新列表。Windows 与 Android 共用这一逻辑。
- 真实验收：本机 QA Node 换上新构建（旧包另存为 nekodot-node.cjs.before-latest），Windows 当前源码客户端与 Android 模拟器 NekodotNativePhase3 冷启动后、未打开任何会话前，本机小助手与笔笔两行即显示各自最新消息；两端旅程其余步骤照旧通过。截图：docs/evidence/ui-refresh-windows-home.png、ui-refresh-android-home.png。
- 新增 Node 用例（跳过工具步骤与空草稿，只取有文字的最新一条）；Node/协议/Relay 62 项、Flutter 25 项辅助测试与 tsc、eslint、analyze 通过。有一轮 Windows 旅程在 Hermes 刚启动时命令面板 90 秒内未加载出命令，重跑正常，未改产品代码。未验：Android 真机、macOS/Linux。只做本地提交，未 push。

## 2026-11-04 官网开场改版

- 首屏改为一段滚动开场：白底上新版 Windows 主界面截图弹出（比原来大，几乎占满一屏），8 个 Bot 依次从截图背后跳出、越过边缘落到截图前面；下滑时截图后退变淡，nekodot 名称卡片浮上来，再放大铺满全屏，Bot 围在名称与下载按钮周围，随后直接接原有的功能讲解。按钮统一为胶囊形。
- 手机上换成手机主页截图，两侧 Bot 移到名称上方；深色模式跟随系统；减少动态效果时不播放动画，截图与卡片直接上下排列。开场两组截图（desk-group、phone-home，浅色/深色）用 UI 巡览对新界面演示数据重新拍摄，页面下方其余截图仍为旧界面。
- 在内置浏览器检查 1440×900、755 宽与 375×812 的开场、下滑中段与全屏卡片，浅色与深色，无横向溢出；eslint、prettier 通过。只做本地提交，未部署；正式发布时需按 apps/site/README.md 递增资源版本参数。

## 2026-11-04 官网介绍重写：突出产品重点

- 重新梳理亮点，开场之后按五件事讲：几个 Bot 在一个群里接力；装在你自己的电脑上（Windows 选「这台电脑」自动安装，数据各存在哪写清楚）；动手之前先问你（审批、运行中补充、停止、拿不准会问）；人不在电脑前用手机管；开源、底下是 Hermes Agent。最后是四张能力卡片（屏幕接管、可编辑的记忆、技能、保密交付）和更新后的三步开始。
- 文案改成具体场景和事实：写明 2–6 个 Bot、最多连续 6 轮、四种审批选项、通知覆盖回复/提问/确认，保留「模型请求发给服务商、不是离线、无端到端加密」和屏幕仅限 Linux 服务器等说明；去掉口号式排比和已过时的「毛玻璃」、Linux/WSL2 配对为唯一途径等内容。中英文逐条对应。
- 配图动画：三段会自己播放的对话（群聊接力、读写本机文件汇总报销、审批与提问轮播），手机通知滑入，屏幕接管光标与输入、记忆新行打字、技能安装、保密交付按钮等循环小动画；对话离开视口时播完当前一段再停。新增手机私聊截图，深色模式为卡片、对话框补了表面色和细边。
- 用 Playwright + Edge 在 1440 浅色/深色/英文、390 浅色/深色英文与减少动态效果下逐段截图检查，无控制台错误、无横向溢出；eslint、prettier 通过。只做本地提交，未部署；正式发布时需按 apps/site/README.md 递增资源版本参数。根目录 README 的介绍未同步修改。

## 2026-11-05 README 改写与官网重新部署

- README 开头按官网的五个重点重写（群聊接力、装在自己电脑上、动手前先问、手机管着、开源基于 Hermes），快速开始加入 Windows「这台电脑」，路线图补上本机运行、保密交付和 0.3.1；聊天截图换成当前界面。官网与 README 里「Hermes 设置都有中文说明」改为 0.3.1 已有的「原生设置能在 App 里直接改」，因为中文说明还没发布。
- 官网资源版本参数改为 0.3.1-20261105。按提交内容 `git archive` 打包上传，正式服务器 /opt/nekodot-product/site 原内容先备份到 releases/site-20261105/backup-site，再覆盖；Relay 直接读目录，未重启任何服务，health 仍为 0.3.1/build7。
- 公网检查：首页、脚本、样式、新截图均 200，两个固定下载地址 200；Playwright + Edge 对 https://nekodot.com 按 1440 与 390 逐段截图，无错误、无横向溢出。
- 提交时排除了测试重跑改写的历史 docs/evidence 截图、其他阶段未跟踪的证据、opus-video/、design/ardot/ 与 Flutter 测试失败比对图。官网截图来自当前源码，比 0.3.1 客户端略新。本地提交，未 push。

## 2026-11-05 聊天卡片从简、图片直接显示、自由选中与侧栏可调

- Skills 与插件移到右上角「＋」菜单的「添加插件」，账户菜单与手机底栏不再放这个入口；打开后顶部切换 Skills / 插件。
- 提问、审批、保密请求统一成同一种卡片：一圈细线、白底、无阴影，粗体标题在上。提问的选项为 A/B 字母行，单选一点即答，多选才有「提交」，下方「其他回答」输入框带发送箭头；答完显示「✓ 所选答案」，被中断的显示「— 未回答」。审批选项也是字母行（允许一次在首位）。
- 保密请求只留名称、一个输入框与「提交」、「允许 Bot 复用」：多个字段时一次填一个（下一步），有已保存的匹配时可「用已保存的」；去掉了说明文字、接收方、展开收起和取消按钮，完成后显示「✓ 已完成」。例行任务卡片改为一行小字。
- Bot 发来的文件不再放在对话气泡里，各占一行：图片直接显示（保持原比例，不放大超过原像素，点开看大图），其他文件显示名称和大小。回复里只用来交付文件的 MEDIA 行和本地路径链接不再显示成文字，会话列表预览同样去掉。
- 回复文字整段可选（拖选可跨行跨段，手机长按可全选），每条 Bot 回复下方有复制小图标，复制后短暂变成勾。
- 桌面端侧栏与主栏之间的分界线可以拖动（240 到窗口宽减 420），松手后记住宽度。
- 真实验收（QA Relay 127.0.0.1:4459、本机 Node、官方 Hermes、真实模型）：新增 integration_test/chat_cards_journey_test.dart。Windows 当前源码客户端：＋菜单打开插件、侧栏拖窄 120 并保存、模型发起 clarify 选择题并一点作答、模型发起保密请求后填入并勾选复用、Bot 读取交付的 env 回复 SECRET_CARD_OK 且聊天记录不含明文、模型生成 notes.txt 与 360×220 PNG 并交付（图片按原尺寸显示、MEDIA 行未显示）、拖选两段并 Ctrl+C、复制图标复制全文均通过；途中 Bot 请求运行 python -c 时审批卡片「允许一次」放行。Android 模拟器 NekodotNativePhase3（节点由新预览版托管）同一旅程（保密请求一步只在 Windows 跑）通过，图片按手机宽度缩放保持比例，长按全选复制通过。截图：docs/evidence/chat-cards-*.png。
- 已知：跨段拖选复制时两段之间没有换行（Flutter SelectionArea 的拼接方式），复制图标复制的是带分段的原文。现有 product、secrets 旅程按新卡片改了操作方式，本轮未重跑。Flutter 27 项辅助测试与 analyze 通过。未验：Android 真机、macOS/Linux。本地提交，未 push。

## 2026-11-05 工作步骤折叠、状态说明与浮层阅读器

- Bot 干活时调用的工具（以及步骤之间它写的过程说明）合成一个框，默认折叠，放在你的消息下面。框和里面每一步用同样的细线白底、同样的行高与字号；点开逐条列出「读取网页 https://…」「运行命令 python -c …」与用时，再点某一步才显示完整参数和结果。做完后框只剩一行「N 个步骤 · 用时」，有失败会标出。审批卡片里的命令也收成同样材质的一行，点开才看完整命令。
- 原来工作中的「…」换成正在做什么：Bot 在这一步前自己写了说明，就显示它的原话；没写时显示 Hermes 原生的中文步骤说明（来自 Hermes display.verb 与工具调用的 context，如「正在读取网页 https://nekodot.com…」「正在运行命令 …」）；步骤之间显示「思考中…」。Node 现在把 Hermes tool.start 里的 context 一并存进工具步骤（协议加了可选字段 context），旧步骤没有 context 时只显示动作。
- 文件与图片不再跳到新页面，直接在当前页面上浮起阅读器：图片可缩放，文本可选中，PDF 照常预览，顶部有分享、保存、关闭；Bot 资料库里的文件同样如此，.tar.gz 仍可「作为新 Bot 导入」。
- 真实验收（QA Relay 127.0.0.1:4459、本机 Node 换上新构建、官方 Hermes、真实模型）：新增 integration_test/work_steps_journey_test.dart。Windows 当前源码客户端与 Android 模拟器 NekodotNativePhase3（节点由新预览版托管）均通过：聊天里之前的图片和 notes.txt 点开都是浮层、聊天页仍在底下；让 Bot 看 nekodot.com 首页标题并运行 python -c，工作中状态依次为「思考中…」「正在读取网页 https://nekodot.com…」「正在运行命令 python -c "print(6*7)"…」，审批卡片命令默认一行、点开可见全文、「允许一次」放行；完成后框显示「2 个步骤 · 5.9s」且默认折叠，点开两步的说明不再是原始 JSON。截图：docs/evidence/work-steps-*.png。
- 本轮真实模型没有在步骤前写过程说明，所以只验到 Hermes 步骤说明这一路，Bot 自述那一路未在真实运行中出现。composer、host 命令、product、tool-markdown 旅程按浮层与步骤框改了操作方式，本轮未重跑。Node 相关 6 项与 Flutter 辅助测试、analyze、eslint、prettier 通过。未验：Android 真机、macOS/Linux。本地提交，未 push。

## 2026-11-05 审批并入步骤、Bot 每步先说一句、菜单与设置收拾、新建 Bot 表单

- 审批：等待中的命令收成运行命令同款的一行（图标、单行、点开看全文），下面是允许一次、拒绝等按钮。允许后并入步骤框，与其他步骤一样只显示一行，不再单独出现；框内同一命令只显示一次，计数只算工具步骤。
- Bot 说明：nekodot 托管的 SOUL.md 段新增规则，每次调用工具或命令前，在同一条消息里写一句十五字以内的说明。每轮开始时同步这段（内容不同才写入）。状态行显示 Bot 自己这句话，框里也保留。注意：已经开着的会话沿用创建时的系统提示，新会话才生效；真实验收里先发 /new。
- 菜单：「＋」菜单和账户菜单改成图二样式，图标加文字，分组用细线隔开。Skills/插件、设置页的分段切换仍是胶囊样式，本次未改。
- 设置：Node 在 Hermes 设置处剔除本产品用不上的项，读写都拒绝，Hermes 默认值保留。剔除的有：Discord、Telegram、Slack、Matrix、Mattermost、网关、托管房间、Bot 模式、看板；终端界面与桌面、网页应用展示（display、dashboard、human_delay、desktop、webapp、粘贴折叠阈值）；Hermes 自身的更新、诊断、遥测、监控、日志、数据库、运行时、唤醒词、目标、循环、X 搜索、LSP、工作树、钩子自动接受；OpenRouter、Bedrock、Vertex、本地模型。
- 新建 Bot：颜色与形状选择放大（头像 88，形状 44，颜色点 30）。角色设定从表单移除，新建时角色为空，打开后再和 Bot 说。@handle 收进「高级」，默认与名称相同。
- 真实验收（QA Relay 127.0.0.1:4459、本机 Node、官方 Hermes、真实模型）：Windows 当前源码客户端，步骤旅程通过，新会话后 Bot 自己的说明显示在状态行（如「我先读取首页，并运行指定的 Python 命令…」），框显示「2 个步骤」，展开后两条说明与步骤各一次。新建 Bot 旅程通过：不填角色、@handle 在高级里自动跟名称、真实 Hermes 欢迎语完成。Android 模拟器 NekodotNativePhase3（节点由测试版托管）步骤旅程通过。截图：docs/evidence/work-steps-windows-approval-folded.png、work-steps-android-done-open.png。
- 未验或已知：去掉重复显示之后，没有再触发审批，所以「允许后并入框」的最新状态未再跑；上一轮审批允许后框内计数为 3 个步骤，已验证并入。composer、product、tool-markdown、ui_refresh 旅程未重跑（ui_refresh 的设置键已改为 proxy.enabled）。Node 65 项、Flutter 26 项测试，tsc、eslint、prettier、analyze 通过。未验：Android 真机、macOS/Linux。本地提交，未 push。

## 2026-11-05 工作状态行、回车发送与统一菜单样式

- 工作状态：Bot 干活时，输入框上方一直显示一行「头像 + 名字 + 它自己说的正在做什么」，如「本机小助手 正在查看首页并运行计算」，代替原来的「…」。文字取自 Bot 本轮最新写的那句话（一句话可以覆盖几个并行步骤）；Bot 还没开口时用 Hermes 对正在运行步骤的中文说明（「正在运行命令 …」），什么都没有时是「正在思考」。步骤框在干活时只显示「N 个步骤」，不再重复状态。托管 SOUL.md 规则改为：每次调用工具前写一句不带自己名字的短句，中文以「正在」开头（如「正在查看推文」），英文以 -ing 动词开头；已开着的会话需 /new 才会用上新规则。
- 输入框：回车直接发送，Ctrl+回车换行；输入法正在组字时回车交给输入法，不发送。手机软键盘的回车仍是换行。
- 菜单：所有弹出菜单和下拉选择统一按参考截图重做：白底圆角 16、细边与柔和阴影，上下各留 6，行高桌面 36 / 手机 44，左侧 17 号线条图标，14 号正文，右侧灰色附加信息或勾，分组细线左右各缩进 16，最小宽 220。账户菜单、「＋」菜单、电脑切换菜单换成这种行；新建 Bot 的模型来源、主答、审批，命令面板的执行 Bot，Hermes 设置里的单选，宠物的图像服务从系统下拉改为同款菜单，下拉宽度与输入框一致；模型名称的联想列表也用同款卡片。
- 真实验收（QA Relay 127.0.0.1:4459、本机 Node 换上新构建、官方 Hermes、真实模型）：work_steps 旅程扩充并在 Windows 当前源码客户端与 Android 模拟器 NekodotNativePhase3（节点由新测试版托管）均通过。菜单行高实测 36 / 44；Ctrl+回车只插入换行、组字中回车不发送、回车发出任务；新会话后状态行依次为「本机小助手 正在思考」「本机小助手 正在查看首页并运行计算」（Android：「正在读取首页并运行计算」），与 Bot 本轮写的那句一致。截图：docs/evidence/work-steps-_-working.png、work-steps-_-menu-*.png。
- 新增 Flutter 单元测试 working_line_test；Flutter 28 项、Node runtime 6 项测试与 analyze、tsc、prettier 通过。hermes_settings、providers、research_* 旅程已改为找新的菜单选择，本轮未重跑。未验：Android 真机、macOS/Linux、真实输入法组字（用模拟的组字状态验证）。本地提交，未 push。

## 2026-11-05 合并 PR #1 中不冲突的部分

- 来源：AR307/nekodot PR #1（FairChan，分支 codex/integrate-all-20261105，15 个提交）。用 squash 合入本地，GitHub 上 PR 仍是打开状态，暂缓的部分以后可以再合。
- 合入：网页端新登录/注册页、ShiningText 闪光文字（替换各处「加载中」，原生端同样）、Gooey Nav 分段切换、Animated List 列表、网页输入框与语音、网页 AI 审批卡片；官网首屏自动开场（约 5.2 秒，切到别的标签页会暂停）；原生端登录页改版（auth_frame、auth_layout、校验测试、auth_journey）；对应文档、浏览器测试与证据截图；打包脚本的 vswhere `-products *` 修复。PR 中的 nekoDOT 写法在合入文件里统一回 nekodot，docs/development.md 去掉「产品名称」一节。PR 自带的证据截图拍于改名时，图中仍是 nekoDOT。
- 冲突处保留本地实现：chat.dart、files.dart、home.dart、secrets.dart 用本地版本，只把 ShiningText 移进 Hermes 指令执行行、阅读器加载、电脑切换的「连接中…」和保密请求加载；parts.dart 保留 Breathing（PR 删了，步骤框仍在用）。
- 暂缓、等验收：nekoDOT 品牌改名（会改 exe 名与安装目录）、原生 AI 审批卡片、原生输入框胶囊与模型选择、SVG 侧边预览与 Windows 文件操作，以及 PR 自己写的 Summary/progress 记录。
- 真实验收（QA Relay 127.0.0.1:4459、本机 Node、官方 Hermes、真实模型）：Windows 当前源码客户端 work_steps 旅程通过，经 PR 新登录页登录，状态行依次为「本机小助手 正在思考」「正在查看首页标题并运行计算」「正在用 terminal 运行指定的 Python 命令」，完成后「2 个步骤 · 4.9s」，菜单行高 36，回车发送。内置浏览器连本地网页（4466 → QA Relay）：登录页登录成功，Gooey Nav 与 Bot 列表正常，给笔笔发「用 terminal 运行 python -c」后出现闪光「正在思考」、terminal 步骤，回复 42。官网本地预览：开场按顺序播放，停在完整首屏。
- 未验或已知：网页 AI 审批卡片没触发真实审批（笔笔的命令不需要审批，第二次请求时节点已随旅程结束离线）。Edge 浏览器测试要加 `NODE_OPTIONS=--import=tsx` 才能加载（releases.ts 直接 import package.json，Node 24 要求 json 导入属性，自 766db25330 起）。全套 20 项：17 通过、1 跳过（screens-live 需真实 Linux 屏幕）、2 失败；失败的 groups（第 234 行等发送失败提示）与 node-update（更新提示不出现，页面显示电脑离线）换回合并前的网页代码同样失败，与本 PR 无关。foundation、groups、node-update、providers 四个旧测试仍点「继续」，已改为新登录页的「登录」/「创建账号」，groups 的「模型」输入框与新输入框的模型选择同名，改按文本框定位。运行前快照了 docs/evidence，结束后按字节恢复。原生 auth_journey 需要 Mailpit 8025，未跑。Android 模拟器与真机本轮未跑。Flutter 30 项、pnpm test 75 项、tsc、eslint、合入文件的 prettier、analyze、网页 build 通过；另有 7 个本轮未改动的文件原本就不符合 prettier。本地提交，未 push。

## 2026-11-05 PR #1 暂缓项按验收决定落地

- 品牌：保持小写 nekodot，PR 的 nekoDOT 改名不合入。
- 工作状态行：Bot 干活时输入框上方那句「名字 + 正在做什么」改用 PR 的闪光文字，灰字上有白光扫过，两秒一轮；系统关闭动画时为静止灰字。
- 审批与提问卡：保留我们的一行样式，借用 PR 的两点：
  - 提交时只有点下的按钮闪光，其他按钮不可点；Node 接受后卡片立刻定为结果，不会在等服务器更新的间隙重新开放。
  - 失败时错误旁有「重试」，按原选择再发一次。ErrorNotice 现在可以带一个操作按钮。
- 输入框：
  - 外观换成 PR 的胶囊（prompt_card.dart）：空闲时宽 320，聚焦、有内容或运行中展开到最宽 480，圆角 24，细边加柔和阴影。
  - 展开后下方一排：左边是当前模型，点开为统一菜单卡，列出模型目录和「Bot 模型设置」；右边「＋」发文件。群聊不显示模型按钮。
  - 右侧按钮：私聊空闲时是语音，转写结果回填到输入框（取自 PR 的 voice.dart 改动）；运行中是停止；有字时是发送。
  - 回车发送、Ctrl+回车换行、工作状态行都不变。
- 文件阅读器：
  - 保留浮层。SVG 在聊天和阅读器里都直接显示为图形，可缩放（25%–400%），阅读器可切换看源码。
  - 电脑端阅读器顶部新增「打开」菜单：用默认应用打开；Windows 另有「打开方式…」和「在文件夹中显示」。这两项取自 PR 的 Windows runner file_actions，只操作临时副本，不改原文件，也不改默认关联。
  - 没有用 PR 的 WebView 截图渲染，改用项目里已有的 flutter_svg，少一个原生插件；代价是 SVG 滤镜（阴影、模糊）不显示。
- 修正：交给系统的临时副本路径原先混用 / 和 \，Windows「在文件夹中显示」报 0x80070057；现在统一用系统分隔符。
- 真实验收（QA Relay 127.0.0.1:4459、本机 Node、官方 Hermes、真实模型），work_steps 旅程扩充：
  - Windows 当前源码客户端：胶囊空闲 320、展开 480，模型菜单列出 gpt-6.1-sol 与「Bot 模型设置」，状态行依次为「本机小助手 正在思考」「正在查看首页标题并运行计算」「正在运行指定的 Python 命令」，2 个步骤。之后 Bot 用 terminal 生成 badge.svg 并交付，渐变在聊天和阅读器里都正确显示；源码视图含 <svg；「在文件夹中显示」打开资源管理器并选中临时副本。
  - Android 模拟器 NekodotNativePhase3（节点由新预览版托管）同一旅程通过：胶囊 320 展开到手机宽 387，菜单行高 44，SVG 在聊天、阅读器、源码视图都正常；手机上没有「打开」菜单，用分享代替。
  - 截图：docs/evidence/work-steps-windows-composer-model.png、work-steps-windows-drawing-chat.png、work-steps-windows-viewer-open-menu.png、work-steps-android-composer-model.png、work-steps-android-drawing-chat.png、work-steps-android-viewer-drawing.png。
- 模拟器：NekodotNativePhase3 以 GPU 模式启动时连续崩溃（崩溃信息 bad color buffer handle），冷启动也一样。本轮改用 `-gpu swiftshader_indirect` 启动，AVD 配置未改，未 wipe-data。崩溃报告未发送。
- 未验或已知：两次真实运行都没有触发审批，所以审批卡的「提交中锁定 / 立即定结果 / 失败重试」只在代码和组件层面完成，真实审批未再跑；「用默认应用打开」「打开方式…」只验了菜单出现，没有实际打开外部程序；macOS、Linux 与 Android 真机未验。Flutter 35 项测试与 analyze 通过。本地提交，未 push。

## 2026-11-05 旧 Web / Tauri 客户端回收

- 按用户明确授权，将 apps/web、apps/client、packages/tauri-plugin-nekodot、两个专用构建/开发脚本、tests/browser 和 playwright.config.ts 移入 D:/nekodot-recycle/ui-20261105，清单在同目录 manifest.json；不永久删除。
- 保留 Flutter、Node、Relay、官网 apps/site、历史证据和用户数据。移除旧客户端专用依赖、别名和 CI 浏览器入口。官网静态服务改为明确的 SITE_DIR；产品 Compose 同步，不保留旧 SPA fallback。未部署到正式服务器。
- PowerShell 移动旧 node_modules 时跟随了 pnpm junction；协议源码已从回收副本完整恢复（包括本轮修改），依赖重新安装修复。没有丢弃协议修改。
- pnpm frozen install 与 typecheck 已通过，服务端 38 文件 / 74 测试通过。原生候选 UI 和真实 Hermes 旅程单独记录，不以这些测试代替。

## 2026-11-05 UI 配套：模型配置与例行任务通知

- 完成 `models.assign` 与主模型上下文的原生配置写入；辅助、委派、定时槽位使用已有模型来源，不引入新执行通路。命令消息拆分命令名/原生输出。
- 原生 cron 新增、修改、暂停和执行进入现有例行任务通知；首次建立快照，不补发旧创建通知。真实运行发现并修复单次任务完成后被误显示为“已停止”；新完成任务只显示创建与执行，历史消息不改写。
- 隔离 Windows/Android 候选客户端连接真实 Node/Relay、Hermes v0.22.6：主模型 `gpt-6-sol`、上下文 128000、辅助压缩模型 `gpt-6.1-sol` 保存后原生读回一致。真实 terminal 返回 323，Windows 单次任务实际触发并回投结果。
- typecheck、ESLint、服务端 38 文件/75 项测试通过。全量 lint 的 5 个既有文档格式问题原样保留。UI/构建与范围记录见下一模块；未部署、未 push。

## 2026-11-05 原生 UI 十项改进

- 完成侧栏无灰色退场/窄栏不溢出、加号右置、详情内统一模型来源目录选择、可编辑上下文和高级设置折叠。
- 命令与例行任务居中灰字通知；真实进度仅在闪光行显示，有意义回应保留；复制图标悬停/聚焦出现。未增加解释性 UI 段落。
- Windows、固定 Android 模拟器真实验收：登录、详情模型目录与上下文 128000、辅助压缩模型 `gpt-6.1-sol` 原生读回、`/new`/`/resume`、terminal 计算 323；Windows 实际 cron 触发与结果通知通过。
- Flutter analyze/33 项测试、双端 Release 构建通过。详见 `docs/ui-refinements-acceptance.md` 和结构化证据；真机、跨来源、完整公网 webhook 等未验范围明确保留。只做本地提交，不发布、不 push。

## 2026-11-05 Windows 本机安装长路径修复

- 真实复现账号 PM workspace 的 WinError 3：普通路径复制失败，最长 288 字符。用户授权最小 Hermes 安装补丁，仅复制调用使用既有 long_root；不改 HERMES_HOME、Agent 或账号路径。
- Flutter 安装器集成幂等补丁并保留原文件；官方依赖、产品、配置、新账号安装与重试通过。Windows 原生候选使用真实 gpt-6.1-sol 完成读写文件、二次对话和重启历史验收。
- Windows legacy-path 模式下 Hermes 两条测试基线失败、补丁通过；Flutter analyze/33 项测试及 Windows Release 构建通过。详见 docs/windows-long-path-fix.md。仅本地提交，未发布、未 push，用户另一台电脑待复测。

## 2026-11-06 Cron 结果接续与授权规则

- 普通 cron 结果关联至原生执行会话并检查用户所选会话是否已包含结果，避免遗漏或重复注入；用户可从执行详情发起一次明确的新回合来追问。执行会话只读。
- 按最新确认，定时任务授权由 Agent 在聊天中询问，用户自然语言回答后由 Agent 调用 `hermes routine approvals JOB_ID --policy JSON` 设置。支持询问、允许、拒绝及按时区/星期/跨午夜时段组合；移除任务卡配置按钮、详情弹窗及公开设置 RPC。运行时人工审批卡保留。
- cron 回合内出现原生审批时，经对应 Bot 私聊展示并对同一 admission 提交用户选择；不默认拒绝、不停止或重跑任务。Bot 指引要求配置任务时先询问用户的授权偏好。
- 实际 Windows 候选完成真实 gpt-6.1-sol 的聊天设置、允许一次、默认拒绝、自动允许及两种结果追问；三次原生执行对应文件两行，没有因追问重跑。验收发现并修复用户追问消息打开执行详情时 Bot ID 错误、深色气泡链接不可读。
- 固定 Android 模拟器已通过真实聊天创建/设置规则、原生允许一次、默认拒绝、自动允许、普通追问和执行详情的选定结果追问；三次执行实际写入两行 UUID，最终任务暂停。配置规则的工具已成功，后续模型回读停滞时仅停止该回读回合，再继续验收，没有重放配置或已完成任务。结果及截图见 `docs/cron-conversational-approval-acceptance.md`。
- 工程：Hermes 官方测试入口 11 项、代码检查 13 项通过；Node 24 的 38 文件/76 项、typecheck、相关 ESLint/Prettier、Node bundle、Flutter analyze/33 项测试与 Windows/Android release 构建通过。
- 边界：Android 真机未验；跨日时间边界用自动化验证，未宣称实等跨日。安装包只在本地构建，本轮不发布、不 push、不更新正式服务，所有 QA 文件与历史保留。

## 2026-11-06 Flowchart：执行投影

- 新增 flow.get、FlowSnapshot/FlowStep 和 flow.changed，沿用既有账号归属、seq 和快照同步。Node 仅保存每会话最新图，不复制工具参数或输出。
- 真实 admission 开始后建图；工具开始/结束、审批/提问、正文与结束状态来自 canonical 事件。排队不替换图，原生 session 切换清空，群聊按实际接力保留各 Dot 回合。Cron/Webhook 独立执行不接入。
- 辅助行为测试覆盖同一调用、并行、审批拒绝、排队、会话切换、A/B/A 接力及缺失完成事件不误判成功。typecheck、相关 ESLint 和新测试通过；候选 Windows/Android 真实验收正在进行，尚不标记整体验收完成。

## 2026-11-06 Flow：原生计划事件

- 使用 Hermes canonical `todo.updated` 的完整快照，将计划 ID 按 admission 隔离、工具按发生时的当前计划归组。待执行节点不进入实际执行路径，不会因为生成了计划就亮起工具。
- 保留最新私聊或群聊图；不为 cron/webhook 补图，不复用上次任务的计划。群聊同名计划的父子归属、服务重载后的快照恢复有行为覆盖。
- 空白正文不产生回复节点；无结果的原生 settled 保持未知，用户真实选择才更新为已处理。服务端 39 文件 / 81 项、typecheck 与相关 ESLint 通过。
- Windows 真正运行 `gpt-6.1-sol` 的 todo_list → read_file → execute_code → write_file → read_file → todo_list，结果文件均值 20。界面折叠/重连已观察，reduced-motion 验收复现既有 AnimatedSize 零时长布局异常，后续 UI 模块修复；尚不将整体验收标记完成。

## 2026-11-06 Flow：界面与 Plan 折叠

- 采用审核稿（标题 Flow），四状态色；按追加要求外框 32px、行高 56px，点击区域 44px。真实计划自动折叠已完成项、手动展开、跟随下一执行项。
- Flutter 原生面板与 Dot 详情互斥；工具详情/审批定位复用原界面，断线不进度冒进，重新打开不重跑。Android 横屏仍全屏，系统返回仅退出图。
- 真实 Android `gpt-6.1-sol` 三计划读/算/写/复核成功，均值 20；重连保持同一 execution。Windows 与 Android 只读查看同一最新任务、群聊三 Dot 记录与深色/英文/reduced-motion 的原生候选复测通过。
- reduced-motion 下 size animator 直接使用静态 child，修复已复现的 RenderAnimatedSize 自布局通知异常；Windows 玻璃标题栏为系统按钮预留宽度，解决 Flow 按钮被遮挡。Flutter analyze 与 36 项辅助测试通过（最后两处 UI 修复的全量复检留到验收模块）。

## 2026-11-06 Flow：真实验收与构建

- 已完成紧凑 32px 节点/56px 行高的双端真实视觉检查，采用审核文案与四状态色，Plan 完成收起/手动展开、Android 横竖屏/返回、Windows 窄窗和深色 reduced-motion 复测通过。
- 真实 gpt-6.1-sol 完成私聊读/算/写/复核、三 Dot 搜索/浏览/报告、原生计划、clarify、terminal 审批返回 63、不存在命令 exit 127。控制与重连分段验收，Windows `/new` 清图，Android 重新读取同一新会话确认无旧图。
- 初始 Windows Plan 的 reduced-motion 断言及 Android 固定同名 `/new` 测试误判均保留记录；修复/纠正后分别复测，不重放已完成工具。详情见 docs/flowchart-acceptance.md。
- 最终 typecheck、相关 lint、39 文件/81 项服务端测试、Flutter analyze/36 项测试、Node/Relay bundle 和双端 release 构建通过。Android 构建与测试改为串行，避免生成注册器互相污染。
- 仅本地候选与提交，未 push/发布/更新正式服务。Android 真机、物理网络切换及未触发的原生异常逐项保留待验，截图和脱敏记录位于 docs/evidence/flow。

## 2026-11-06 Hermes 后端运行包：构建模块

- 固定官方 v0.22.6，使用官方发行快照、PM 和 Agent assembler 构建 Windows x64 / Linux x64 后端包；保留管理 HTTP、canonical WS、Skills/插件/MCP/Cron、Chromium、cua-driver 和 FFmpeg。无 Git、测试环境、官网、Electron/TUI/Web 前端构建输入，不打包 uv 构建缓存。
- 构建配方在 deploy/hermes-runtime-recipe.json；scripts/build-hermes-runtime.py 在目标系统构建。此前批准的长路径、webhook listener 与 Cron 审批补丁集中保存并重定位到稳定版；保留上游新的 owner/cancel 行为，不改 Agent 回合逻辑。
- Windows 包 770308773 字节，Linux 包 642321596 字节。Windows 候选已从隔离 Relay 下载并解压，真实 gpt-6.1-sol 读写文件、第二次消息和重启无重放通过。Linux 已在真实 VPS 独立目录解压/启动，完整能力旅程仍在验收。
- 尚未完成 macOS 实机与完整双系统能力回归；不标记整体验收完成。不发布、不 push，不回收已有安装/缓存/历史。

## 2026-11-06 Hermes 后端运行包：安装与分发

- Flutter 本机安装和 VPS 安装统一消费版本化后端包；去掉用户端 clone、PM 全量安装与前端构建。Relay 支持大包流式下载及 Range 续传，发布材料检查对应运行包是否备齐。
- 新账号直接使用官方打包基线，共享下载缓存但不共享可变 Python 环境；已有缓存和账号数据保持不动。Linux VPS 默认准备官方屏幕系统依赖，保留原资源策略。
- Windows 全新安装与第二账号真实模型读写、重启保留历史通过；取消下载后续传并完成安装通过。验收修复取消时文件流错误覆盖 cancelled 状态，复测已得到正确取消结果。Windows 原生 computer_use 实际写入记事本并保存、停止操作通过。
- Linux VPS 新包完成真实搜索、浏览器、代码与文件工具；官方 PM 安装带 humanize 依赖的隔离插件，真实模型调用插件与 MCP 成功。VPS 屏幕被原生内存阈值拒绝，未绕过。完整 Cron/Webhook、更新路径和平台回归继续验收。
- 仅本地修改，未发布、未 push、未清理现有安装；架构和构建流程见 docs/hermes-runtime.md。

## 2026-11-06 Hermes 后端运行包：插件环境同步

- 原生更新路径验收发现：切换运行包安装身份后，已有插件配置保留但依赖没有同步。Flutter 与 VPS 安装入口在账号准备时执行官方 `hermes pm install --extra all`，新账号匹配发行基线时不创建额外 generation。
- Windows 原生候选 4 分 08 秒旅程通过：72 条旧消息完整保留、Node 身份一致、真实读写和二次对话、runtime_probe 插件输出 1,234,567、重启不重跑、停止/退出后进程为 0。系统本机安装指针已恢复原值。
- 只模拟同一个 r1 包更换安装目录；跨版本升级未验。旧历史分页与远端文件路径的验收误判已修正。完整工程检查和平台验收结果将在独立记录中汇总。

## 2026-11-06 Hermes 后端运行包：第二账号启动

- 同一个安装的 ready 标记是共享的，第二账号可能绕过 setup 直接 start。现在普通启动也执行当前账号的官方 PM 同步，setup 内不重复准备；不新建另一套升级状态机。
- Windows 第二账号在旧运行目录安装带依赖插件后，用已完成准备的新目录启动，实际 gpt-6.1-sol 读写、第二次回答与插件输出通过；9 条历史和身份保留，重启不新增消息，退出进程为 0。2 分 34 秒全旅程通过，原指针恢复；仍仅为同 r1 包路径切换，不冒称跨版本升级。
