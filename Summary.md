# nekodot

面向非技术用户的多智能体产品。Web/PWA 通过 Relay 连接用户自己的 Node，
Node 以官方 CLI/API 管理 Hermes。Node 是本地业务状态的唯一数据源。

## 架构

- apps/web：React 用户界面。
- apps/relay：连接与路由入口。
- apps/node：本机代理与 Hermes 集成。
- 每个 Bot 对应独立 Hermes profile；单 agent 的模型、上下文、记忆、技能和工具循环直接采用 Hermes 原生实现。nekodot 只处理产品状态与群聊接力路由。
- packages/protocol：Zod 边界协议及 TypeScript 类型。
- packages/fake-hermes：仅测试使用的真实事件回放服务。
- scripts：开发和真实 Hermes spike。
- docs/references、design：完整技术及视觉原件。

## 更新记录

### 2026-10-28 / Hermes 原生单 agent 边界

- 确认一个 Bot 对应一个 Hermes profile；私聊原文通过官方 Runs API 交给 Hermes，模型、上下文、记忆、技能及工具循环均由 Hermes 实现。群聊仅在产品层选择成员并顺序交接。
- 新建 profile 不再传入 --no-skills，保留官方默认技能初始化；将此边界写入 AGENTS.md 和 README。
- WSL Ubuntu 24.04 中通过产品 CLI 封装在隔离 HERMES_HOME 实际创建两个 profile，各初始化 58 个技能和独立会话/记忆目录。Node 24 的 lint、typecheck、19 项现有场景与 Node 构建通过；既有 profile 和历史保持原状。

### 2026-10-27 / 0.0

- 创建独立产品目录，保留原 PDF 和完整 HTML，提取 19 页伴随文本。
- 建立参考索引、凭证示例与工作约定。真实模型接入尚未验收。

### 2026-10-27 / 0.1

- 建立 Node 24 / pnpm workspace、严格 TS、lint/format、构建和 CI。
- 增加中英基础页、Relay health、Node 入口和真实浏览器场景。
- 依赖安装、类型、构建及基础页桌面/手机实际浏览器检查通过。

### 2026-10-27 / 0.2

- 按 PDF 第 7 节实现实体、信封、全部 RPC、持久事件和实时流 Zod 协议。
- 添加真实私聊、审批、群成员、历史查询、密钥输出边界样例。
- Message 工具状态统一 streaming；裁切字段按实测事件及 PDF 邻文定稿。

### 2026-10-27 / 0.3

- 新增隔离 CLI 启动、真实 Runs API 客户端与 SSE 边界解析，不改 Hermes 核心。
- 自定义 provider 的真实文本、工具、审批允许/拒绝、执行中停止五项通过。
- 录制真实 SSE、审批/停止响应、pending/final 状态及测试文件结果；七项调查完成。
- 自有 Chromium CDP 实际连接成功；最终临时现场使用持久缓存且已重新进入确认。
- 修正真实 SSE 的 JSON event 读取、先读后改审批场景；失败资料本地保留。

### 2026-10-27 / 0.4

- 实现仅测试的 loopback HTTP 回放服务：health、创建、SSE、查询、stop、approval。
- 用真实 fixture 驱动文本、工具关联、审批暂停/允许/拒绝、取消及 profile 隔离。
- 实际 Node HermesApi 通过 HTTP 消费回放；fake-hermes 只列为根 devDependency，产品不导入。
- 业务协议、HTTP 回放与分块 SSE 场景共 13 项检查通过；不以其替代真实模型结果。

### 2026-10-27 / 0.5

- 从 0.4 提交全新检出，安装依赖、lint、类型检查、13 项测试和全部构建依次通过。
- 实际 Edge 再验桌面、中英切换和手机页面，保留并人工查看两张截图。
- 全新构建的 Node 入口与 Relay HTTP health 实际启动通过；再次确认 WSL 审批现场保留。
- 完成验收记录与开发入口说明。原 HTML 视觉核对仍受查看方式限制，未虚报通过。
- 初始私有 GitHub 归档已上传；后续模块均保留为本地提交，没有推送真实配置或运行现场。

### 2026-10-27 / Phase 1.1

- 实现 Relay 账号、JWT、配对码、节点凭证和解绑；不保存聊天正文。
- 实现 client/node WebSocket、请求路由、所有权检查、在线通知和心跳。
- 协议增加 HTTP 边界、node.status 和实时文本 offset；安装既定 Phase 1 依赖。
- 真实 HTTP/WebSocket 旅程通过：注册登录、配对单次使用、跨账号隔离、节点解绑。

### 2026-10-27 / Phase 1.2

