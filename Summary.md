# nekodot

面向非技术用户的多智能体产品。React 网页及 Windows / Android 客户端通过 Relay 连接 Node，
Node 以官方 CLI/API 管理 Hermes，并保存业务状态。原生 App 当前只连接远程服务器，不运行本地 Hermes。

## 架构

- apps/web：React 用户界面。
- apps/client：共用 React 界面的 Tauri 2 Windows / Android 宿主。
- apps/native：Flutter Windows / Android 候选客户端，Rust 原生 RFB 屏幕与现有 Relay 协议；迁移验收完成前不替换已发布客户端。
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

## 2026-10-30 / Side Phase 3 原生产品旅程与安装候选

- 补齐双端 Flutter 私聊、群聊、审批、提问、同 run steer、停止、失败恢复和文件旅程；修复审批设置误覆盖、发送中草稿清空、重连选项丢失及 Windows 列表 Material 断言。真实 Node/Relay 加 Hermes 录制回放通过，不冒充新模型验收。
- 新增 Windows 每用户 NSIS 安装器与 app-local runtime；隔离目录覆盖安装、单实例和托盘恢复实测，旧 Tauri 保留。Android 候选沿用产品签名并按官方 ABI 分包，Flutter 0.2.0+4 的 arm64 APK versionCode 为 2004。候选包仅保留本地，未部署、发布或 push。
- 独立源码 frozen install、Node 24 lint/typecheck、19 文件 / 31 项测试及 build 通过；完整 Edge 最终 6 通过 / 1 真实 Linux 屏幕跳过。Flutter analyze、4 项 widget 场景和原生旅程结果与未覆盖范围见 docs/side-phase-3-native-product.md。真机通知、外部邮件重置/补验、扩展导入与干净用户安装仍未完成。

## 2026-10-30 / Flutter 客户端界面重构

- Windows 改为纯黑白实色：左侧会话栏、顶部居中名字胶囊、灰色消息气泡、宽窗右侧详情面板、左下角账户菜单和居中的 Skills / 插件弹窗；无边框窗口，自绘窗口按钮。
- Android 保留透明黑白毛玻璃：共用背景上的磨砂卡片和顶栏，底部悬浮栏放 Skills、插件、设置和新建。两端共用逻辑，由 `Tone.glass` 按平台切换样式。
- 重绘圆形猫头像、应用图标和 Android 启动画面；Bot 颜色是界面里唯一的彩色。砍掉解释性文案、重复入口和按钮说明，状态改用圆点表达，图标按钮保留 tooltip 与无障碍标签。
- Windows 与 Android 模拟器的产品旅程（回放 Hermes）通过，功能逻辑未改。Web、Tauri 和官网未动，官网截图仍是旧界面。详见 docs/progress.md。

## 2026-10-31 / 重连竞争、运行动画与头像形象

- 修复 Flutter 客户端手动重连的竞争：`connect()` 开始时复位 `ready` 并立即结束旧连接上的请求，握手完成前不再发出 RPC。新增回归测试，修复前失败。
- 恢复运行动画：耳朵摆动、眼睛扫动、空闲眨眼、悬停抖耳和思考时的跳动圆点，参数取自网页版。修复上一轮引入的每次刷新都重启主题动画的问题。
- 头像增加到 8 种形象（猫、熊、兔、狗、团子、花、幽灵、机器人）和 16 种颜色，协议 `avatar.shape` 扩展为枚举，Flutter 与 Web 同步显示和选择；Flutter 新建 Bot 默认随机。新形象需要 Node 升级后才能保存。

## 2026-10-31 / Flutter 客户端密度调整

- 按 impeccable 的 Operate 与 Android 规则收紧两端：控件高度电脑 32、手机 40（触控区 48），小圆角按内容宽度排布；输入框标签移到框外；统一线性图标；降低字重；去掉阴影加边框的组合和设置行的装饰图标。详见 docs/progress.md。

## 2026-10-31 / 全量回归与提示条

- 提示条改为居中、宽度贴合文字的短条。Windows 与 Android 模拟器 5 条原生旅程全部通过，Edge E2E 6 通过 / 1 跳过；`live_journey` 指向生产环境，未运行。详见 docs/progress.md。

## 2026-10-31 / Node 更新 1：协议与发布工具

- 增加时间戳版本、签名清单和 node.update 通知；hello 保持已有宽松版本字段。发布工具只读取发布者提供的 Ed25519 私钥，生产私钥不生成、不入库。
- 普通分发构建把旧清单移入私有回收目录，避免新 bundle 配旧清单；不删除文件。隔离测试实际执行盖章脚本，验证签名及缺少密钥/占位符时拒绝。该模块尚未接产品自更新链路。

## 2026-10-31 / Node 更新 2：Relay 发布通知

- Relay 每次 Node/客户端 hello 后从磁盘重新读取发布清单，仅向时间戳旧版本发送 node.update；1.0.0 旧 Node 不收未知消息，/api/me 返回一次手动更新命令。替换同一节点连接时保留新 socket 的版本。
- HTTP/WS 场景通过：旧版本保持在线、同版本不通知、更换 downloads 后客户端连接触发更新、缺失/非法清单返回 404；typecheck 通过。未部署生产。

