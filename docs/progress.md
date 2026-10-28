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

| 模块        | 状态                 | 验证                                                                       |
| ----------- | -------------------- | -------------------------------------------------------------------------- |
| Node / 接力 | 已完成               | SQLite v2、CRUD、群 session、队列、上限、错误继续与恢复；19 项当前场景通过 |
| Web         | 实现完成，视觉复验中 | 群列表/面板、成员选择、作者、交接标签、接力计数、停止；Edge 完整旅程进行中 |
| 整体验收    | 进行中               | 真实模型核心场景已通过；全新检出和完整 Edge 回归待终验                     |

## 2026-10-28 / Node 与真实群聊

- 真实网页完成注册、CLI 配对、自定义提供方、Researcher/Writer profile 和群聊。
- 真实 lead、多个成员按序、Bot 接力、自身/非成员提及忽略、六回合停止、同 run steer 与 stop 均通过，见 `phase2-live-report.json` 与 group fixtures。
- steer 保持 runId，工具执行和测试文件效果各一次；stop 后 cancelled，未执行成员未启动。Node 重启后历史存在。
- `group-failed.sse` 来自隔离连接故障的真实 `run.failed`；此前无效模型请求在上游 503 重试期间超出浏览器等待，现场保留，不能将该超时写为一次成功的即时验收。
- 已使用 Node 24 跑通 19 项场景与构建，包含 Phase 1 数据库实物升级、原私聊回归、群编辑/归档、成员顺序、错误继续、六回合、原 run 恢复、steer 和停止。
- 原 HTML 继续只作静态参考，没有改用其他通道执行原稿；新页面视觉验收独立进行。
