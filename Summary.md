# nekodot

面向非技术用户的多智能体产品。React 网页及 Windows / Android 客户端通过 Relay 连接 Node，
Node 以官方 CLI/API 管理 Hermes，并保存业务状态。原生 App 当前只连接远程服务器，不运行本地 Hermes。

## 架构

- apps/web：React 用户界面。
- apps/client：共用 React 界面的 Tauri 2 Windows / Android 宿主。
- apps/site：双语静态官网，无构建步骤。
- apps/relay：连接与路由入口。
- apps/node：本机代理与 Hermes 集成。
- 每个 Bot 对应独立 Hermes profile；单 agent 的模型、上下文、记忆、技能和工具循环直接采用 Hermes 原生实现。nekodot 只处理产品状态与群聊接力路由。
- packages/protocol：Zod 边界协议及 TypeScript 类型。
- packages/tauri-plugin-nekodot：Android FCM、生命周期、返回键与文件分享桥接。
- packages/fake-hermes：仅测试使用的真实事件回放服务。
- scripts：开发和真实 Hermes spike。
- docs/references、design：完整技术及视觉原件。

## 更新记录

### 2026-10-29 / 官网

- 新增 `apps/site` 双语静态官网：首屏产品窗口与手机叠放、私聊审批与群聊接力的脚本化回放、五组功能展示、能力格、原理图、三步开始与路线图；中英文与深浅主题可切换，截图随主题替换。
- 截图取自演示数据下的真实界面（2x WebP 约 1.2MB）；字体随站点自带，不加载外部资源。eslint 为官网脚本声明浏览器环境，全仓 lint 恢复通过。

### 2026-10-29 / UI 详情与扩展中心

- Bot 详情改为右侧滑入的卡片面板，标签用分段滑块；Skills/插件页、详情与导入弹窗、资料库文件卡统一标题字重、圆角、阴影和悬停反馈。UI 改版 U0–U7 至此完成。

### 2026-10-29 / UI 屏幕接管面板

- 屏幕面板按画板 06/07 改为常深色：实时徽标、成员头像切换、接管时 accent 控制条与呼吸描边，桌面右侧滑入、手机自底部滑入；接管逻辑未改。

### 2026-10-29 / UI 设置与登录

- 设置页改为卡片式单栏，提供方滑块切换、主题开关与底部解绑确认，并入原生端通知设置；复制操作统一走原生安全剪贴板。
- 登录/注册页改为品牌区 + 表单左右分栏，猫耳 bot 弹入漂浮；旧页面样式迁出 `style.css`。

### 2026-10-29 / UI 添加电脑

- 添加电脑页按画板 05 重做：步骤条、可滑动选中的电脑类型卡、编号步骤、终端风格命令框与高亮配对码。
- 等待卡带倒计时环与就地重新生成，配对成功时播放头像回弹与彩点散开后回到团队。

### 2026-10-29 / UI 新建与编辑面板

- 新建/编辑 bot 与群组改为手机底部面板（可下拉关闭）、桌面居中弹窗；头像实时预览、颜色选中环滑动、成员卡片与主答标记。
- 统一全站表单字段样式；新建按钮按 PDF 显示“创建 <名字>”，E2E 同步更新按钮名称。

### 2026-10-29 / UI 消息流

- 私聊与群聊消息按作者分组、加入介绍卡与时间分隔；bot 回复渲染安全 Markdown 并可复制，离开底部时提供“回到最新”。
- 工具卡、审批卡、运行状态条与自适应输入框按画板 02/03 重做；@ 成员浮层支持键盘选择，接力进度改为 6 段进度条。

### 2026-10-29 / UI 首页、侧栏与命令面板

- 桌面侧栏改为浮起选中卡片、电脑状态胶囊、搜索入口与分段导航；bot/群行显示最后消息、时间、工作状态和“需要你”。
- 手机首页按画板 01 改为“团队”标题与卡片列表，右下角新建按钮展开 bot/群组两项；会话推入/返回动画只由导航触发。
- 新增 ⌘K / Ctrl+K 命令面板；同步后预取各会话最近消息，修复列表恒显示“还没有消息”。

### 2026-10-29 / UI 基础层