## 2026-10-31 / Node 更新 3：空闲切换

- 安装版 Node 校验签名、版本、32 MB 下载上限、内容摘要及 CommonJS 语法；下载后等待私聊、欢迎、群聊接力及管理操作空闲，再保存上一版、写入待确认标记并切换，以 75 退出交给服务重启。失败保留当前服务，冷却 10 分钟。
- hello.ok 回收启动标记；标记只移入 bin/recycle，不删除。开发版或非安装路径不更新。Node 24 typecheck、更新器及连接 2 项场景测试通过；真实安装与 systemd 升级/回滚仍待后续验收。

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

## 2026-10-31 / 官网与 README 更新

- 官网按 impeccable 的 Persuade 文档重做，配色跟随 Windows 客户端：纯黑白，只有 Bot 头像有颜色。首屏是下载按钮和站在窗口上的 8 个头像，眼睛跟随指针。
- 回放改成客户端窗口样式，新增「停下来问你」场景；新增 8 形象 16 颜色的头像选择、Windows / Android 黑白分屏、滚动切换的功能窗口。截图全部换成 Flutter 客户端的演示数据实拍。
- README 和官网补上多模型来源、共享用户记忆、原生提问、Bot 欢迎、节点自动更新和 Flutter 客户端，移除 OpenRouter 专用说法。README 写明 0.2.0 仍是候选版。详见 docs/progress.md。

## 2026-10-31 / 0.2.0 发布构建与候选验收

- 统一为 0.2.0 开发者预览版；Flutter 0.2.0+5，Android arm64 versionCode 2005。Windows 安装包与 Android 原签名包构建通过，保留 MIT 及 Windows 未签名说明。
- 使用用户在仓库外生成的生产密钥盖章 Node，Relay 镜像在本地构建并实际启动；明确打包发布清单。候选服务使用生产数据库副本，SMTP TLS/认证、旧账号补验、登录/退出与 WS 撤销通过。
- Node 24 frozen install、lint/typecheck、23 文件 / 36 项测试、build，Flutter analyze 与 11 项测试通过；新官网 12 组 Edge 视觉/交互检查通过。线上切换和发布结果另行追加，不把真机通知等遗留项标记完成。

## 2026-10-31 / 0.2.0 线上部署与官网缓存修复

- 生产 Relay、项目 Node、官网及双端下载已更新，账号、profiles、历史与浏览器资料保留；其他产品容器没有重启。首次 Node 安装遇到项目 PM 输入目录属主问题，保留原目录后局部修正并完成安装，不改 Hermes 核心。
- 公网 HTTPS/WSS 真实流式回复及重复 clientMsgId 去重通过，临时内部验收会话已撤销；不作为新的真实邮箱登录验证。官网两个包实际完整下载成功。独立源码全部基础检查和 Edge 7 通过 / 1 实屏专项跳过。
- 在用户原有 Edge 标签复现新版 HTML 混用 CDN/浏览器旧资源；给 CSS、JS、截图及主题切换地址加发布版本。上线后普通刷新已显示白底、猫 logo、8 头像和新版 Flutter 截图，无需清缓存。原站点文件保留，无服务重启。
- 记录见 `docs/release-0.2.0-acceptance.md`。GitHub 发布继续执行，真机通知、干净用户安装等未验项目保持待验。

## 2026-10-31 / 0.2.0 公开交付

- GitHub main 已同步本轮完整产品更新与官网缓存修复，v0.2.0 采用开发者预览版，保留既有 Release。双端安装包已上传，Windows 为 15,684,634 字节，Android 为 34,054,104 字节，与官网包一致。
- 官网与仓库主页均为 `https://nekodot.com`，README 链接到 v0.2.0，许可证继续 MIT。Windows 安装器未做 Authenticode 签名，Android 延续原签名；用户其他未提交截图未纳入发布提交。
- GitHub 包已用未登录请求完整下载验证，v0.2.0 标签 CI 通过。另一轮 CI 暴露群聊测试抢先读取配对码，等待可见码后隔离 Edge 完整旅程通过；仅补测试断言，不改发布标签或产品包。

## 2026-10-31 / 0.2.0 正式发布

- 按用户要求将现有 v0.2.0 转为正式版并设为 GitHub Latest，Release 名称改为 `nekodot 0.2.0`；双端包及既有标签保留。
- 同步官网中英文、README、更新说明与当前发布验收说明，官网脚本增加新资源版本，普通刷新即可看到正式版文案。
- GitHub API 核对正式版、Latest 与原资产；Edge 实测官网中英文和两处下载入口，eslint 与针对性格式检查通过。既有未验项目继续按实际结果保留。

## 2026-10-31 / Hermes 执行中断恢复

