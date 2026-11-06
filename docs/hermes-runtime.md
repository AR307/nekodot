# Hermes 后端运行包

## 边界

- 配方：`deploy/hermes-runtime-recipe.json`，当前官方 v0.22.6，产品包 v0.22.6-r1。
- 保留官方 Agent、PM、管理 HTTP、canonical WebSocket、Python TUI gateway 后端、Skills、插件、MCP、Cron/Webhook。
- 不携带 Git 历史、测试环境、官网、Electron/TUI/Web 前端及其构建依赖。`hermes_cli/web_*` 与 `tui_gateway` 不是前端，必须保留。
- Python 使用官方 `all` 常用依赖集合，不是把每个可选 extra 都装上。保留 Chromium、cua-driver、FFmpeg；Linux 桌面系统库仍由官方安装入口准备。
- 运行包更新随 Nekodot 配方管理，用户机器不 clone Hermes 或构建前端。不更改 Agent 循环及资源策略。

## 构建与分发

在对应的 Windows x64、Linux x64、macOS arm64 主机上，以配方中的固定 commit 检出官方 Hermes；构建输出目录必须是新目录。

```sh
python scripts/build-hermes-runtime.py --source /build/hermes-agent --out /build/r1/payload --cache /build/cache
# 已准备好的官方工具 store 可以复用；缺少的工具仍由 PM 获取到新输出。
python scripts/build-hermes-runtime.py --source /build/hermes-agent --out /build/r2/payload --cache /build/cache --tools /build/r1/payload/tools
```

脚本使用官方发行快照、PM、隔离的 PM Python 环境和 Agent assembler。前端列表为空；既有获准补丁只应用于新快照，不修改输入 checkout 或已安装环境。补丁保留长路径复制、动态 webhook profile 路由和 Cron 授权规则；清单记录原提交。

产出为 `nekodot-hermes-<version>-<target>.tar.gz` 与 `<target>.json`。目标系统的包不能用跨平台构建代替实机验收。

```sh
pnpm build:distribution
node scripts/stage-hermes-runtime.mjs /build/windows/win32-x64.json /build/linux/linux-x64.json
# 隔离验收可指定 --output /qa/downloads，不部署正式下载目录。
```

Relay 提供 `/downloads/hermes/<version>/<target>.json` 和 `.tar.gz`，支持 HTTP Range。客户端流式写盘，中断保留 `.part`，重试下载剩余部分；解压到新目录后切换，失败目录保留。

安装包发布前必须先准备对应后端运行包。现有产品发布脚本检查 Windows/Linux 包；发布 macOS 客户端时同时要求 macOS 后端包。此步骤只准备本地发布材料，不自动发布。

## 安装布局

```text
runtime/
  hermes-runtimes/v0.22.6-r1/   # 只读基线、Python、PM、工具
  node/                       # Nekodot 私有 Node 24
  cache/                      # 同一安装共享的依赖下载缓存
  downloads/                  # 包与可续传的未完成下载
data/accounts/<userId>/
  hermes/                     # 账号设置、原生 profiles、独立 PM generations
  ...                         # 原有节点身份、数据库、工作目录
```

新账号直接使用包内基线。新增插件依赖由官方 PM 在该账号内建立可变环境，不修改共享基线，不合并不同账号的 Python 环境。Hermes PM 使用其 home 下的 `cache`，因此新账号用 Windows junction / POSIX symlink 指向安装级缓存；只设 `UV_CACHE_DIR` 不足以影响 PM。已有缓存目录不搬动。

VPS 安装使用同一 Linux 包与官方 launcher，并保留现有 systemd user service、账号身份和历史。普通 Linux VPS 默认准备屏幕系统库；WSL 不启用 VPS 桌面。

## 旧安装

不自动清理。Git 历史、前端 `node_modules`、旧工具/环境及下载缓存仅列为待盘点候选；要确认当前 launcher、PM 环境和工具引用后，再单独申请移入回收目录。profiles、浏览器资料、会话数据库、插件状态和用户文件不是清理项。

## 验收口径

分别记录下载字节、展开字节、磁盘占用、安装耗时与采样 RSS。构建时缓存命中、loopback 下载、实际 VPS 解压和完整冷安装不可混算。现有安装包含历史验收环境时不能算作默认安装必需体积。真实能力及未验范围见 `hermes-runtime-acceptance.md`。
