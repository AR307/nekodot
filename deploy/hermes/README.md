# Hermes 原生 Webhook 最小修复

0.3.0 正式产品环境使用 Hermes v0.22.5（官方基线 `bf0203a794a0`），外加此前独立验收并获用户授权的 listener home 修复。补丁来源为本地 Hermes 提交 `67e4f384b8929926438c9bb014f371d0238a532a`；没有改变 Agent、审批或任务执行逻辑。

## 影响范围

官方该版本在共享 gateway 将动态 webhook 路由到其他 profile 时，会错误从目标 profile 重新读取 listener 的订阅文件，可能出现原生 `not_found` / HTTP 503。修复仅在 listener 构造时固定订阅文件路径，后续仍按原生 hot reload 读取。

正式产品服务器已随本次发布安排部署。**Node 安装器和自动更新器不会擅自修改其他服务器的 Hermes 核心**；自部署节点若使用上述受影响版本并需要跨 profile Webhook，应由管理员安排同一修复。普通聊天与 Session 功能不需要此补丁。

## 自部署操作

1. 先确认节点没有执行中的任务，保留原 Hermes 源码、home 和 Node 数据库备份，停止该节点自己的服务。
2. 在项目专属 Hermes 源码目录检查并应用本目录的 `webhook-listener-home.patch`：

   ```sh
   git apply --check /path/to/webhook-listener-home.patch
   git apply /path/to/webhook-listener-home.patch
   ```

3. 将修改作为独立本地提交保留，启动原节点服务，用真实 Webhook 验证接收、执行与私聊回投。

若检查失败，不要强行覆盖源码；先检查当前版本是否已包含修复或有本地改动。补丁不安装依赖、不清空 profiles、不创建第二套任务引擎。
