# 开发说明

产品介绍见 [README](../README.md)，部署见 [独立产品环境](../deploy/product/README.md)。

## 工程与环境

- 产品界面只有 `apps/native` 的 Flutter 客户端，Windows / Android 共用界面和同步层，不加载远程 HTML。
- `apps/relay` 提供账号、节点路由、文件、屏幕和通知通道；`apps/node` 连接官方 Hermes；`packages/protocol` 定义协议。
- `apps/site` 是官网，继续保留。Relay 可通过 `SITE_DIR` 提供官网静态文件，不再提供旧 SPA 的任意路由回退。
- Node 24 LTS、pnpm 10.34.5；Flutter、Rust、平台 SDK 使用本项目已有工具链。Windows 可以运行 `. ./scripts/activate.ps1`，只改变当前 shell。

## 常用命令

```sh
pnpm install --frozen-lockfile
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm native:analyze
pnpm native:test
pnpm native:windows
pnpm native:android
```

## 本地运行

Relay 使用私有 `JWT_SECRET`，`pnpm dev` 只启动 Node / Relay 开发进程，不启动网页。Relay 默认 loopback，可配置 `PORT`、`HOST`、`PUBLIC_URL`、`DATA_DIR`。Flutter 通过构建参数 `RELAY_URL` 连接测试 Relay；生产使用 HTTPS/WSS，不要求用户启动开发服务器或 SSH。

```sh
node scripts/flutter.mjs flutter run -d windows --dart-define=RELAY_URL=http://127.0.0.1:4319
pnpm node:pair --relay http://127.0.0.1:4319 --code XXXX-XXXX
pnpm node:run
```

客户端可使用现有本机安装入口；也可以连接独立 VPS Node。各 Bot 仍使用独立 Hermes profile。源码运行 Hermes 时使用官方 PM runtime，不用裸 pip 修改环境。

## 真实验收

`apps/native/integration_test` 中的旅程直接运行候选 Flutter 客户端。使用独立测试账号、真实 Node/Relay、官方 Hermes 和真实模型；私有参数只写在本地被忽略的 `.runtime` 目录。截图和脱敏结果与模拟器、真机范围分别记录。

```sh
node scripts/flutter.mjs flutter test integration_test/ui_refinements_journey_test.dart -d windows --no-pub --dart-define-from-file=C:/private/qa.json
pnpm native:emulator
```

Android 固定复用 `NekodotNativePhase3`，不创建新 AVD、不 wipe-data。Flutter 命令通过 `scripts/flutter.mjs` 使用现有 SDK；模拟器不能替代真机验收。

Vitest 和 Flutter 单元/组件测试只作辅助。`packages/fake-hermes` 是开发依赖，不进入产品执行路径，也不能作为真实模型通过的依据。旧 Web/Tauri 与专用浏览器测试已移到本地回收目录，历史验收文档和证据保留。

## 数据与文档

Node 数据默认在 `~/.nekodot`，可用 `NEKODOT_HOME` 指定。客户端凭据使用系统安全存储，模型凭据由 Hermes profile 保存，不提交日志、密钥、数据库或浏览器资料。

- [进度与验收](progress.md)
- [Hermes 接入](hermes-notes.md)
- [参考资料](references/README.md)
- [更新摘要](../Summary.md)
