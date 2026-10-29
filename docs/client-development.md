# Windows / Android 客户端

客户端位于 `apps/client`。Tauri 仅管理窗口、平台文件入口、通知和生命周期；React、聊天同步、noVNC 和中英词典全部来自 `apps/web`。客户端不包含 Hermes 或 Node 服务。

## 构建

使用 Node 24、pnpm 10、项目的 Rust 1.90 工具链。Windows 需要 MSVC / Windows SDK；Android 需要 JDK 21、Android SDK 36、NDK 和 Rust Android targets。`JAVA_HOME`、`ANDROID_HOME`、`NDK_HOME` 只在当前构建进程设置。

```powershell
pnpm install --frozen-lockfile
$env:NEKODOT_RELAY_URL = 'https://your-product-domain.example'
pnpm client:windows
pnpm client:android
```

生产构建要求 HTTPS Relay origin，不接受页面地址、HTTP 公网地址或 SSH 参数。Web 回归输出在 `apps/web/dist`，原生包资源输出在每次构建独立的 `.runtime/side-stage-2/frontend-*`，两者不会覆盖。Windows 产物为 NSIS x64 EXE；未配置发布证书时没有 Authenticode 签名。

Android 固定 `app.nekodot.client`，最低 API 29。首次在干净检出初始化 Android 工具链时可执行 `pnpm --filter @nekodot/client tauri android init`；仓库已保留 Android 工程和项目配置，**不要用重新生成的模板覆盖 Gradle 签名和原生配置**。常规构建直接使用 `client:android`。

将 Firebase 的 `google-services.json` 放在 `.runtime/side-stage-2/private/google-services.json`，与 applicationId 一致。release 构建同时要求：

- `NEKODOT_ANDROID_KEYSTORE`：本地签名文件绝对路径。
- `NEKODOT_ANDROID_KEY_ALIAS`：签名 alias。
- `NEKODOT_ANDROID_STORE_PASSWORD` 和 `NEKODOT_ANDROID_KEY_PASSWORD`：仅当前进程中的密码。

配置、签名文件和密码均不提交。构建成功后将正式产物复制到 `release/` 及 `dist/distribution/`；Relay 下载入口分别为 `/downloads/nekodot-windows-x64.exe`、`/downloads/nekodot-android-arm64.apk`。文件尚未发布时明确返回 404。

不验证推送的 Android 宿主开发可以使用 `pnpm client:android --debug --target x86_64`；arm64 调试使用 `--target aarch64`。调试构建没有 Firebase 文件时保留明确的通知不可用状态，不生成正式发布包；release 仍要求 Firebase 配置和签名。两类构建都需要配置 HTTPS Relay 地址，测试地址构建只能用于宿主检查。

## 平台行为

- Windows 单实例，关闭窗口隐藏到托盘，托盘明确退出才结束客户端；窗口大小与位置由官方插件保存。
- Android 使用系统文件选择和保存；目录导入使用 ZIP。分享通过系统 chooser，PDF 在共享 PDF.js 组件预览。
- 草稿只保存在进程内，切会话、页面和后台仍保留；退出账号清空。聊天正文没有离线持久副本。
- Android 后台关闭业务 WS 和屏幕观看，禁用输入；前台复用现有同步，不重发任务，不自动接管。
- FCM 使用 Firebase SDK；关闭通知权限、缺少 Google 服务或缺少服务器配置时显示原因，不启动另一套推送。
- Windows 系统通知仅承诺客户端进程在线期间；Android 系统“强行停止”不承诺送达。

## 真实验收边界

调试构建和模拟器只证明编译、原生桥接及对应场景。正式联网、FCM 和手机屏幕旅程必须在实际域名、Firebase 项目和设备上验证。没有这些前提时不发布指向占位地址的正式安装包。