- 修正 Node 将原生 `unknown` 执行误当终态的问题：保留对应 run、部分回复和群聊队列，刷新或节点恢复后仍提供停止入口，不继续提交或重跑任务。
- 现有停止操作读取原生状态；对 `unknown` 使用原生 `/resolve-unknown` 和实际 admission/generation，成功后才结束本地回合并清空本次群聊接力。失败时保留待确认状态。
- Flutter 与 Web 显示中断提示、保留草稿并暂停发送，停止确认后可手动发送新任务；不改 Hermes 核心。服务端 38 项测试、Flutter 12 项测试通过；Edge 390/1440px 实际完成回放恢复旅程。
- 此次仅完成本地修复与隔离验证，未部署、未发布新安装包。已核对的产品服务没有用户所述失败记录，仍需准确 VPS SSH 地址或 App 节点名称，才能检查及恢复实际会话；回放结果不作为该 VPS 已恢复的证据。

## 2026-11-01 / 实际 VPS 会话恢复与 Node 修复部署

- 已在用户提供的实际节点复现：原生执行重启后为 `unknown`，后续四条消息仍在原生队列；Node 又因 `execution_generation: null` 解析失败显示 unsupported event。补齐实际空值契约，原生仍为 queued 时不把 SSE 错误当作已结束回合。
- 通过 Hermes 原生接口先取消四条未执行消息，再确认原中断执行；待执行队列归零，没有重放原任务。保留节点数据库、profile、历史及私有现场备份。
- 仅更新受影响 Node 的独立构建 `20261031155700`，服务重启后 Relay 在线。同 profile、同会话的真实模型在部署前后验证中均完成回复；修复解析器读取真实 SSE 成功，工具执行数为零，既有聊天历史数量不变。
- 25 文件 / 39 项服务端测试、typecheck、针对性 lint 通过。未改 Hermes 核心、未重启整机或其他服务，未更改公开安装包或 push；Android 真机界面未在本次操作中直接控制。

## 2026-11-01 / Windows 登录窗口

- 登录/注册页补上独立的原生拖动区域，位于表单滚动层之上；语言切换避开右上角窗口按钮。复用 window_manager，不增加另一套窗口实现。
- 手势用例确认拖动命中实际 startDragging，邮箱输入与语言按钮不被覆盖。Windows 实窗双击标题区域可最大化/还原；自动化拖动没有取得窗口位移证据，不能写成实际移动已验收。未替换用户已安装客户端，仅本地提交。

## 2026-11-01 / 原生指令栏、群提及与文件发送

- Flutter 输入 `/` 获取对应 profile 的 Hermes 原生命令目录并执行，耗时结果复用 Operations；群聊可选执行成员。仅终端及需要原生会话切换界面的命令明确禁用，不假造会话效果或另建 agent。
- 群聊 `@everyone` 按成员顺序展开、去重，沿用现有串行接力与六回合上限；Flutter/Web 均有成员选择入口。
- Flutter 系统文件选择、分块上传、文件单独发送、中文文件卡和预览已接通；Node 向原 profile 提供文件路径及原生图片输入。上传副本、消息去重与草稿保留沿用既有机制，运行中的原生 steer 不接收附件时明确提示。
- 服务端 27 文件/41 测试、Flutter analyze/14 测试、Node/Relay/Web 与双端 release 构建通过。Windows 原生回放旅程通过，真实模型另验中文文件读取和图片识别；Edge 初次 6 项通过/1 超时，超时的提供方旅程独立复测通过。未冒称 Android 真机通过。
- 验收和新增截图见 `docs/composer-update-acceptance.md`。仅本地更新，未部署、未发布、未 push；其他未提交截图和运行现场保留。

## 2026-11-01 / 小内存 VPS 屏幕调查

- 实际故障节点约 2GB RAM，可用约 380–452MiB，原生 display.status 明确被 1536MiB 可用内存门槛阻止；依赖已安装，不是客户端等待太短。没有内核 OOM 证据，不将旧 SIGKILL 等同 OOM。
- 量化本项目瞬时 PSS：Node 约 9MiB、gateway 253MiB、管理 serve 228MiB。官方 gateway 管理通路值得后续收敛，但使用专属单次票据，不能直接换 URL 或去掉管理后端；即使省下 serve，当前机器也不够原生门槛。
- 本轮未改内存配置、强行启动屏幕或停止其他服务。调查与容量建议见 `docs/screen-memory-investigation.md`；不把研究结果写成小 VPS 屏幕已修复。

## 2026-11-01 / 测试客户端启动与真实验收约定

- 已启动本次候选 Windows Flutter release 客户端，使用产品 HTTPS 地址并恢复现有账号，实际窗口显示当前 VPS 节点与 Bot；不是回放演示页，未替换已安装版本。
- 按用户最新要求，将真实候选客户端、对应服务端、官方 Hermes 与真实模型作为默认验收；已获准必要模型调用，不按费用缩减测试。回放与代码测试只作辅助，不冒称真实验收完成。
- 本次启动本身不等于新增能力的远程闭环通过。新增指令与附件 RPC 尚需对应服务器版本，未在本次启动操作中擅自更新生产服务。

## 2026-11-01 / Side Phase 4：原生例行任务与公网接入