- 新增本地 SQLite 状态、事务事件流、稳定消息顺序和运行游标；数据目录默认 ~/.nekodot。
- 新增真实 HTTP 配对凭证保存和 Relay 出站连接，按 1/2/4 秒至 30 秒重连。
- 新增隔离 Hermes 生命周期管理，所有 CLI 显式绑定 HERMES_HOME 与官方 PM runtime。
- Node 24.22.1 的实际 HTTP/WS 配对、凭证落盘、SQLite 关闭重开及同步检查通过；完整浏览器旅程持续验收中。

### 2026-10-27 / Phase 1.3

- 新增提供方与 bot 服务：节点仅保存密钥后四位元数据，完整密钥写入 Hermes 托管 .env。
- 支持 OpenRouter、自定义 API、hub 模型目录、nk-xxxxxx profile 与独立私聊会话。
- bot 名称、角色、头像、模型可更新；逻辑归档保留历史和 profile。
- 通过真实 HTTP 录制回放和 Edge 网页完成首次提供方配置、热建 bot 和私聊；真实 provider 网页验收单独记录。

### 2026-10-27 / Phase 1.4

- 联通 Node 命令入口、同会话消息去重、真实 run、SSE 文本快照、工具、审批、停止与原生 steer。
- steer 保持 runId，保留已有文本和工具，后续使用新回复段；终态 pending_steer 提示用户并提供放回输入框。
- 分离 SSE 与普通请求超时，使用 Last-Event-ID 续接；同步重发 activity，恢复时查询已有 run，不自动重跑。
- 测试回放加载真实 steer 录制，断开 SSE 不推进审批，重新连接只续传后续事件。
- Node 24 检查及 Edge 旅程通过；WSL 真实网页文本、允许/拒绝、同 run steer（一次工具、一次文件效果）、停止和节点重启均通过。

### 2026-10-27 / Phase 1.5

- 以账号、配对、团队、私聊、bot、设置功能模块替换基础展示页；使用 React 19、Tailwind v4、motion 和 Zustand。
- 落地设计 tokens、本地参考字体、八色猫耳头像、工作/流式/审批动效、中英词典、浅深色和 reduced-motion。
- 按 nodeId 隔离同步，首屏 snapshot、重连 since、超 1000 条重新 snapshot；实时 offset 与完整文本快照合并。
- 实际 Edge 完成注册到私聊、刷新/重连/节点重启、补充指令、停止、历史分页及响应式截图；修正手机输入框裁切和页头按钮重叠。
- 双电脑网页旅程补测配对与切换隔离、解绑、退出重登；发现并修正无 body 请求错误声明 JSON 导致解绑失败。

### 2026-10-27 / Phase 1.6

- 补齐真实整栈 SSE/state 与脱敏报告；单独记录真实模型和 HTTP 回放，保留 WSL 验收现场。
- 自动化覆盖实际 Edge 双语言、三尺寸、主题、审批刷新/节点重启、断流去重、同 run steer、停止、双节点和历史分页。
- 增加提供方托管文件的实际切换检查；切换 provider 后仅保留当前 key，稳定保留独立 API_SERVER_KEY。
- 更新启动、调研、阶段说明及 CI（包括 Edge 旅程）；当前工作区 lint/typecheck、17 项场景、构建和 2 个完整浏览器旅程通过，全新检出待最终复核。

### 2026-10-27 / Phase 1 终验

- 从 3816562 全新检出，未复制 .env 或 node_modules；Node 24 下 frozen install、lint、typecheck、17 项测试、构建和 2 个 Edge 旅程全部通过。
- 隔离网页端口 4328 确保浏览器实际使用新检出；真实模型保持此前自定义 API 独立报告，不以回放替代。
- 核对三种尺寸的真实历史截图、工具与审批画面；保留原参考视觉核对限制及 OpenRouter 未实际付费调用的边界。
- Git 跟踪资料未发现真实 provider 配置值。所有模块只本地提交，未推送；参考、profile、历史和临时验收资料均保留。

### 2026-10-28 / Phase 2 Node 与接力

- SQLite 前向升级至 v2，保留既有私聊，新增群组/唯一群会话和持久接力状态；建群与对应会话事件同事务提交。
- 群组支持 2–6 位活跃成员、主答、编辑和逻辑归档；活跃群组成员不能归档 Bot。
- `group-routing.ts` 按 PDF 模板提供成员名册、新群文本与稳定群 session；只从最终文本解析成员提及，按群串行、最多六回合，失败继续。
- 复用私聊 SSE、审批、停止、原生 steer；steer 接受后清空待执行队列，恢复时查询原 run，不重跑已完成工具。
- 实际自定义 API 录制 group-*.sse/state；自动化仅测试注入选择录制资料，产品无 fake 开关。
- Node 24：8 文件 19 项场景及构建通过，覆盖私聊回归、数据库升级、群 CRUD、定向与 Bot 接力、上限、失败继续、节点恢复、steer、停止。