- 设计 tokens 增加阴影层级、悬浮/按下色、遮罩与统一缓动；按钮、图标按钮、标签、快捷键标识统一交互反馈。
- 新增状态点、群成员色点、分段控件等共享组件，并补齐设计稿图标集。

### 2026-10-29 / UI 画板导出

- 九块设计画板静态展开并由 Edge 截图为 `design/01-home.png` … `09-tokens.png`，未执行原稿脚本；后续 UI 改版逐屏对照这些图。
- 用户要求在原稿基础上重新设计：更高端、大气、简洁、交互性强并配合恰当动效；原稿 tokens 与 PDF 动效数值作为下限保留。

### 2026-10-29 / Bot 跨私聊与群聊共享 Hermes 会话

- 同一 Bot 的群聊 Run 复用该 Bot 私聊的 Hermes `session_id`，使 Hermes 原生 transcript 在群聊与私聊之间连续；不添加 nekodot 自建记忆层。
- 保留群聊名册、角色提示及新增群聊文本的既有路由。旧 `nk_grp_*` session 和历史不迁移、不改写。
- Node HTTP 集成与 Edge 旅程验证私聊 → 群聊接力 → 私聊均使用同一 session；目标 Node 测试和群聊 Edge 旅程通过。

### 2026-10-28 / 私聊界面与消息发送恢复

- 修复 Bot 弹窗滚动与固定操作区，调整侧栏宽度、logo 对齐、设置入口、语言布局和电脑选择器；清除重复的 Team 标题。
- 提供方设置通过 API URL/Key 获取模型目录；Bot 创建时可选择模型或手填 ID，并为每个 profile 提供 Hermes 工具审批等级及允许一次/本会话/始终允许/拒绝选项。
- 区分节点在线状态与浏览器 Relay WebSocket 就绪状态；网页唤醒或重连期间发送会等待 hello 握手，草稿保持不变。
- 每次重连使用独立 socket 引用，旧连接回调不会清理新连接；短暂断线不再错误地把仍在线的节点标为离线。
- Edge 真实浏览器旅程覆盖 Bot 创建、审批设置、群聊、唤醒后立即发送、节点接收次数为一次和断线保留草稿；21 项自动化测试与 3 条 Edge 旅程通过。

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
- 新增服务器首次安装时补装 `libatomic1` 后，通过独立 Unix 用户和 systemd linger 安装 Hermes/Node；真实自定义 API 私聊成功，Node service 重启后历史保留，断开反向 SSH 通路 30 秒后自动重连。
- 新服务器暴露 Hermes PM 的 `libatomic.so.1` 前置依赖，安装器现会在下载前明确检查并提示 Ubuntu/Debian 安装 `libatomic1`；包含该检查的新 Relay 镜像已部署，Relay health、安装器和 Node 单文件下载均验证成功。
- VPS 节点验收期间通过本机 SSH 反向隧道访问 loopback Relay；当前节点在线依赖该隧道持续运行，尚未配置新服务器到 Relay 的持久服务器间 SSH 身份。PM 对可选 `cua-driver` 报缺少 `libXi.so.6`，屏幕控制未纳入本阶段验证。
- Edge 页面恢复时改用浏览器允许的 WebSocket 正常关闭码；重连同步成功后恢复节点在线状态，私聊 E2E 覆盖页面返回、WebSocket 重建和无浏览器异常。
- 最新代码在独立检出通过 frozen install、lint、typecheck、21 项测试、build 与 3 条 Edge E2E；现场截图和首次安装依赖记录保留在 `docs/evidence/`。
- 尚未在手机真机后台/唤醒流程和全新 WSL 配对现场验收；开发脚本自建 SSH 隧道的断线重连分支也未单独触发。
- Phase 3 提交后另建独立本地克隆，不复制 `.env`、账号或 `node_modules`；Node 24.22.1 / pnpm 10.34.5 的 frozen install、lint、typecheck、21 项测试、build 和独立端口 4368 的 3 条 Edge E2E 全部通过。

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

### 2026-10-29 / Side Phase Bot 详情与扩展中心

