# Node 离线：WebSocket 握手恢复修复

## 2026-11-03 现场与原因

- 用户在 Android 客户端看到 Node offline。正式 Relay 与产品 Node 正常；用户 VPS 的 nekodot 服务仍为 active，但已不在 Relay 的在线连接中。
- 该节点最后一次断流为 2026-11-02 14:58:39 UTC。重连后的 TCP 连接持续约 11 小时没有继续收发，停止服务时明确记录 `WebSocket was closed before the connection was established`。
- `connectRelay` 原来没有配置 WebSocket 开启握手超时。连接停在建立阶段时，不触发 error/close，已有指数退避重连也就无法继续；systemd 看到存活进程，不会自行重启。

## 最小修复

- 使用现有 ws 库的 `handshakeTimeout`，复用协议已有 30 秒请求超时。
- 超时后由 ws 触发错误和关闭，继续使用原有 1/2/4 秒至最多 30 秒重连，不增加任务队列、兼容路径或 Agent 状态机。
- 只更新 Node；Flutter 安装包、Relay 协议、Hermes 核心和用户数据不变。

## 验证与部署

- 使用真实 TCP 代理和项目 Relay：第一次连接接受 TCP 但不响应升级，30 秒后 Node 超时并重连，第二次完成认证；`/api/me` 显示节点在线，`sync.snapshot` 成功读取原配对的持久 Bot 数据。
- Node 24 上连接场景测试通过；TypeScript、限定文件 ESLint 和 Prettier 检查通过。首次误用本机默认 Node 22 执行测试因不支持 `node:sqlite` 退出，改用项目已有 Node 24 后通过。
- 在真实 Linux Node 24 运行时完成单文件语法及 CLI 启动检查。补丁版本 `20261103022508` 已更新正式下载分发，并安装到发生问题的 VPS；原 bundle 保存在各自版本目录的 backup 内。
- 更新前确认该节点没有活跃私聊或群聊任务。只重启 nekodot 节点服务，保留身份、profiles、历史、浏览器资料及其他服务；Relay 和 App 安装包不重启、不重建。
- 本次验证针对真实节点连接及读取链路，没有运行新的模型任务，也不将其记为 Android 真机界面复验。
