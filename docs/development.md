# 开发说明

面向参与开发的人。产品介绍见 [README](../README.md)，Relay 镜像、节点安装器与系统服务见 [部署文档](../deploy/README.md)。

## 环境

- **Node 24 LTS**：节点和 Relay 依赖 `node:sqlite`，不要用 Node 22 及更早版本运行。
- **pnpm 10.34.5**（见 `package.json` 的 `packageManager`）。
- **Microsoft Edge**：端到端测试使用本机 Edge；缺少时运行 `pnpm exec playwright install msedge`。
- Windows 上若已在 `.runtime/` 放置项目专用的 Node 24，可执行 `. ./scripts/activate.ps1` 仅为当前 shell 启用它，不改动全局环境。Windows 与 WSL/Linux 各自安装 `node_modules`，不要共享。

## 常用命令

```sh
pnpm install --frozen-lockfile
pnpm lint        # ESLint + Prettier
pnpm typecheck
pnpm test        # Vitest：协议、Relay、节点、Hermes 回放
pnpm build
pnpm test:e2e    # Playwright + Edge 完整用户旅程
```

群聊与扩展两条端到端旅程直接加载 `apps/web/dist`，改动界面后请先执行 `pnpm --filter @nekodot/web build` 再跑 `pnpm test:e2e`。

## 本地运行

Relay 需要一个私有的 `JWT_SECRET`，只在本地 shell 中设置，不要写进源码或提交：

```powershell
$env:JWT_SECRET = '<本地生成的随机值>'
pnpm dev
```

`pnpm dev` 启动 Web（http://127.0.0.1:4318）与 Relay（http://127.0.0.1:4319）。Relay 默认只监听 loopback，可选环境变量：`PORT`、`HOST`、`PUBLIC_URL`、`DATA_DIR`、`WEB_DIR`。构建后设置 `WEB_DIR=apps/web/dist` 并运行 `node apps/relay/dist/index.js`，即可由 Relay 同源提供网页与 WebSocket。

节点在网页生成配对码后单独启动：

```sh
pnpm node:pair --relay http://127.0.0.1:4319 --code XXXX-XXXX
pnpm node:run
```

`pnpm node:run` 使用已安装的官方 Hermes CLI。从 Hermes 源码运行时，额外指定源码目录与官方 PM runtime：

```sh
pnpm node:run --hermes-source /path/to/hermes-source --hermes-runtime /path/to/pm-runtime
```

## 连接远程 Relay

Relay 部署在服务器上并只监听服务器的 loopback 时，用本机已有的 SSH 配置连接：

```sh
pnpm dev:remote --ssh <your-ssh-alias>
```

它在本机 127.0.0.1:4329 建立到远端 Relay 的 SSH 隧道，并在 4318 启动、打开网页；API、WebSocket 与节点安装包下载都经网页同源代理。退出命令会关闭它启动的网页与 SSH 进程。加上 `--lan` 可让同一局域网内的手机访问本机网页，Relay 隧道仍只绑定 loopback。

## 节点数据

- 节点数据默认在 `~/.nekodot`，可用 `NEKODOT_HOME` 指定其他目录。Hermes home、各 Bot 的 profile、SQLite、节点凭证和日志都在其中。
- nekodot 使用独立的 Hermes home，不影响你自己的 `~/.hermes`；Hermes gateway 只监听 `127.0.0.1:18642`。
- 完整的提供方密钥只写入 Hermes 托管的 `.env`，网页与节点数据库只保留后四位。
- 根目录的 `.env.example` 仅供真实 Hermes spike 脚本使用；产品的提供方在网页中配置。

## 测试策略

- 自动化测试不调用付费模型：`packages/fake-hermes` 通过 HTTP 回放 `docs/fixtures` 中录制的真实 Hermes SSE 与状态。该包只作为开发依赖，产品代码不引用。
- 产品运行时始终使用真实的 Hermes CLI 与 API。真实模型的验收与回放验收分开记录，见 [实施进度](progress.md)。
- `tests/browser/screens-live.spec.ts` 只在提供本地 `NEKODOT_SCREEN_ACCEPTANCE_FILE` 时运行，连接独立的真实 Linux 节点。文件包含 `url`、登录 `token`、`nodeId` 及 `bots[].bot.botId` / `bots[].conversation.conversationId`，不得提交。普通 E2E 明确跳过这一项，不以回放替代屏幕验收。

## 文档索引

- [实施进度与验收记录](progress.md)
- [Hermes 接入调研与命令](hermes-notes.md)
- [原生屏幕接口与限制](hermes-screen-notes.md)
- [Phase 4 真实验收](phase4-acceptance.md)
- [原始技术与视觉参考](references/README.md)
- [设计画板](../design/)
- [更新记录](../Summary.md)