- Web 增加 Bot 详情、原生记忆和资料库三部分；展示 Hermes profile 定时任务和运行记录，编辑 SOUL、MEMORY、USER，调用原生 `/refine` 并呈现操作状态。
- Skills 与插件页面读取当前节点 Hermes 目录，支持搜索、分类、原生说明、Bot 安装状态、启停、Git 安装、本地文件/目录/ZIP 导入及插件配置。secret 由 Hermes profile 的 `.env` 保存，界面不回显完整值。
- 文件卡片接入私聊与群聊，资料库支持搜索、类型筛选、预览、下载、来源消息及历史补录；文件内容留在 Node，Relay 只做认证传输。
- Edge 完整浏览器旅程覆盖详情/记忆保存、资料库预览下载、Skills 内容与启停、插件目录及 390/768/1440px 页面；真实 Hermes 与自定义 API 的能力证据见 `docs/evidence/sidephase-*.png`。

### 2026-10-29 / 公开仓库 README

- 以 `README.draft.md` 为底稿重写 `README.md`，面向 GitHub 公开访客：Logo（浅深色两版）、徽章、定位与主图、“为什么是 nekodot”、功能、工作原理与数据归属、快速开始、开发、路线图、致谢与许可证。
- 原工程 README 的环境、命令、本地运行、远程 Relay、节点数据与测试策略整理到 `docs/development.md`，内容不丢失。
- 按代码与部署文档核对说法：当前为开发者预览，需要自托管 Relay（仅 loopback，经 SSH 隧道访问），节点支持 Linux x64 与 WSL2 Ubuntu 24.04 x64。仓库尚无 LICENSE，需在公开前选定。

### 2026-10-29 / 产品 README 草稿

- 新增 `README.draft.md`，以产品介绍、使用场景和首次使用流程说明 nekodot，保留现有工程 README 供审阅时对照。
- 配入新版桌面群聊、手机首页和快捷命令面板三张实际运行截图，明确演示数据与真实模型验收的区别。
- 说明一个 Bot 对应一个 Hermes profile、私聊与群聊、记忆与定时任务、资料库、Skills/插件，以及节点部署和数据归属；当前支持范围以既有实现和阶段记录为准。
- 本轮仅更新文档；人工查看所选截图，核对草稿 14 处图片、文档与章节引用，全部可解析，未新增模型调用或运行时功能。

### 2026-10-29 / Phase 4 原生能力与安装

- 增加按 Bot 的原生 display 状态、启动、停止、观察和控制权适配；复用管理连接与 Operations，不改变 Hermes agent、工具或审批。
- 配置 profile 的有界面浏览器、1440×900 和 computer_use；sync 能力按实际宿主平台返回。安装器增加 `--with-computer`，通过官方 CLI/PM 安装驱动和屏幕，补齐实测缺少的 Chromium 系统音频库。
- 隔离 Ubuntu 环境已启动两个独立原生屏幕，采集脱敏状态；Node 24 typecheck、既有 21 项测试和构建通过。真实模型及恢复仍继续验收，详见阶段记录。

### 2026-10-29 / Phase 4 Relay 屏幕通道

- 增加认证 `/api/tunnels`、60 秒单次票据、浏览器与节点出站 WebSocket 配对；屏幕会话按账号、节点和 Bot 隔离，解绑关闭通道。
- 二进制转发保留主动关闭、异常断流和原生 control-taken 的差异，不记录画面和输入；真实 Edge 已通过 Node 看到原生 Xfce。
- 实际 HTTP/WS 测试覆盖归属、离线、单次票据、双向字节、4000、1000、1006、重连与解绑。回放服务新增真实原生状态录制支持，作为离线测试依赖。

### 2026-10-29 / Phase 4 屏幕界面与原生接管

- 私聊顶栏、Bot 详情和群聊接入 noVNC 屏幕；桌面为 480px 侧栏，窄屏为全屏面板。沿用现有视觉组件与中英词典，提供只读观看、接管、交还、强制交还、缩放和键盘输入。
- 群聊按执行成员、最近作者、主答选择初始屏幕，打开后固定目标。接管不调用停止；关闭画面与停止任务分离，断线不自动取得控制权。
- 真实 Edge 双客户端验证轮流接管、只读输入禁用、断网后保留原生 lease、身份丢失后显式强制交还，以及 390/768/1440 布局。修复浏览器离线后仍可点击接管的问题。
- 真实模型通过原生浏览器填表，同一 run 内人工输入后交还，Bot 验证并提交一次；computer_use 经原生审批操作 nano 保存测试文件，实际文件内容核对通过。Runs 使用的 computer_use 配置已改为原生 `platform_toolsets.api_server`。整体恢复与独立安装验收继续记录。

