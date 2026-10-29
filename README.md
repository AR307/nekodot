<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/nekodot-mark-dark.svg">
    <img src="docs/assets/nekodot-mark.svg" alt="nekodot" width="72" height="72">
  </picture>
</p>

<h1 align="center">nekodot</h1>

<p align="center">
  <strong>把你的 AI 小队，带到自己的电脑上。</strong><br>
  组建一支各有专长的 Bot 团队，单独聊，或拉进群里接力协作。<br>
  它们运行在你自己的电脑或服务器上，由 <a href="https://hermes-agent.nousresearch.com">Hermes Agent</a> 驱动。
</p>

<p align="center">
  <a href="https://github.com/AR307/nekodot/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/AR307/nekodot/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Node 24 LTS" src="https://img.shields.io/badge/node-24%20LTS-2F9E8F">
  <img alt="Status: developer preview" src="https://img.shields.io/badge/status-developer%20preview-E8603C">
</p>

<p align="center">
  <a href="https://nekodot.com">官网</a> ·
  <a href="https://github.com/AR307/nekodot/releases/tag/v0.1.0">下载 0.1.0</a> ·
  <a href="LICENSE">MIT License</a><br>
  <a href="#为什么是-nekodot">为什么是 nekodot</a> ·
  <a href="#功能">功能</a> ·
  <a href="#工作原理">工作原理</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#路线图">路线图</a>
</p>

![nekodot 桌面界面：Bot 列表、群聊接力与工具执行进度](docs/evidence/ui-u2-sidebar-1440.png)

<p align="center"><sub>两位 Bot 在群里协作整理周报：一位起草，再交给另一位核对数据来源。截图使用演示数据。</sub></p>

## 为什么是 nekodot

- **模型由你决定。** 接 OpenRouter，或任何 OpenAI 兼容接口，包括你自己平台上的模型。每个 Bot 可以用不同的模型。
- **数据留在你的机器上。** 聊天记录、Bot 配置和完整密钥都保存在你自己的电脑或服务器。电脑只主动向外连接，不需要开放任何端口。
- **不用碰配置文件。** 复制一行命令接入电脑，之后的模型、Bot、技能和插件都在网页里完成。浏览器多端同步，断线重连后接着看。
- **不重新发明 agent。** 每个 Bot 就是一个原生 Hermes profile，记忆、技能和工具循环都由 Hermes 完成。nekodot 专注于易用的界面、多端连接和多 Bot 协作。

## 功能

| 能力               | 说明                                                                                   |
| ------------------ | -------------------------------------------------------------------------------------- |
| **Bot 团队**       | 为每个 Bot 设定名字、头像、角色和模型；随时调整，已积累的历史与记忆保留。              |
| **私聊**           | 流式回复，展开查看工具过程；需要确认的操作有明确的审批卡片；运行中可以补充指令或停止。 |
| **群聊接力**       | 2–6 个 Bot 组成小组，用 `@handle` 指定谁来做；Bot 之间也能 `@` 对方交接工作。          |
| **记忆与自我改进** | 直接查看、编辑 Bot 的原生记忆，一键调用 Hermes 整理经验。                              |
| **定时任务**       | 在聊天里让 Bot 安排任务，在 Bot 详情中查看计划与执行记录。                             |
| **资料库**         | Bot 交付的文件统一收录，可预览、下载，或跳回当时的对话。                               |
| **Skills 与插件**  | 浏览 Hermes 扩展目录，按 Bot 安装、启用和配置；也支持从 Git、本地目录或 ZIP 导入。     |
| **实时屏幕与接管** | 观看 Linux Bot 的独立浏览器与桌面；接管鼠标键盘，再交还给 Hermes。                     |
| **多电脑、多端**   | 一个账号连接多台电脑；手机、平板、电脑上的浏览器看到同一份进度。                       |

### 看得见、管得住的执行过程

对话里不只有回答，还有 Bot 正在做的事。

- **看见过程**：实时文本、工具的开始与完成、等待确认的状态集中呈现。
- **随时补充**：运行中发送的消息由 Hermes 原生 steer 并入当前回合，已经完成的工作不会白做。
- **该你拍板时**：遇到需要授权的操作，Bot 会停下等你确认；等待期间你仍可以先写草稿。
- **随时叫停**：一个按钮停止当前执行；在群里则是「全部停止」，清空待接力的队列。
- **回来接着看**：刷新、切换设备或网络恢复后，历史与当前运行状态自动同步。

### 把任务交给一个小组

群组可以包含 2–6 个 Bot，并指定一位主答。没有 `@` 任何人时由主答开始；`@` 了谁，就按顺序交给谁。

> 这周的周报，@bibi 先整理草稿；@xiaoyan 帮忙核对数据来源。

