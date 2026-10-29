# 独立产品环境

该目录是远程产品部署定义。测试环境保持原样；产品 Relay 使用独立 Compose 项目、SQLite 数据目录和服务器节点用户。主机上仅 Relay 的 `127.0.0.1:4349` 对本机开放，Hermes Runs / management / VNC / CDP 保持 loopback。

## 部署顺序

1. 本地 `pnpm build`，按客户端文档用实际 HTTPS 域名构建安装包。
2. 本地构建 `docker build -f deploy/docker/Dockerfile -t nekodot-relay:product-0.1.0 .`，将镜像归档和 `dist/distribution` 上传到产品部署目录。
3. 复制 `compose.yml`；在服务器私有 `.env` 配置随机 `JWT_SECRET`、实际 `PUBLIC_URL` 和允许的 App origins。`data` 由容器用户 1000 读写，`downloads` 只读挂载。
4. 运行该项目的 `docker compose up -d`。示例复用当前 Caddy 的 `getplus_default` 网络，仅新增 Relay；不要重启其他服务。
5. DNS 指向服务器后，备份既有 Caddyfile、追加独立 site block、执行 `caddy validate`，仅 reload Caddy 配置。不要覆盖已有站点块。
6. 创建独立产品用户 `nekodot-product`。用新产品账号生成配对码，在该用户下执行产品安装脚本（可加 `--with-computer`）；使用该用户自己的 Hermes home、源码及 PM runtime。安装器生成持久 systemd user service，启用 linger。
7. 产品 Node 的 Relay 地址使用同机 loopback。产品账号和 Node 凭据不复制测试数据。若采用附带 system service 模板，应先停用同一产品用户的 user service，避免启动两个产品进程。

## Firebase

服务端凭据放在部署目录 `private/firebase-admin.json`，设置 `GOOGLE_APPLICATION_CREDENTIALS=/run/nekodot-private/firebase-admin.json`，仅该目录只读挂载。客户端配置与服务端项目一致。

Relay 只记录设备 token、账号归属及通知投递标识，不记录聊天正文。信号来自已经认证的 Node；通知含节点与会话标识及通用提示。审批必须在应用内操作。产品账号解绑节点会沿用既有路由撤销连接；退出 App 账号解除该安装实例的通知绑定。

## 运维验证

检查 `/health`、注册登录、配对、节点在线、原生 WS、文件和屏幕通道；重启仅针对产品 Relay / Node 服务。安装包缺失时不返回网页代替。公网域名未提供前可以准备 loopback 服务，但不得将其记为 HTTPS 或双端远程验收通过。