### 2026-10-29 / Phase 4 整体验收与恢复修正

- 真实 SSH 断流暴露 Relay 提前丢弃 viewer 会话的问题：节点暂时离线保留身份映射，解绑才清除；实际 HTTP/WS 场景与真实恢复均验证通过。
- 修正原生 Operations 完成后屏幕启停按钮仍被锁定的问题，补充真实 Linux 停止/再启动旅程；窄屏画面按 1440×900 比例显示，减少多余黑边。
- 独立 Linux 用户完成下载安装、重复安装、无权限提示与保留数据停用；稳定版 Chromium 安装入口改为官方 `hermes pm install chromium`。
- Node/管理后端重启及 SSH 中断后，历史、run 数量、测试文件和两个 profile 浏览器资料保留；不自动新增模型执行。真实模型验证了 profile 隔离与重启后浏览器资料可读。
- 补充真实同 run SSE/state、12 种 Edge 布局及桌面/群聊/接管截图；公开文档同步屏幕用法和原生窗口生命周期限制。详见 `docs/phase4-acceptance.md`，最终清洁检出结果另记。

### 2026-10-29 / Phase 4 最终代码检出复核

- 独立检出更新到代码提交 `cabd55a`，未复制 `.env` 或 `node_modules`；Node 24.22.1 / pnpm 10.34.5 的 frozen install、lint、typecheck、11 文件 23 项测试、build 和 4 条 Edge 旅程全部通过。
- 真实 Linux 屏幕旅程独立通过，包含双 viewer 原生接管、离线恢复、身份丢失、强制交还、刷新、主动关闭和停止/再启动。普通 E2E 对此明确 skip，不把缺少私有现场算作真实通过。
- 真实接管 fixture 核对为单一 run、5 次工具开始/完成及 completed 终态；文档引用可解析，提交内容未包含本地提供方配置值。验收结果见 `docs/evidence/phase4-clean-checkout-report.json`。
- 现有 UI 改版的未提交文件与所有私有验收现场保留；本阶段按模块本地提交，未推送，也未重启其他产品或整机。

### 2026-10-29 / Side Stage 2 客户端基础

- 新增 `apps/client`，以 Tauri 2 打包现有 React 界面，支持 Windows x64 与 Android 10+；客户端只连接远程 Relay，不运行本地 Hermes。
- HTTP、业务和屏幕 WebSocket、文件及扩展导入共用构建时 HTTPS 地址；App 资源使用独立构建目录，不覆盖 Web 回归产物。新增原生保存/选择/分享、PDF.js 预览、进程内草稿和应用恢复接入。
- Windows 实际生成 NSIS 测试安装器并打开本地资源，验证安全 origin、关闭留驻和单实例恢复；Android x86_64 测试 APK 在独立模拟器安装打开，原生通知/生命周期桥接命令可达且没有水平溢出。
- Firebase 配置、产品域名和 Android 真机尚未提供；目前测试包只验证打包与宿主能力，不作为可连接公网的正式产品包。最终构建与验收继续记入阶段记录。

### 2026-10-29 / Side Stage 2 产品服务与通知

- 新增独立产品 Compose、Caddy 路由模板和 Node 服务说明；产品 Relay 与 Node/Hermes 使用独立目录、数据库、系统用户和 loopback 端口。Node 直接连接同机 Relay，不依赖开发电脑隧道；既有测试环境及其他产品保持运行。
- Relay 接入标准 CORS、认证设备注册/注销、Firebase Admin 和安装包下载入口；缺少正式安装包时返回 404。通知只携带节点、会话、事件标识与通用类型，不保存聊天正文。
- Node 持久保存待确认通知，连接恢复后发送；审批、完成和失败来自实际 run 状态，群聊在接力结束时发送一次，主动停止不发完成提醒。
- 产品环境使用现有自定义 API 实际完成私聊与两成员定向群聊，收到一条私聊完成及一条群聊完成通知；Node 服务重启后 Bot 与历史保留。该结果经临时验收通道取得，不作为公网 HTTPS、原生 App 或 FCM 投递通过。
- Windows 系统保存中文文件后写入/读回一致；Android 模拟器系统文件保存/选择与中文名、后台返回和进程内输入保留通过。域名、Firebase 和真机缺失的项目继续明确待验收。