Bot 在回复里 `@` 其他成员，就会把工作接力下去。为了避免无限循环，每条消息最多连续执行 6 个 Bot 回合，到上限会暂停并提示你。同一个群内一次只运行一个 Bot，不同群可以同时工作。同一个 Bot 在私聊和群聊之间共享上下文，群里讨论过的事，私聊时它也记得。

### 每个 Bot 都有自己的积累

从 Bot 名字打开详情：

| 页面   | 可以做什么                                                                                                                   |
| ------ | ---------------------------------------------------------------------------------------------------------------------------- |
| 详情   | 基本信息、定时任务的计划与执行记录。                                                                                         |
| 记忆   | 查看和编辑 `SOUL.md`（自身设定）、`MEMORY.md`（长期经验）、`USER.md`（对你的了解）；「整理记忆」调用 Hermes 原生 `/refine`。 |
| 资料库 | 搜索、筛选它交付的文件；预览图片、PDF 和文本，下载，或回到来源消息。                                                         |

交付的文件会单独保存一份副本，原工作文件之后再改动，也不会影响已经交付的版本。

### 打开它的屏幕，亲自接手

Linux VPS 节点安装时加上 `--with-computer`，就能从私聊、Bot 详情或群聊打开该 Bot 的原生屏幕。每个 Bot 使用独立的浏览器资料；默认只读观看，点击「接管」后才发送鼠标和键盘输入。

![原生浏览器完成表单后交还给 Bot](docs/evidence/phase4-real-handback.png)

「交还」释放 Hermes 原生控制权，不会自动重发任务；如果回合已经结束，在聊天中发送“继续”。关闭画面与停止聊天任务是独立操作。浏览器窗口的生命周期遵循 Hermes，持久浏览器资料不会因为关闭面板而清空。

屏幕目前支持 Linux VPS，访问页面需要安全上下文。局域网普通 HTTP 页面可聊天；产品 HTTPS 已接通，原生 App 的公网屏幕和手机真机接管仍待完整验收。

### 在任何屏幕上都好用

<table>
  <tr>
    <td width="34%" valign="top"><img src="docs/evidence/ui-u2-home-390.png" alt="手机首页：Bot 卡片与群聊列表"></td>
    <td valign="top"><img src="docs/evidence/ui-u2-palette-1440.png" alt="命令面板：搜索 Bot、群聊与常用操作"></td>
  </tr>
  <tr>
    <td valign="top"><sub>手机上是卡片式首页，右下角一键新建。</sub></td>
    <td valign="top"><sub>按 <kbd>Ctrl</kbd> <kbd>K</kbd>（macOS 上 <kbd>⌘</kbd> <kbd>K</kbd>）搜索 Bot、群聊和常用操作，回车直达。</sub></td>
  </tr>
</table>

支持中文与英文、浅色与深色主题，并遵循系统的「减少动态效果」设置。

## 工作原理

```text
浏览器（电脑 / 手机）
      │  HTTP · WebSocket
      ▼
   Relay ············ 账号、配对、在线状态与消息路由，不保存聊天内容
      ▲
      │  由节点主动连出，无需开放端口
      │
   Node ············· 你的电脑或服务器：聊天记录、Bot 配置、交付文件
      │  官方 CLI / API（仅本机 127.0.0.1）
      ▼
   Hermes ··········· 每个 Bot 一个独立 profile：会话、记忆、技能、插件
```

| 位置           | 保存什么                                                  |
| -------------- | --------------------------------------------------------- |
| 浏览器         | 只保存登录状态、语言等偏好；聊天内容从节点同步而来。      |
| Relay          | 账号与配对信息。消息和文件只经过它转发，不落盘。          |
| Node           | 聊天历史、运行记录、Bot 配置与交付文件。                  |
| Hermes profile | 该 Bot 的原生会话、记忆、技能、插件，以及托管的模型密钥。 |

完整的模型密钥只保存在节点上，网页里永远只显示后四位。nekodot 不修改 Hermes，只通过官方 CLI 与 API 集成，Hermes 升级不需要改动 nekodot。

请注意：模型请求会发往你配置的模型服务商。nekodot 让数据留在你自己的机器上，但它不是离线运行，也没有端到端加密。

## 快速开始

> [!NOTE]
> nekodot 目前是**开发者预览版**。Windows / Android 客户端已提供连接产品服务的预览包；也保留自行部署与本地 Web 开发入口。完整真机与安装验收仍在进行。

### 下载安装预览版