- 增加 routines 模块、薄 Hermes CLI/skill 插件和私有 socket；纯 webhook 使用原生动态订阅，组合任务关联既有 cron，不增加调度或 agent 引擎。旧定时任务查询统一进入 `routines.*`。
- Relay 新增 `/hooks/:routineId`，经现有节点出站连接转发到原生 loopback webhook；只存入口摘要/归属，不存请求正文。Node 分离并加密外部/内部凭据，保密卡和模型仅使用任务引用。
- 原生结束 hook 决定实际执行结果，保留 outbox 并回投对应私聊；不会占用或打断正在运行的私聊。Relay 握手提供公网 URL，避免同机 Node 展示 loopback 地址。
- 已真实复现上游跨 profile admission 503。获用户授权后，最小原生修复单独提交 `67e4f384`，13 项 canonical 测试和官方 checker 通过，仅应用隔离 checkout。
- 隔离真实公网及模型、Windows 候选完整旅程、错误/旧钥、跨账号和原生 ignored/duplicate 已验证；组合 cron 的 webhook 执行通过。当前 lint/typecheck、29 文件44测试和服务构建通过。其余验收及产品部署边界见 `docs/side-phase4-routines-acceptance.md`；未发布或 push。

## 2026-11-01 / Side Phase 4：原生终态采集修正

- 真实非法模型在初始化时失败，Hermes 没有发 session hooks，早期 outbox 方案漏报。改由薄插件只读原生 admission 与持久结果；不修改 Hermes 执行逻辑，不依赖回复文本判断成功，不增加后台执行或重试循环。旧验收 outbox 保留。
- 通过明确 profile 定位原生数据，已完成 session 不重复回投；Node 关闭先收集结果再关闭管理后端。已有 profile 在启动时更新项目插件。
- 实际已失败任务经重启补回 failed 私聊记录，没有重跑；归档后公网403。同一 cron 的实际定时与 webhook 都完成真实模型回复。Agent 创建并执行保密 helper 脚本，公网202且实际任务完成；模型上下文不含密钥。
- 当前 typecheck、lint、29文件44服务端测试、Flutter analyze及15测试通过。最终候选双端与恢复验收继续，未发布、未 push。

## 2026-11-01 / Side Phase 4：Flutter 例行任务入口

- Bot 详情统一展示定时、Webhook 和组合例行任务；新增详情/编辑、URL及密钥按需复制、用户确认保密交付、Webhook暂停/恢复、密钥轮换、JSON测试及原生执行记录。组合任务分别显示定时与Webhook状态。
- 聊天任务卡和保密卡仅保存任务引用；后台结果可打开对应执行详情。详情手机滚动、返回、加载和错误状态复用现有原生组件；不新增HTML产品路径。
- Windows与Android模拟器候选均连接隔离真实Node/Hermes/模型，完成创建、复制、保密交付、公网202、真实结果、暂停403、轮换旧钥401、返回聊天。Android加载初始值的实际异常已修复并完整复测；不是回放结果。Android真机和真实推送仍待验。
- 真实Agent脚本调用及私聊工具运行期间独立后台执行均通过：前台runId不变、完成无误；后续追问使用已有结果，没有新增执行。屏幕截图和完整边界见阶段验收记录。仍未发布、未 push。

### Side Phase 4 — 实拍修正：例行任务滚动边界

- Android 候选实拍发现任务详情的长记录会滚入玻璃顶栏，叠到标题和返回入口；例行任务详情和设置页改为在顶栏下滚动，其他改版页面维持原布局。
- 原生集成旅程增加实际视口与顶栏几何断言，继续使用真实模型和公网 webhook；不以 widget 单测替代双端旅程。

### Side Phase 4 — 原生复制旅程的实际完成确认

- 真实复测暴露验收脚本在异步凭据复制完成前读取剪贴板，导致后续请求拿到旧内容；改为等待原生页面复制完成提示，并核对复制 URL 所属任务及密钥一致性，失败信息不打印明文密钥。
- 双端旅程串行运行，避免 Android 模拟器和 Windows 共享系统剪贴板干扰；产品凭据接口和权限逻辑没有放宽。

## 2026-11-01 / Side Phase 4：最终隔离验收与候选交付

- 最终代码基线 `866ee2de56` 在独立检出完成 Windows 和 Android 模拟器原生旅程，均使用真实 Node/Hermes、真实模型和公网 HTTPS，覆盖建任务、保密交付、复制、执行结果、暂停及轮换；不是回放通过。
- 真实补验包括同一 cron 的定时/事件触发、helper 引用调用、前台工具执行时的独立后台任务、追问不重跑、原生权限拒绝、失败及离线/服务重启恢复。原生 execute_code 拒绝已核对实际 tool 记录。
- frozen install、lint、typecheck、29文件44服务端测试、服务构建及 Flutter analyze/14测试通过；Edge 7通过1屏幕配置缺失跳过。双端 release 构建完成，APK原有签名有效，EXE未做发布签名；版本仍为0.2.0+5。
- 临时公网QA路由已撤回，官网/产品health为200、原QA hook为404；只reload Caddy，其他服务启动时间不变。保留隔离数据、profiles、日志与失败现场。原生最小修复仅在QA，产品未部署、未发布、未push。
- Android真机、真实通知/FCM和新页面完整视觉矩阵仍待验收。详细结果、实际截图、脱敏证据及候选包位置见 `docs/side-phase4-routines-acceptance.md`。

