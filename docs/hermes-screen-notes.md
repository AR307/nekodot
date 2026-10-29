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
hermes pm install chromium
```

全部经过官方 CLI/PM。系统依赖必须先装：反向执行时 driver 因缺少 `libXi.so.6` 无法运行。Hermes 的屏幕包未包含 Chromium 的音频库；干净 Ubuntu 24.04 上实测浏览器退出 127，`ldd` 指向缺少 `libasound.so.2`，需系统包 `libasound2t64`。安装器补齐这一系统库或打印管理员命令，不安装另一份 Chromium。

独立用户全新安装核实：官方稳定版 `bf0203a794` 的 post-setup 列表没有 `chromium`，直接使用官方 `pm install chromium`。本地参考源码的较新 post-setup 名称不能作为该稳定版的安装依据。

缺少权限时不收集系统密码、不增加 sudo 配置。WSL、Windows、macOS 本阶段仅提供聊天。

## Runs 工具与浏览器资料

- `screen.start` 配置 `browser.headed=true`、`browser.auto_start=false` 和原生 geometry；Runs 使用的工具集位于 `platform_toolsets.api_server`，在既有集合中加入 `computer_use`。通用 `toolsets` 不是该 API 适配器的读取入口，首轮真实调用因此没有获得工具；修正后通过原生审批完成桌面输入与保存。
- 配置不重建运行中的 agent；新的工具配置供后续回合使用。屏幕仍由用户手动启动。
- 稳定版实测中，回合结束或节点服务退出可能关闭 agent 创建的浏览器窗口。nekodot 不另加浏览器生命周期；不能将持久资料保留表述为标签页一直存在。
- 两个 profile 的 cookie/localStorage 测试标记相互隔离。Node 重启后，同 profile 的新原生浏览器回合仍读到旧标记，另一 Bot 读到空值；测试只访问本地无害表单，没有使用网站账号。
- 同 run 接管使用正在执行的原生浏览器。人工输入后交还，Bot 读取原值并提交一次；若 Hermes 已结束回合，则由用户聊天发送“继续”，页面不自动重跑。

## 证据

- `docs/fixtures/display-native.json`：真实原生 runtime/lease 快照，与 `display.status` 字段一致，包含停止的 hub 和两个运行中的独立 Bot；个人路径已替换。
- `docs/evidence/phase4-screen-*.png`：Edge 真实 Xfce/RFB 与双客户端接管。转发测试中的模拟字节不算真实画面验收。
- `docs/fixtures/screen-handover.sse` 与 `screen-handover-state.json`：真实同 run 接管的事件和 completed 状态。提供方地址、模型配置、密钥与个人路径已脱敏。
- 桌面首次完成后的 run 在 gateway 重启后已不在原生内存 Runs 列表，未将事后生成内容冒充原始 SSE。真实工具过程、网页画面、实际文件与后续只读 GUI 复核共同记录这一项。
- 真实模型、恢复、全新检出及未完成项目见 `docs/progress.md`。
