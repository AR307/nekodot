# nekodot

面向非技术用户的多智能体产品。Web/PWA 通过 Relay 连接用户自己的 Node，
Node 以官方 CLI/API 管理 Hermes。Node 是本地业务状态的唯一数据源。

## 架构

- apps/web：React 用户界面。
- apps/relay：连接与路由入口。
- apps/node：本机代理与 Hermes 集成。
- packages/protocol：Zod 边界协议及 TypeScript 类型。
- packages/fake-hermes：仅测试使用的真实事件回放服务。
- scripts：开发和真实 Hermes spike。
- docs/references、design：完整技术及视觉原件。

## 更新记录

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