## 2026-11-01 / Side Phase 5：Hermes canonical gateway transport 基础

- Node 增加按 Hermes profile 复用的 `hermes-gateway-v1` WebSocket 客户端；通过 `gateway ensure --json` 获取本机 endpoint，再由同用户私有控制 socket 申请单次 session ticket，ticket 不下发给 App。
- 处理 Hermes 首帧 `gateway.ready`、JSON-RPC 请求/响应、服务端请求回包、事件帧、断线及错误帧；服务启动关闭时统一释放连接。
- 协议旅程测试验证事件、RPC 与反向请求；Node typecheck、目标 ESLint、gateway/runtime 测试通过。
- 这只是 canonical transport 基础：聊天仍使用旧 Runs API，session/history/approval/clarify/steer/stop 尚未切换，未对真实 Hermes 服务或模型做端到端验收，Phase 5 未完成。

### 2026-11-01 / Side Phase 5：canonical 会话与命令路径

- Node 私聊与群聊回合统一经 Hermes `hermes-gateway-v1` 创建/恢复 profile session、提交 prompt、读取事件、恢复历史、审批/提问、steer、停止和读取 admission 结果；群聊成员仍由 Node 选择，但同一 Bot 的群聊与私聊复用已持久化的 Hermes stored session。
- 命令目录、slash 与 quick/skill command dispatch、`/refine` 以及记忆审核改用对应 profile 的 Gateway 会话；self-improvement 通过原生 `review.summary` 事件关联。新增轻量 `openNativeSession` 统一 session 创建/恢复和数据库映射。
- 移除产品 runtime 对 Hermes Runs API 客户端的依赖，启动健康检查只请求本机原生 health endpoint；Hermes 自身 API server 仍保留为文件/工具等原生能力使用，不承载产品聊天执行。
- 验证：Node 24 全量 typecheck；30 个 Vitest 文件、45 个场景；针对性 ESLint、Prettier 与 Node 24 build 通过。隔离 Ubuntu 24.04 实际 Hermes/模型旅程验证真实欢迎回合、Gateway `/profile`、恢复与同步不重复，详见私有 `.runtime/side-phase-5/canonical-session-welcome.json`。
- 未完成：真实候选 Windows/Android 客户端、远程 Node/Relay 的匹配版本验收，以及 Hermes 全能力和设置目录仍待后续模块；本地真实 WSL 旅程不替代这些验收。

### 2026-11-02 / Side Phase 5：Hermes profile 设置

- Bot 详情新增 Hermes 设置页，分类、字段描述、类型、选项与当前值从官方 `/api/config/schema` 和 profile 配置读取；开关、选择、数字与 JSON 字段经官方 config PUT 保存，不另存一份产品配置。
- 设置范围固定到当前 Bot profile；密码、密钥及 token 字段只显示是否已配置，不回传明文，也不允许从通用设置编辑。`model` 与虚拟 `model_context_length` 在此只读展示，编辑仍走 Bot 模型设置。
- 验证：Node 24 typecheck、31 个 Vitest 文件 / 46 项通过、Node bundle build、目标 ESLint、Flutter analyze、Flutter tests 及 Windows debug 构建通过。新增 390px 原生设置页场景覆盖搜索、敏感项遮蔽和布尔保存。
- 真实 Hermes profile 的隔离写入/读回及候选客户端在线旅程仍未完成；现有 WSL 安装的隔离运行环境缺少 `ruamel.yaml`，不把 fake Hermes/widget 测试算作真实验收。全仓 lint 另被 `opus-video` 目录里 16 项 ESLint 错误阻挡。

### 2026-11-02 / 官网：极早期开发版本提醒

- 官网下载说明的中英文由「0.2.0 正式版」改为极早期开发版本、可能会有很多 Bug，与首发视频片尾提醒一致；官网脚本增加新资源版本，普通刷新即可看到新文案。
- ESLint 与 Prettier 忽略 `opus-video`，全仓 ESLint 恢复通过。README 和 GitHub Release 仍写正式版。

### 2026-11-02 / 验收环境整理与固定 Android AVD

- 按用户确认范围回收旧隔离检出的 Tauri/Flutter 构建、旧依赖、重复 Flutter SDK/ZIP 和旧 `NekodotSideStage2` AVD；仅移动保留，没有永久删除。跨盘 pnpm junction 的剩余依赖保存在项目同盘回收目录，两端均保留，恢复清单位于私有回收目录。
- 当前候选、源码、profiles、历史、凭据、证据及其他项目 AVD 均保留；整理后实测 D 盘空闲约 36GB。
- 新增 `pnpm native:emulator`，固定启动或复用 `NekodotNativePhase3` 并等待启动，不新建、不 wipe-data。实际复用 `emulator-5554`，Android API 35 x64。
- 真实 Hermes v0.22.5 的隔离 PM 环境已通过官方入口同步，原 `ruamel.yaml` 阻塞已解除；本次真实客户端验收继续使用匹配源码的隔离 Node/Relay，不改生产服务。