### 2026-10-29 / Side Stage 2 原生平台与调试构建

- Android arm64 调试 APK 编译通过，实际产物包含 arm64-v8a；标准构建入口支持在无 Firebase 文件时构建调试宿主，保留明确的通知不可用状态，release 仍要求真实配置与签名。
- Android 模拟器实测系统返回进入后台、返回后保留原进程，以及中文文件的系统分享 chooser；没有选择外部应用或发送文件。Windows 系统文件保存已读回核对。
- 本地私有目录生成首个 Android 发布签名密钥及构建环境参数，不进入 Git、不打印密码，也未发布测试地址安装包。用户确认域名和 Firebase 稍后提供，相关联网、推送与正式交付项目继续待完成。
- 独立检出已完成 frozen install、lint、typecheck、24 项场景、build 和 4 条 Edge 旅程；本模块提交后的最终检出复核继续记录。

### 2026-10-29 / Side Stage 2 最终可执行检查

- 独立检出更新至 `fa6e675`，未复制私有配置或原依赖；Node 24.22.1 / pnpm 10.34.5 下 frozen install、lint、typecheck、12 文件 24 项场景、build 与 4 条 Edge 旅程通过。缺少私有现场的真实屏幕旅程明确 skip。
- 同一独立检出通过标准入口生成 Windows x64 NSIS 调试安装器和 Android arm64 调试 APK，不依赖原工作区的 native target 或 node_modules；Android 实际包含 arm64-v8a。
- 新增 `docs/side-stage-2-acceptance.md` 与机器结果，将原生宿主、真实产品服务、离线回归及待联调部分分开记录。域名/Firebase 已由用户确认稍后提供，正式包、FCM、真机和跨端远程闭环仍待完成。
- 本阶段所有模块仅本地提交，既有未提交 UI、历史、profiles、原参考资料及验收现场保留；未推送、未重启其他应用或整机。

### 2026-10-29 / Side Stage 2 公网、Firebase 与预览交付

- 用户提供域名及 Firebase 配置后，独立产品 Relay 接通正式 HTTPS/WSS；Caddy 原站点完整保留，只 reload 新增路由，其他服务没有重启。产品 Node 继续直接连接同机 Relay。
- 实际请求确认 Firebase 服务账号最初缺少消息发送权限；用户修正 IAM 后，真实 FCM token、App 自动设备注册、模型任务完成后的后台系统通知及点击定位会话均在独立 Android 模拟器通过。
- 构建并发布 Windows x64 release NSIS 和 Android arm64 签名 release APK 0.1.0。Windows release 与 Android 模拟器均从本地内嵌资源直接访问公网产品服务、完成真实私聊，不依赖 Vite 或 SSH 转发。
- 原生视觉检查发现 Android 15 系统栏覆盖标题；宿主增加 WindowInsets 处理，重建后实际确认系统栏与页面分离。完整手机软键盘、锁屏与划掉后的 FCM、屏幕接管及 Windows 干净用户安装仍明确待验收。
- 更新 `docs/side-stage-2-acceptance.md` 和脱敏截图/机器结果；起始全仓 lint、typecheck 与 24 项测试通过。收尾新增的并行 `apps/site` 未跟踪文件导致全仓 lint 报错，已独立记录并限定本次检查范围。私有凭据、签名资料、原始日志和其他并行 UI / 网站工作不提交。

### 2026-10-29 / 0.1.0 官网与发布准备

- 将 Claude 的双语静态官网部署至 https://nekodot.com，复用产品 Relay 的 WEB_DIR 与只读目录挂载；保留原有 API、WebSocket、下载和其他站点服务。
- 官网新增 Windows / Android 下载、真实 App 上手流程与 MIT 说明；README、仓库链接及包元数据统一到 AR307/nekodot，新增标准 MIT LICENSE。
- Edge 完成 12 种尺寸 / 语言 / 主题检查；lint、typecheck、24 项测试、build 和 4 条产品 Edge 旅程通过，真实屏幕旅程因没有本次测试现场明确跳过。公网真实模型回复复核通过。
- 原 GitHub main 为 Hermes 源码，重命名为 hermes-reference 保留；产品 main 与 0.1.0 正式发布继续执行，安装包及最终发布核对另记。