### 2026-10-28 / Phase 2 Web

- 团队新增群列表、群创建/编辑/归档面板，支持 2–6 位成员和主答选择；复用已有私聊消息与审批组件。
- 群聊按作者显示名称、handle 与头像，提供 @ 成员选择器、交接标签、接力进度及全部停止；运行中仍通过原生 steer 补充指令。
- Web 保存完整 activity，保留归档 Bot 的历史作者身份；修正新建 Bot 后进入会话时读取旧状态的问题。
- Edge 完整群旅程通过：创建、接力、审批刷新与节点重启、断线、steer、停止、编辑、归档；人工查看 390/768/1440px、中英、浅深色与 reduced-motion 截图，无横向溢出。

### 2026-10-28 / Phase 2 整体验收

- 自定义 API 真实网页验收确认主答、成员顺序、Bot 接力、自身/非成员忽略、六回合上限、同 run steer、停止、失败后继续及重启历史；最新 WSL 构建复验定向群聊、刷新、编辑和归档。
- 补充真实故障观察：上游重试分别超过 240/120 秒页面等待，最终失败及后续 Writer 完成均从实际 run 和网页另行核对，不声称即时响应。
- 完整 Edge 回归暴露并修正 Hermes 错误码直接越过 RPC 枚举的问题；HTTP 错误映射为类型化 NodeFault，网页保留被拒绝的补充草稿，可重发到原 run。
- 补验跨群并行、审批中编辑成员与节点重启后原队列继续；群成员快照只在下一条新消息更新。Node 24 的 19 项场景和 3 条完整 Edge 旅程已通过，全新检出终验另记。
- 真实补录工具前进度文本及工具预览中的 @writer：最终回复无提及，只有一个 run。Hermes 未总是单发 interim 事件，故工具前文本按 commentary 保存，避免界面误显示交接，不改写旧历史。
- 真实取消前可能先发 tool.completed(error=true)；持久保存本地停止意图，使该工具卡显示已停止。回放按真实取消序列验证，保留此前已完成工具结果。

### 2026-10-28 / Phase 2 全新检出终验

- 基于最终代码提交 d96712f 新建独立检出；不复制根 .env 或 node_modules，Node 24.22.1 / pnpm 10.34.5 的 frozen install、lint、typecheck、test、build、Edge E2E 全部通过。
- 8 个测试文件、19 项场景、3 条 Edge 旅程通过；隔离 Web 端口 4358，未复用开发页面。报告为 docs/evidence/phase2-clean-checkout-report.json。
- 真实自定义 API 与回放验收分别记录；最新真实停止、非最终提及忽略和响应式页面均留图。提交资料未发现本地 provider 配置值，临时现场、参考资料、profile 与历史全部保留，只做本地 commit。

### 2026-10-28 / Phase 3 本地入口、Relay 分发与多端验收

- 增加 Relay 安装器及 Node 单文件下载接口；Node 入口打包为独立 CJS，Relay 镜像只包含服务代码、生产依赖和分发文件，不携带源码检出。
- 增加 Dockerfile/Compose 部署资料，在 VPS 的专属 nekodot 项目中更新 Relay 镜像；仍只监听 loopback，原 SQLite 数据挂载保留，其他容器和 Caddy 未重启。
- 安装器提供 Linux x64/WSL2 systemd user service、linger、独立 Node 24/Hermes home、重复安装与保留数据的卸载。检测到既有 Hermes API 端口占用后选择空闲端口，不覆盖 Phase 1 的运行现场。
- 增加 `pnpm dev:remote --ssh <SSH目标>` 和局域网访问选项；Web、API、WebSocket 和分发下载统一同源，能够复用已健康的本地 Relay 隧道，避免与 WSL 节点的持久隧道争抢端口。
- 配对页提供 WSL2 与 Linux 服务器安装命令；连接恢复时根据页面可见、在线状态触发重连和同步。
- 使用已存在的账号与 WSL 节点完成重复安装（未传配对码）、真实私聊、真实群聊定向回复、两个 Edge 客户端同步以及 30 秒断网恢复；视觉证据见 `docs/evidence/phase3-*.png`，脱敏结果见 `docs/evidence/phase3-live-acceptance.json`。
- Node 24.22.1 / pnpm 10.34.5 下 frozen install、lint、typecheck、21 项测试、全部构建和 3 条 Edge E2E 通过；远程 Relay 健康与安装器/Node 下载接口均返回正常，局域网开发页 HTTP 200。
- 尚未在手机真机、独立 VPS 节点账号或全新 WSL 配对现场验收；本轮也复用现有 WSL Relay 隧道，没有单独触发开发工具自建隧道的断线重连分支。