### 2026-11-02 / Side Phase 5：profile 设置双端真实验收

- Windows 与固定 Android API 35 x64 模拟器的原生候选，连接真实隔离 Node/Relay、官方 Hermes v0.22.5 和 gpt-6.1-sol，完成 908 字段读取、搜索、布尔与 select 保存、profile 隔离、真实流式回复及连接恢复；不是 fake Hermes 或 widget 回放通过。
- 真实复现并修复“选择清空后取消仍写入配置”：dialog 用明确保存结果区分取消与 null。Android 实拍发现第四个标签被起始留白挤出，仅调整该详情栏对齐方式，双端复测通过。
- 实际重启隔离 Hermes 后设置/历史不变，canonical `/profile` 可用；再实际重启隔离 Node/Relay，复用原数据，12 条消息标识及设置保持一致，没有重建 Bot 或重新配对。
- Node typecheck、31 文件 / 46 场景、全仓 ESLint/Prettier、Node bundle、Flutter analyze 与16项 Flutter tests通过；最终候选 Windows 约22秒、Android模拟器约26秒完成本模块真实旅程。详细证据与限制见 `docs/side-phase5-settings-acceptance.md`。
- 本轮仍为 0.2.0+5 Debug 候选；Android真机、完整视觉矩阵、生产VPS匹配版本、其他全能力模块及最终release验收继续保留，不部署、不发布、不push。

### 2026-11-02 / Side Phase 5：修复指令目录与 App 薄适配

- 真实定位 `/history` 的 `unsupported_command`：Hermes 目录是多客户端能力合集，不保证每条都由 `slash.exec` 实现。历史改用 canonical `session.history`；工具、子 Agent/进程、技能重载、环境刷新接各自原生 RPC，设置/模型/插件打开已有 App 页面，编辑器/指令栏留在客户端处理。
- 目录区分原生可执行、App 适配、服务器终端及待接入，将不可用条目折叠；保留原生别名、动态 Skills/Quick Commands/插件和详细错误，不增加 shell 转发或第二套 Agent 引擎。会话新建、分支、恢复、撤回等仍明确待接入。
- Windows 与固定 Android API35 模拟器通过真实 Node/Relay、官方 v0.22.5 和 gpt-6.1-sol 的流式回复、历史无新增模型回合、工具/子 Agent 查询、别名、技能重载、设置跳转及重连无重放旅程；不是只靠录制测试。完整报告见 `docs/side-phase5-command-acceptance.md`。
- Node 32 文件48测试、typecheck、lint、bundle，Flutter analyze及17项测试通过。没有改生产或发布；保留未验真机、完整命令/参数和会话控制边界。
- 额外按已授权范围将三个旧原生安装包移入私有回收目录，未永久删除；重建并启动匹配服务的 Windows/Android 私有手测候选，不将其中 QA 配置纳入 Git 或公开分发。

### 2026-11-02 / Side Phase 5：原生命令适配（Node 模块）

- 将会话新建/恢复/分支/撤回/重试/压缩/导出集中到 `session-commands.ts`；子 Agent、进程、后台问答、工具启停及浏览器控制集中到 `command-controls.ts`；日志、备份、profile 导入导出和工作区使用 `host-commands.ts` 的固定官方接口，不增加 shell/URL 代理或第二套执行通路。
- 增加原生学习历程、宠物与订阅的薄投影，以及对应 RPC。原生 profile archive 经既有资料库交付、导入为新 Bot，保留原生记忆和技能。
- 冻结目录实际为 152 条：52 条 App 适配、97 条原生动态/命令条目、2 条纯终端设置、1 条 canonical 不支持的 handoff。目录可用不代表全部参数已经验收；wake 仅依赖状态、queue 仅查询/取消，恢复或删除数据的操作不开放。
- 真实发现工具配置写错 profile，改用官方 profile-scoped REST；发现 `wake.status` 不接受 session_id，修正原生参数；子 Agent/进程列表补上可用于后续控制的真实标识。
- 真实复现子 Agent 回投污染下一次私聊输出：canonical 事件按原生 admission ID 归属，排除其他后台回合，并随实际事件更新 execution generation。Windows 同场景复测通过，真实 steer/Stop、子 Agent 控制和模型压缩通过；55 个原生命令调用场景完成，完整双端复测另记录。
- 本模块仅本地提交；未改 Hermes 核心、未部署生产、未发布、未 push。实现说明：`docs/side-phase5-command-adapters.md`。

### 2026-11-02 / Side Phase 5：原生命令扩展，模块二（Flutter）

