# Side Stage 2：Windows / Android 客户端

## 已确定的边界

- Tauri 2 加载随安装包分发的现有 React 界面，Windows 和 Android 共用业务与同步代码。
- 客户端经 HTTPS/WSS 连接独立产品 Relay；Node 和 Hermes 仅运行于服务器，本阶段不安装本地 agent。
- 服务器使用独立目录、账号数据库和 Hermes home，保留全部测试现场。
- Android 后台提醒使用 Firebase FCM；Windows 使用托盘与在线系统通知。
- 交付 Windows x64 安装器与 Android arm64 签名 APK，不做商店、自动更新或 iOS。

## 实施顺序

1. 客户端工程、统一 Relay 地址与跨 origin 访问。
2. 文件、应用恢复、屏幕和 Android 通知原生桥接。
3. 独立服务器部署与公网 HTTPS 联调。
4. 原生安装包、真实双端旅程与独立检出验证。

## 真实联调前提

- 产品域名与 DNS 解析。
- Firebase Android 配置（applicationId 为 `app.nekodot.client`）及服务端凭据，仅保存在本地私有文件或服务器私有挂载。
- Google 服务可用的 Android 真机，用于后台通知、锁屏与触摸验收。

缺少上述条件时继续完成其余代码与可执行构建检查，但不得将公网连接、真实 FCM 或手机验收标为通过。

## 进度

- 2026-10-29：开始实施；现有 UI 改版未提交文件已识别，将保留其内容，只提交本阶段改动。
- 已建立 Tauri 宿主、统一连接入口及平台桥接；Windows NSIS 和 Android x86_64 调试构建成功，并在实际原生宿主打开。
- 独立产品 Relay、系统用户和 Hermes home 已在授权服务器运行；通过本地验收通道完成真实自定义 API 私聊与两个 Bot 的群聊，屏幕依赖已安装。该结果不等于公网 HTTPS 或 App 远程旅程通过。
- 正式域名、Firebase 文件和 Android 真机仍待提供；不发布连接占位地址的正式安装包。阶段验收详见 `progress.md` 和 `evidence/side-stage-2-*.json`。
- Windows x64 NSIS、Android x86_64/arm64 调试构建已验证；Android 模拟器系统返回、文件选择/保存与分享入口通过，arm64 包未在真机安装。Android 发布签名密钥已生成并仅保存在本地私有目录，未用于发布占位地址安装包。
- 用户确认域名与 Firebase 配置稍后提供；公网路由、真实 FCM、正式安装器及双端旅程保持待完成。开发与产品服务的已验证结果不受此等待影响。
