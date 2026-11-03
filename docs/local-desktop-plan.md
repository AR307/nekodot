# 本地电脑运行：实施计划

目标、范围与验收标准以用户确认的方案为准；本文只记录实现层面的决定，随模块推进更新。

## 已核实的 Hermes 基线

- 集成基线为 Hermes **v0.22.6**：标签对象 `49138a6058`，提交 `f0d94882e89ab8d4098b5bb2f166adfb9ee0a0ab`。
  安装脚本按该提交从 `raw.githubusercontent.com/NousResearch/hermes-agent/<sha>/scripts/` 下载，客户端内置脚本 sha256 校验。
- 官方分阶段协议（protocol 1）：`prerequisites, repository, venv, python-deps, config, products, setup, gateway, complete`。
  每阶段输出最后一行 `{"ok","stage","skipped"[,"reason"]}`；Windows 用 `install.ps1 -Stage X -Json`，POSIX 用 `install.sh --stage X --json`。
  版本固定用 `-Commit <sha> -Branch main`，不传 `-Channel`。
- 不执行 `setup`（交互配置）与 `gateway`（会安装系统服务/计划任务）。
- `products` 阶段在 Windows 会无条件改写用户 PATH，在 POSIX 会改写 shell 启动文件。为保持用户既有 Hermes 与环境不变，本阶段改为直接执行它内部调用的
  `<bootstrap python> -I -B -X utf8 hermes_cli/source_completion.py --source <checkout>`，不执行 `Publish-UserCommand`；POSIX 先在配置写入
  `cli.expose_on_path: false`。其余阶段原样调用官方脚本。
- 安装进程设置 `UV_PYTHON_INSTALL_DIR` / `UV_CACHE_DIR` 到运行环境目录，避免 bootstrap Python 落到 uv 默认的用户目录；运行时设置
  `HERMES_GATEWAY_LOCK_DIR` 到账号数据目录。
- PM 依赖状态按数据根划分；检出位于 `<owner home>/hermes-agent` 时，其他 `HERMES_HOME` 借用 owner 的解释器与依赖（`pm/environments.py`
  `owning_home_root`）。因此运行环境安装一次，多个账号共用。

## 目录布局

用户在安装第一步分别选择两个目录（默认位于系统应用数据目录，可改到任意本机固定磁盘），只有指针文件留在系统应用数据目录。

```
<运行环境目录>/                 一台电脑一份，多账号共用
  node/node-v24.22.1-<os>-<arch>/
  hermes/                       安装用 owner HERMES_HOME：tools/、installs/、cache/
  hermes/hermes-agent/          官方检出，固定 v0.22.6
  runtime.json                  已完成阶段、Hermes 提交、Node 版本
<数据目录>/accounts/<userId>/   NEKODOT_HOME，按账号隔离
  node.json  node.db  logs/
  bin/nekodot-node.cjs          沿用现有自动更新与 pending/tried/rejected 回滚标记
  hermes/                       账号 HERMES_HOME：profiles、记忆、技能、会话、vault、浏览器资料
  gateway-locks/
<系统应用数据目录>/local-runtime.json   {runtime, data}
```

- 目录须为本机固定磁盘上的空文件夹或已有的 nekodot 目录；检查可写、剩余空间，不允许位于客户端安装目录内。
- Windows 上新建的数据目录设置仅当前用户、SYSTEM、Administrators 可访问且向下继承的 ACL。
- 已有内容直接复用：运行环境按 `runtime.json` 判断，账号数据按 `node.json` 判断，不重复安装或重新配对。
- 安装后不提供目录整体搬迁；设置页显示路径并可打开。

## 模块

1. **Node 桌面托管**：`run --desktop` 监听 stdin（关闭或 `stop` 行即优雅停止），stdout 输出 `{"desktop":...}` 状态行；信号处理在 Hermes 启动前注册。
   Hermes 通过明确的 launcher 路径启动（Windows `hermes.exe`，POSIX `.hermes/bin/hermes`）。本机桥接：POSIX 为 Unix socket（过长时退到私有临时目录），
   Windows 为每次启动随机命名的 named pipe；gateway 控制通道在 Windows 按 Hermes 规则计算 `\\.\pipe\hermes-gateway-<hash>`。
   Windows 停止时先 `gateway stop --yes` 再结束进程。桌面节点不提供 Bot 独立屏幕。文件交付识别 Windows 路径。
2. **客户端本机运行模块**：目录选择与检查、下载 Node 24（SHASUMS256 校验）与 Node bundle、执行 Hermes 阶段并解析结果帧、写 `runtime.json`；
   启动、停止、退出码 75 重启与回滚标记；Windows Job Object（kill on close），POSIX 依赖 stdin 管道与 Node 停止所属进程。
3. **首次使用与生命周期界面**：运行位置选择（Android 只保留远程）、安装进度与真实错误/重试、最后申请配对码并自动配对与选中；
   打开应用自动启动；退出应用、退出/切换账号先停止本机实例，有本机任务时确认。
4. **Windows 真实闭环验收**。
5. **computer_use 与能力信息**：节点能力区分本机运行、原生桌面操作、独立屏幕；权限与驱动状态，macOS 授权只在本机执行。
6. **macOS / Linux 宿主**：runner、Rust 目标、托盘/菜单/退出、通知、单实例；可获得的构建结果与未验项分开记录。
7. **发布与交付**：版本清单增加 macOS DMG、Ubuntu DEB 与运行时版本，下载入口与文档。

## 验收环境限制

- 当前只有 Windows 真实环境；macOS 与 Ubuntu 桌面未具备前不标记通过。
- 本机 D 盘剩余约 2.5 GB、C 盘约 27 GB，真实安装验收前需确定使用的磁盘。