- Windows / Android 增加原生会话选择与历史、学习条目编辑、宠物目录及订阅状态页；profile 导出资料卡可导入为新 Bot。剪贴板图片、设备文件、显示密度、时间戳、专注、外观、电量与退出均使用当前设备能力，不读取服务器剪贴板或仿造终端界面。
- 同一真实候选、官方 Hermes v0.22.5 与真实模型已完成双端会话、设备、主机/导入及运行控制旅程：实际图片识别、后台问答、子 Agent tail/steer/interrupt、进程 kill、私聊 steer/Stop、真实模型压缩和重连无重放。Android 固定复用已有模拟器；不混作真机结果。
- 实测修正长时间使用的电量刷新 Future/setState 异常、用户气泡时间戳对比度和新页面长内容叠顶栏。`/help` 与指令栏展示实际 App 参数，不再照搬 CLI 的删除、服务器路径或未连接的麦克风/队列参数。
- 最新原生目录 152 条：53 App 适配、96 原生/动态条目、2 纯终端设置、1 canonical 不支持。缺图像服务的孵化、无账号的 Nous 订阅、App 语音及队列写入不计通过；逐项范围记录在命令验收文档。
- 不覆盖其它 UI/截图改动，不删除验收数据，不发布或 push；最终工程检查、安装包与手工系统对话框验收另行记录。

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
- 原生 heartbeat / handoff 限制、语音闭环、Android 真机/推送/完整视觉矩阵与缺配置外部工作流继续保留为后续事项，不改记为通过、不再阻塞本阶段。详细范围见 `docs/side-phase5-command-acceptance.md`。
- 本次只更新结项文档，不修改产品代码、服务或用户数据；本地提交，不发布或 push。

### 2026-11-02 / Bot 历史会话与 GUI 切换

- 私聊顶栏与 Bot 详情增加历史会话入口，支持名称/ID 搜索、当前标识、历史预览、可选名称新建及直接切换。复用既有 canonical 会话和 Operations，不新增 Agent 引擎或服务端协议。
- Windows 与固定 Android 模拟器使用官方 Hermes v0.22.5、真实 Node/Relay 和 gpt-6.1-sol 完成 GUI 新建 A/B、原生 session_search 读取旧会话、预览不切换、切回后真实回忆、草稿保留、重连无重放和其他 Bot 会话不变；测试后恢复原会话，所有测试历史保留。
- 真实旅程发现并修正历史预览返回时 setState 返回 Future 的刷新异常；最终双端完整复测通过。Flutter analyze 与18项辅助测试通过。Android 真机及完整视觉矩阵不计通过，未部署生产或发布/push。
- 主聊天时间线保留现有交互日志，切换改变原生上下文；具体会话历史在预览中读取，不清空或重写聊天记录。详见 `docs/bot-sessions-gui-acceptance.md`。

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

## 2026-11-03 · 修复 Node 握手卡住导致持续离线

- 真实 VPS 在网络断流后停在 WebSocket 建立阶段约 11 小时；服务进程存活，Relay 已离线。使用 ws 原生 30 秒握手超时恢复既有退避重连，不改 Agent 执行逻辑。
- 真实 TCP 卡住升级的 Relay 场景验证自动恢复、在线查询及持久 snapshot；限定文件检查和 Node 24 单文件运行通过。
- Node 补丁 `20261103022508` 更新正式分发和故障 VPS，旧程序保留备份；不要求手机重装，不更改用户数据或其他服务。详情见 docs/node-relay-handshake-fix.md。

## 2026-11-03 · 新建 Bot 默认按名称生成 handle

- 修正空白 `@handle` 被创建协议拒绝的问题：新建时由 Node 按名称生成，支持中文；同名追加序号，手动代号仍可指定，已有 Bot 改名不改代号。
- Flutter 表单在未手动修改时随名称填入代号；模型必填错误显示具体字段并保留表单。群聊提及同步支持中文代号。
- 固定 Android 模拟器使用真实 Node/Relay、官方 Hermes v0.22.5 和 gpt-6.1-sol，通过实际表单创建、真实欢迎、中文群聊提及和缺模型纠正旅程；11 项辅助测试、TypeScript、限定 ESLint 及 Flutter analyze 通过。
- Node `20261103042820` 已更新正式分发和故障 VPS，服务恢复 online；当前 APK 留空即可创建，无需重装。客户端自动填入的显示更新尚未发布新 APK/EXE，仅在候选中验证。未改 Hermes 核心、用户历史或其他服务，未 push。详见 docs/bot-default-handle-fix.md。

## 2026-11-03 · 聊天内保密交付：Node 与原生插件

- 新增 metadata-only secret 卡片、显式 secrets RPC、Bot 独立密钥和加密保存；Relay 只转发密文。通用请求使用原会话原生排队继续，不制造用户气泡，不重跑工具。
- 复用 Unix socket 桥接，增加 profile 绑定的 CLI / skill / SecretSource；原生技能密钥通过 canonical server request 回答。网站通过原生 vault、browser supervisor 与控制权检查处理。
- 辅助行为测试及 TypeScript 已通过；真实隔离 Hermes v0.22.5 + gpt-6.1-sol 已创建实际待交付卡片。客户端、网站及恢复验收继续进行，未发布、未 push。详见 docs/confidential-delivery.md。

