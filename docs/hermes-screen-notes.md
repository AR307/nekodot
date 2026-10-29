# Hermes 原生屏幕接入 / Phase 4

## 接口与边界

- 实测 Hermes `bf0203a794`、Ubuntu 24.04 x64、官方 PM 的 `cua-driver 0.21.0`。Linux 驱动当前由 Hermes 标为 alpha。
- 一个 Bot 对应一个 profile。现有 loopback `hermes serve --isolated` 连接调用 `display.status/start/stop/observe`、`display.lease.acquire/release`，始终传入 `profile`。
- 屏幕、1440×900 显示、Xfce、TigerVNC Unix socket、浏览器数据和控制权文件由 Hermes 管理。nekodot 不分配显示号、CDP 或 VNC 端口，不重写工具执行和审批。
- `display.observe` 返回 30 秒单次原生票据与服务端 viewer。Node 使用票据连接 `/api/display/ws`；票据和 viewer 只留在连接内存，不写事件、数据库或日志。
- Relay 的独立票据为 60 秒单次使用，绑定账号、节点和 Bot。浏览器同源连接 `/ws/tunnel`，节点出站连接 `/ws/tunnel-node`，Relay 只转发二进制。

## 控制权与断线

- 接管只调用原生 acquire，交还只调用 release；均不调用 stop、steer 或发送聊天消息。
- noVNC 默认 `viewOnly=true`，原生 RFB 过滤器仍是服务端输入边界。网页确认自己的 viewer 持有控制权后才开放输入。
- 1000/1001 为主动离开，释放该 viewer 的 lease；异常断流保留 lease；4000 `control-taken` 为另一 viewer 接管，回到观看并重连。
- 短暂重连复用原管理连接签发的 viewer；身份失效时重新观察，不自动接管。刷新后可明确强制交还。
- 群聊打开时依次选择执行成员、最近发言 Bot、主答；打开后固定，显式选择才切换。

## 安装观察

安装器 `--with-computer` 在项目专属 home/runtime 内依次调用：

```sh
hermes computer-use screen install --yes
hermes computer-use install
hermes tools post-setup chromium
```

全部经过官方 CLI/PM。系统依赖必须先装：反向执行时 driver 因缺少 `libXi.so.6` 无法运行。Hermes 的屏幕包未包含 Chromium 的音频库；干净 Ubuntu 24.04 上实测浏览器退出 127，`ldd` 指向缺少 `libasound.so.2`，需系统包 `libasound2t64`。安装器补齐这一系统库或打印管理员命令，不安装另一份 Chromium。

缺少权限时不收集系统密码、不增加 sudo 配置。WSL、Windows、macOS 本阶段仅提供聊天。

## 证据

- `docs/fixtures/display-native.json`：真实原生 runtime/lease 快照，与 `display.status` 字段一致，包含停止的 hub 和两个运行中的独立 Bot；个人路径已替换。
- `docs/evidence/phase4-screen-*.png`：Edge 真实 Xfce/RFB 与双客户端接管。转发测试中的模拟字节不算真实画面验收。
- 真实模型、恢复、全新检出及未完成项目见 `docs/progress.md`。