### 2026-10-29 / 0.1.0 安装包与发布验收

- Windows x64 NSIS 与 Android arm64 签名 release APK 重新构建到 0.1.0；NSIS 包包含 MIT 许可页，Android v2 签名通过且只包含 arm64-v8a，Windows 未带 Authenticode 签名。
- 两个最新包已上传官网，Edge 实际点击两处下载并保存，文件名与大小正确；之前的产品下载包在服务器另存保留。
- 从源代码独立导出、不复制私有配置或 node_modules，frozen install、lint、typecheck、24 项测试、build 和 4 条 Edge 旅程均通过；真实屏幕回归缺少本次私有运行现场，明确跳过。
- GitHub 已转为公开，main 展示产品完整源码，hermes-reference 保留原 Hermes 历史；官网主页信息及 README 链接已更新。v0.1.0 使用本模块提交与双端安装包发布，验收范围见 docs/releases/v0.1.0.md。
- 复核共享服务器其他三个容器身份、启动时间及重启次数均未变化；没有提交密钥、运行数据、Firebase 服务端凭据或签名资料。

### 2026-10-29 / README 发布徽章显示修正

- Edge 复现 GitHub README 的 developer preview 外部徽章未显示；图片源直接请求可返回 SVG，页面中的 GitHub 图片代理未能正常展示。
- 改用仓库内置的 0.1.0 SVG 徽章并链接到对应 Release，不再依赖该外部静态状态图片。此变更只影响 README 展示，不修改客户端和服务器。

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

- 提问卡与执行审批分开建模，接入 Hermes 原生 clarify；刷新、Node 恢复仍回答原 run，等待期间保留草稿。断流明确显示重连，协议错误与终止原因可见，不自动重跑。
- 隔离真实模型提问回答完成，脱敏 SSE 与 run 状态入库；Edge 实际旅程覆盖问题中刷新、Node 重建、回答及后续聊天。真实模型与回放浏览器证据分别标明。
- 最新 typecheck、15 文件 / 27 项测试及 Flutter analyze 通过；完整 Edge 4 项通过，Linux 实屏项跳过。详见 docs/side-phase-3-progress.md。线上未部署，新客户端未切换。

## 2026-10-30 / Side Phase 3 邮箱验证与会话基础

- 注册验证码、旧账号补验、密码重置/修改及可撤销登录已接入实际 SMTP。Web 更新账号流程；退出和密码变更撤销服务端凭证，关闭业务与屏幕通道并解除通知绑定。
- 本地 SMTP 验证码收发、错误次数/重发/重放、旧账号身份保留、退出后 401 与双向屏幕 4401 通过；默认不信任客户端伪造转发头。账号检查结果与未覆盖范围记录在 docs/side-phase-3-accounts.md。
- 最新 15 文件 / 27 项测试通过。外部 SMTP 与可信代理部署复核待做；没有部署到线上，不以本地邮件测试代替真实邮箱验收。

## 2026-10-30 / Side Phase 3 外部 SMTP 收码

- 独立 Relay 使用本地私有 SMTP 配置完成 TLS 认证与实际发信。发件域名未验证的 550 拒绝由用户在邮件平台修正，未绕过 TLS 或改用其他发件人。
- 用户从真实邮箱收到验证码并通过本地文件提供；注册、密码登录、验证码单次消费及服务端退出后 401 均通过。邮箱、密码、验证码和原始响应不入库。
- 补充账号验收报告与脱敏证据。外部重置/旧账号补验、生产来源 IP 与原生完整账号页面仍分别待验收；不部署或推送。

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

- Skills / 插件正确按种类、稳定标识及 profile 读取实际说明、文件列表、图标和仓库；简介直接预览，完整内容独立左推页面并保留返回位置。补齐 Flutter Windows 目录导入入口，Web 搜索高亮改为 80ms。
- 隔离官方 Hermes 实际录制并经产品适配器核对 README / SKILL.md 和 SVG；Edge 响应式与独立 Android 模拟器真实 RPC 阅读 / 返回旅程通过。模拟器使用录制管理响应，不冒充新模型验收。
- 实际设备复现并修复 Future 返回给 setState、客户端释放后 WebSocket 通知的问题。结果、截图及未覆盖范围见 docs/side-phase-3-extensions.md。原生系统文件选择与真机完整交互继续待验收；不部署或 push。