## 2026-11-03 · 聊天内保密交付：Flutter 卡片与管理

- Flutter 使用 cryptography 加密提交；聊天卡片展示接收 Bot、用途、准确目标与默认不保存选项，支持多行私钥、匹配资料选择、取消和实际状态恢复。输入不写入草稿，提交、取消、离开及后台时清空。
- Bot 详情新增保密资料管理区，仅显示元数据，支持重新交付、替换和停用。原生请求沿用 Hermes 的等待状态，并发送不含资料值的提问提醒。
- Windows 候选使用真实隔离 Node/Relay、Hermes v0.22.5 与 gpt-6.1-sol，通过 API 配置后实际 HTTP 调用及 canonical 原生技能密钥请求；固定 Android 模拟器通过多行私钥提交、真实继续和文件逐字读回。网站登录、隔离及恢复仍继续验收，不记为整个功能完成。
- 服务端 62 项辅助测试及 Flutter analyze 通过；Windows/Android 截图驱动问题单独修正，不作为产品功能成功证据。未修改 Hermes 核心、生产服务或无关 UI 改动，未发布或 push。

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

## 2026-11-04 本地电脑运行 · 模块一：Node 桌面托管

- 新增 `run --desktop`：由桌面客户端持有进程，stdin 关闭或 `stop` 即优雅停止，stdout 输出机器可读状态；停止信号在 Hermes 启动前生效。
- Hermes 通过明确 launcher 路径启动；插件桥接 POSIX 用 Unix socket，Windows 用随机命名 named pipe；gateway 控制通道支持 Windows 管道并在 Windows 上经 `gateway stop --yes` 停止。
- 桌面节点不提供 Bot 独立屏幕；文件交付识别 Windows 路径。实施计划见 docs/local-desktop-plan.md。
- Windows 上 38 文件 68 项辅助测试、TypeScript、ESLint、bundle 通过；未连接真实 Hermes，不计真实验收。无 push 或部署。

## 2026-11-04 本地电脑运行 · 模块二：客户端本机运行模块

- 客户端可分别选择运行环境与数据目录（可放在非系统盘），按内置校验值下载 Node 24 与 Hermes v0.22.6 安装脚本，执行官方分阶段安装；`products` 阶段经包装脚本只构建、不改写 PATH。
- Rust 桥接托管本机进程：无控制台窗口，Windows Job Object / POSIX 进程组随客户端回收；Node 更新退出后按原回滚规则重启。
- Rust 编译、flutter analyze 与 23 项测试通过；未真实安装，不计验收。

## 2026-11-04 本地电脑运行 · 模块三：首次使用与生命周期界面

- 桌面添加电脑可选本机运行或远程服务器；本机安装页显示目录、进度、错误与重试，上线后自动选中。
- 设置页“这台电脑”卡片；登录自动启动、退出账号与退出应用先停止本机节点，运行中的本机任务先确认。修正配对页快速配对的基线竞态。
- 尚未真实验收。

## 2026-11-04 本地电脑运行 · 模块四：Windows 真实闭环

- Windows 真实 GUI：注册、中文路径目录、官方 Hermes v0.22.6 安装 6.3 分钟、自动配对选中、创建 Bot、真实模型读写本地文件、重新登录自动启动；停止、启动、退出与强制结束后进程全部回收；Relay 重启自动重连；Android 模拟器访问本机节点完成真实回复。
- 修正 Windows 阶段输出编码、进程树回收顺序与空白 commentary 气泡。未验项见 docs/local-desktop-acceptance.md。无部署、发布或 push。

## 2026-11-04 本地电脑运行 · 模块五：本机桌面操作能力

- 节点能力区分服务器/本机、Bot 独立屏幕与本机桌面操作；Bot 详情可逐个开启“操作这台电脑”，本机新建 Bot 默认关闭；授权只在本机执行。
- 真实 Windows 节点验证能力与开关；真实模型实际操作桌面尚未验收。

## 2026-11-04 本地电脑运行 · 模块四补充：取消与重试

- 真实 GUI 中途取消后保留已完成阶段，重试从中断处继续并上线；取消提示本地化。发现欢迎回复进行中发送的消息未送达，记为待处理。

## 2026-11-04 修正：欢迎回复进行中发送的消息

- 新 Bot 欢迎回合期间从输入框发送：Node 先等欢迎被 Hermes 受理（gateway 冷启动），再把消息作为原生排队输入放在欢迎之后，界面显示“已排队”/“队列任务”；不再以“run is starting”拒绝或丢失。普通运行中的发送仍为 steer。
- Windows 全新安装真实旅程（Hermes v0.22.6、真实模型）：欢迎尚未输出时发送，随后真实模型读写本地文件并逐字核对；新增 1 项辅助测试。无 push 或部署。

## 2026-11-04 本地电脑运行 · 模块五补充：桌面操作真实运行

- 关闭桌面操作时 Bot 无工具可用已真实验证；开启后的真实记事本操作被“同一运行内第二条消息未送达”阻断，交由修复会话，修复后重跑测试。

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