- [Windows x64 安装器](https://nekodot.com/downloads/nekodot-windows-x64.exe)：0.1.0，Windows 10 / 11；目前未做 Authenticode 签名。
- [Android arm64 APK](https://nekodot.com/downloads/nekodot-android-arm64.apk)：0.1.0，Android 10+；已签名，手机真机验收待完成。

App 自带界面，直接通过 HTTPS/WSS 连接远程 Relay；本机不用启动网页、Node、Hermes 或 SSH。注册不会自动取得其他账号的服务器访问权，仍需配对你自己的远程节点。当前真实验证与待验收范围见 [客户端验收记录](docs/side-stage-2-acceptance.md)。

### 准备

- 一台可以 SSH 登录的 **Linux x64** 服务器（推荐 Ubuntu 24.04），装有 Docker，用来运行 Relay。Bot 也可以直接跑在这台服务器上。
- 本机安装 **Node 24 LTS**、**pnpm 10.34.5** 和 OpenSSH 客户端。
- 一个模型服务的 API Key：OpenRouter，或任意 OpenAI 兼容接口。

### 五步上手

1. **部署 Relay。** 构建 Relay 镜像，上传到服务器后 `docker compose up -d`。Relay 只监听服务器的 127.0.0.1，不暴露到公网。详见 [部署文档](deploy/README.md)。
2. **打开网页。** 在本机执行：

   ```sh
   git clone https://github.com/AR307/nekodot.git
   cd nekodot
   pnpm install --frozen-lockfile
   pnpm dev:remote --ssh <your-ssh-alias>
   ```

   它通过 SSH 隧道连接远端 Relay，并在浏览器中打开 http://127.0.0.1:4318。加上 `--lan`，同一局域网内的手机也能访问。

3. **注册并添加电脑。** 选择「云服务器」或「这台电脑」，复制页面生成的一行安装命令，在目标机器上执行：服务器在 SSH 会话中运行；Windows 在启用了 systemd 的 WSL2 Ubuntu 24.04 中运行。安装器会把独立的 Node 24、Hermes 和节点服务装进 `~/.nekodot`，不改动系统环境。
4. **连接模型。** 电脑上线后，在设置中填入 OpenRouter Key，或 OpenAI 兼容接口的地址和 Key，获取可用模型。
5. **创建你的第一个 Bot。** 起个名字、选好头像和模型，写一句它负责什么，就可以开始对话了。需要协作时，再建一个群。

节点目前支持 **Linux x64** 与 **WSL2 Ubuntu 24.04 x64**。只想在本机跑起来看看、或参与开发，请看 [开发说明](docs/development.md)。

## 开发

技术栈：React 19 · TypeScript · Tailwind CSS v4 · motion · Zustand · Fastify · WebSocket · node:sqlite · Zod · Hermes Agent

```sh
pnpm install --frozen-lockfile
pnpm lint && pnpm typecheck && pnpm test
pnpm build
pnpm test:e2e
```

自动化测试使用录制的真实 Hermes 事件回放，不调用付费模型。本地运行、远程 Relay 调试、节点数据位置与测试策略见 [开发说明](docs/development.md)。

Windows / Android 原生客户端共用此界面，资源随安装包分发，Bot 运行在远程服务器。预览安装包、正式 HTTPS/WSS 与模拟器后台 FCM 已接通，完整真机旅程仍在联调；构建与当前限制见 [客户端说明](docs/client-development.md)。

```text
apps/web               React 网页与客户端同步
apps/client            Tauri 2 Windows / Android 宿主
apps/site              双语静态官网
apps/relay             账号、配对、WebSocket 路由与文件转发
apps/node              节点：持久化、Hermes 接入与群聊路由
packages/protocol      共享协议与 Zod schema
packages/tauri-plugin-nekodot Android FCM、生命周期与文件分享桥接
packages/fake-hermes   测试专用：回放录制的真实 Hermes 事件
deploy                 Relay 镜像、节点安装器与系统服务
design                 原始视觉参考与九块设计画板
docs                   开发说明、Hermes 调研、实施记录与截图
```

## 路线图

- [x] 私聊：流式回复、工具过程、审批、运行中补充指令、停止
- [x] 群聊：`@` 指定成员、Bot 之间接力、接力上限
- [x] 一行命令接入电脑（Linux x64 / WSL2），多端同步与断线恢复
- [x] Bot 详情：原生记忆、定时任务、资料库
- [x] Skills 与插件中心
- [x] 界面全面改版
- [x] 双语官网（`apps/site`）
- [ ] PWA：添加到手机主屏幕
- [x] 实时画面与接管：Linux VPS 原生浏览器、桌面与人工接管
- [ ] Windows / Android 完整交付验收（0.1.0 预览包已发布，公网聊天与模拟器后台 FCM 通过，真机等项目待验收）
- [ ] macOS 与 ARM 节点

## 致谢

- [Hermes Agent](https://hermes-agent.nousresearch.com)（Nous Research）：每个 Bot 背后的 agent 引擎。
- 界面字体 [Nunito](https://fonts.google.com/specimen/Nunito) 与 [JetBrains Mono](https://www.jetbrains.com/lp/mono/)，以 SIL Open Font License 1.1 授权。

## 许可证

采用 [MIT License](LICENSE)。第三方字体与依赖保留各自的许可证。
