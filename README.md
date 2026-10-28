# nekodot

面向非技术用户的个人 bot 小队。已实现注册、配对电脑、提供方与 bot 管理、流式私聊、群聊与 @handle 接力、工具审批、原生 steer、停止与断线恢复。

架构：React Web → Fastify/WebSocket Relay → 本地 Node → 官方 Hermes CLI/API。
聊天与完整密钥留在 Node；Relay 负责账号、配对、在线状态和连接路由。

每个 Bot 就是一个独立的 Hermes profile。私聊将用户输入直接交给该 profile 的官方 Runs API，
由 Hermes 自身处理模型调用、会话上下文、记忆、技能和工具执行；新建 profile 使用官方默认技能初始化。
nekodot 负责界面与消息同步，群聊只增加成员选择、上下文传递和顺序接力，每轮仍交给对应 profile 的 Hermes 执行。

## 开发

要求 Node 24 LTS、pnpm 10.34.5；浏览器验收当前使用本机 Microsoft Edge。

```
pnpm install --frozen-lockfile
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm test:e2e
```

Web：http://127.0.0.1:4318；Relay：http://127.0.0.1:4319。
Windows 本机可运行 `. ./scripts/activate.ps1` 激活已保留的独立 Node 24。
全新检出需要先安装 Node 24 和 pnpm；不要使用系统 Node 22 运行 node:sqlite。

启动 Relay 前，在本地 shell 提供 JWT_SECRET（随机私有值），不要写入源码：

```powershell
$env:JWT_SECRET = '<本地生成的私有随机值>'
pnpm dev
```

`pnpm dev` 启动 Web、Relay 开发入口；真实 Node 在配对后单独启动。
Relay 可选环境变量：PORT、HOST、PUBLIC_URL、DATA_DIR；默认只监听 loopback。
构建后可设置 WEB_DIR=apps/web/dist，运行 `node apps/relay/dist/index.js`，以同源方式提供网页与 WebSocket。

## 第一次使用

1. 网页注册账号，复制“添加电脑”页生成的本地配对命令，在独立 WSL Ubuntu 24.04 检出目录执行。
2. 按官方 PM 方式准备 Hermes 与隔离 runtime。已有官方 CLI 时运行 `pnpm node:run`；源码模式使用：

   ```bash
   pnpm node:pair --relay http://127.0.0.1:4319 --code XXXX-XXXX
   pnpm node:run --hermes-source /path/to/hermes-source --hermes-runtime /path/to/pm-runtime
   ```

3. 网页看到电脑上线后，进入设置，填写自定义 OpenAI-compatible 地址、API key 和模型，或选择 OpenRouter。
4. 返回团队，新建 bot，选择 Hermes 模型目录中的模型或明确填写自定义模型 ID，开始私聊。
5. 运行中发送会补充当前 run；审批时可以写草稿，允许一次、拒绝或停止后再继续发送。
6. 创建 2–6 位成员的群组并选择主答。无有效提及由主答开始；用户和 Bot 最终回复中的成员 @handle 按顺序触发接力，每条消息最多 6 回合。

群内一次运行一个 Bot，不同群可同时工作。运行中补充指令由当前 Bot 的同一个 run 接收，接受后清空尚未执行的接力队列；“全部停止”取消当前 run 并清空队列。
编辑群组从下一条新消息生效；归档群组保留历史。Bot 需要先退出活跃群组才能归档。

Node 数据默认在 `~/.nekodot`；可用 NEKODOT_HOME 指定隔离目录。
其 Hermes home、profile、SQLite、凭证及日志均在此目录内；gateway 只监听 127.0.0.1:18642。
完整 provider key 仅存于托管 `.env`，网页与数据库只保留后四位。根 `.env.example` 供独立真实 spike 使用，产品提供方在网页配置。
Windows/Linux 各自安装 node_modules，不共享依赖，也不修改全局 shell。

## 验证与证据

- `pnpm test:e2e` 使用本机 Microsoft Edge。首次缺浏览器时执行 `pnpm exec playwright install msedge`。
- 自动化以已录制的真实 Hermes fixture 驱动 HTTP 回放，不调用付费模型；产品启动固定使用真实 CLI/API。
- 自定义 API 的真实网页文本、工具、审批允许/拒绝、同 run steer、停止与节点重启已实际验收。
- 群聊另有真实主答、成员定向、Bot 接力、六回合上限、失败后继续、同 run steer 与停止证据。
- [阶段记录](docs/progress.md)、[Hermes 调研与命令](docs/hermes-notes.md)、[私聊真实验收](docs/evidence/phase1-live-report.json)、[群聊真实验收](docs/evidence/phase2-live-report.json)。
- 原始技术和视觉文件完整保留，见 [参考索引](docs/references/README.md)。

原 HTML 原件与九块静态参考已保留；原稿视觉核对仍受查看方式限制。
新产品页面已在实际 Edge 检查 390、768、1440px、中英、浅深色及 reduced-motion。
OpenRouter 配置和托管文件路径已测，未声称进行其付费模型调用。
远程一键安装、PWA 安装和屏幕接管留待后续阶段。
