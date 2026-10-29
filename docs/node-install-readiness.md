# 节点安装完成后的上线确认

## 已确认的问题

2026-10-30 实际安装现场中，systemd 启动命令返回后，Hermes 仍在准备运行环境、启动 gateway 和管理后端。节点必须等这两项可用后才连接 Relay。

该现场从服务启动到 Relay 连接成功约 48 秒，随后节点日志出现 `online: true`，现有 Windows 客户端也实际显示「已同步」。这是安装器提前提示成功造成的启动期误判，不是需要重新配对或重建 profile。

## 修复

- 安装器使用 systemd 原生 `Type=notify`。只有 Node 收到 Relay 的 `hello.ok` 才通知服务就绪，安装命令随后显示「Node connected to Relay」。
- 正常准备期间显示正在等待 Hermes 和 Relay，启动超时为 5 分钟；启动失败时显示日志位置及当前日志，并保留身份、程序和历史供再次执行。
- 不向 Hermes 子进程传递 Node 服务的 `NOTIFY_SOCKET`，避免它的原生 gateway 通知提前宣告父服务就绪。
- 记录 Relay 连接错误与关闭原因；Hermes 初始化失败时清理本项目启动的子进程，使启动错误能正常返回。
- 不修改 Hermes 核心、用户全局配置或聊天协议。本次只更新公网安装脚本和 Node 单文件下载，不更改客户端包，也不重启已上线的用户节点或其他服务。

## 实际验证

- 独立 Linux 用户中重复安装真实 Hermes / Node：命令在 Relay 握手完成后返回，systemd 的状态为 active，StatusText 为已连接。
- 节点身份保持不变；使用错误的 Hermes YAML 配置重跑时，原生预检返回失败，安装器没有打印上线成功；恢复配置后服务重新上线。
- 14 文件 / 26 项测试通过，包括真实子进程验证项目环境隔离及通知归属；Edge 回归注册、配对、私聊、审批、steer 和停止旅程通过。
- 问题现场通过 SSH 读取日志，并直接读取现有 Windows 客户端的服务器状态，确认「已同步」。原始日志与个人地址不入库。

机器结果见 [node-ready-install.json](evidence/node-ready-install.json)。本次没有重新执行 Android 真机安装或真实屏幕回归，不扩展这些既有验收结论。