## 2026-10-30 / Side Phase 3 Bot 原生欢迎

- 创建 Bot 后由其原生 Hermes profile 生成自我介绍及任务询问；不伪造用户气泡、不维护另一套 agent 或运行流程。刷新/重连不重复，失败保留错误并提供显式重试。
- 隔离 WSL 真实模型 completed；实际同私聊 session、一次 createRun、Node 重建及同步无重复，录制 SSE 与状态已脱敏保存。报告见 docs/side-phase-3-welcome.md。
- Node 24 的 17 文件 / 29 项测试、lint/typecheck/build 及完整 Edge 私聊旅程通过；专用 Android 模拟器通过介绍显示、重连不重复及点击失败重试，实际截图已核对。
- Android 创建表单的多来源接口、Windows 完整旅程、Android 真机/后台通知仍待对应模块验收，不以 RPC 或模拟器替代。未部署线上、未分发候选包、未 push。

## 2026-10-30 / Side Phase 3 Hermes 多来源与模型信息

- 新增 Providers 模块，直接管理 Hermes 原生授权目录、自定义来源及 profile 模型路由；移除单一全节点提供方及 OpenRouter 专用产品路径。Web / Flutter 设置不再选模型，Bot 表单选择来源与模型；Key 留在节点，OAuth grant 由 Hermes 原生继承刷新。
- 持久隔离 WSL 的真实验证通过：两自定义来源回复、OpenAI Codex 用户设备授权与真实回复、共存以及 Node/Hermes 重启后继续回复；没有复制 grant 或修改 Hermes 核心。原生上下文、最大输出与压缩结果如实展示，未知不猜测、不实现额外压缩。
- Edge 来源与建 Bot 旅程、390/768/1440px 截图及 Android 专用模拟器原生表单/欢迎/重连通过。收尾 Node 24 lint/typecheck、18 文件 / 30 项测试、build 通过，完整 Edge 5 通过 / 1 真实 Linux 屏幕跳过；Flutter analyze、2 项测试及双端 release 构建通过。
- 详见 docs/side-phase-3-providers.md。本轮只是模块收尾，不是 0.2.0 发布；全新检出、Windows 安装、Android 真机及共享用户记忆等仍待验收。仅本地提交，不部署、不分发、不 push；其余历史截图与私有现场保留。

## 2026-10-30 / Side Phase 3 同账号共享用户记忆

- 新增账号 USER 文档、修订、原件确认与可见冲突；通过既有 Node 出站连接和官方 profile 文件接口同步。按 Hermes 原生条目合并，不修改 SOUL / MEMORY / 会话，不热重建 agent 或新增记忆引擎。
- Web / Flutter 记忆页支持共享编辑、刷新保留草稿、原件及处理记录。Node 在连接恢复、原生回合前后和 USER 写入后同步；活动 run 中不回写文件，停止和失败也走同步。
- 持久隔离 WSL 真实模型验证：原生 memory 写入、跨电脑独立会话读取、实际文件监听、其他账号隔离、Node 重建无重复任务、独立自身设定及任务记忆均通过。
- Node 24 lint/typecheck、19 文件 / 31 项测试及 build 通过；完整 Edge 6 通过 / 1 真实 Linux 屏幕跳过，共享记忆 390/768/1440px、中英、浅深色与 reduced-motion 已实拍。Flutter analyze、既有 2 项测试与双端 release 构建通过；原生交互结果见本模块报告，不以构建代替真机。
- 详见 docs/side-phase-3-user-memory.md。保留既有数据及其他未提交截图；只做本地提交，不部署、不分发、不 push。全新检出、真机、Windows 安装、原生审核和通知等未验项目继续保留。
- 原生共享记忆旅程在专用 Android 模拟器通过编辑/保存、另一节点读取、返回、刷新与重连保留草稿；官方 driver 初次连接不稳定，续接同一进程后取得通过结果和实际截图，记录不掩盖此工具限制。
