# 独立产品环境

该目录是远程产品部署定义。产品 Relay 使用独立 Compose 项目、SQLite 数据目录和服务器节点用户；仅 `127.0.0.1:4349` 对本机开放。Hermes canonical WS、管理接口和屏幕服务保持 loopback。

## 部署顺序

1. 本地 `pnpm build`，然后用仓库及服务器外保存的发布私钥执行 `NEKODOT_RELEASE_KEY_FILE=/private/nekodot-release.pem pnpm release:node`。将盖章后的 Node bundle 与 JSON 清单作为同一批产物；先部署 Relay/Node，再按客户端文档用实际 HTTPS 域名构建及分发安装包。普通构建不自动成为发布版，不能漏掉盖章步骤。
2. 本地构建 `deploy/docker/Dockerfile` 的候选镜像，将镜像与 `dist/distribution` 作为同一批产物。不要覆盖已发布的版本化产物。
3. 官网由既有 Caddy 从 `/srv/nekodot-site` 只读提供，Relay 不挂载官网。`.env` 中保留原 `JWT_SECRET` 与私有配置，设置 `PUBLIC_URL=https://api.nekodot.com`、`CLIENT_ORIGINS=https://www.nekodot.com`。`data` 继续由容器用户 1000 读写，数据库不迁移。
4. 运行该项目的 `docker compose up -d`。示例复用当前 Caddy 的 `getplus_default` 网络，仅新增 Relay；不要重启其他服务。

SMTP 私有 JSON 放在服务器 `private/`，沿用 `SMTP_CONFIG`、Firebase 与签名配置。`TRUSTED_PROXY` 只配置实际代理地址。不要打印凭据或重置会话。

5. 正式上线须另获授权。协调切换窗口后，配置 `www`、`api` 的 DNS/证书及 `Caddyfile.example` 中的三个站点块；只 reload Caddy，不覆盖其他站点。
6. 已有 VPS 从新 API 下载并运行安装脚本；官方根域地址一次改为 API 域名，保留 `nodeId`、`nodeToken` 与原配置备份，自建 Relay 不改。已有桌面安装由新客户端完成同一地址更新，再启动原账号的 Node。
7. 账号、配对、数据库、profiles、浏览器资料与历史留在原位置。不复制验收账号或重跑已完成任务。每个产品用户只保留一个既有 Node 服务。

后续更新同步发布 Node bundle 与清单；`latest.json` 最后切换。本次不保留旧 API：根域服务路径返回 410，其他官网地址跳转 `www`。旧客户端须从新官网下载，旧 Webhook 调用方须更换域名；任务 ID 与密钥不变。不能依赖旧更新入口。回退材料仅供经授权的整体回退，不添加运行时旧域名回退。

## Firebase

服务端凭据放在部署目录 `private/firebase-admin.json`，设置 `GOOGLE_APPLICATION_CREDENTIALS=/run/nekodot-private/firebase-admin.json`，仅该目录只读挂载。客户端配置与服务端项目一致。

Relay 只记录设备 token、账号归属及通知投递标识，不记录聊天正文。信号来自已经认证的 Node；通知含节点与会话标识及通用提示。审批必须在应用内操作。产品账号解绑节点会沿用既有路由撤销连接；退出 App 账号解除该安装实例的通知绑定。

## 运维验证

检查 `/health`、注册登录、配对、节点在线、原生 WS、文件和屏幕通道；重启仅针对产品 Relay / Node 服务。安装包缺失时不返回网页代替。公网域名未提供前可以准备 loopback 服务，但不得将其记为 HTTPS 或双端远程验收通过。
