# nekodot native · 0.2.0 development

Windows / Android 的 Flutter 客户端。界面由 Flutter 绘制，屏幕通过
`vnc-rs → flutter_rust_bridge → ui.Image` 解码与显示，不包含 WebView。
Hermes 和 Node 仍在服务器运行，客户端不安装或运行本地 agent。

**这是开发工程，不是已发布的 0.2.0。** 现有客户端和线上服务继续工作；
不会因本工程存在而替换安装包或部署未验收的账号接口。

## 结构

- `lib/data/client.dart`：HTTPS、业务 WSS、RPC、snapshot/since/seq/offset、草稿及安全登录存储。
- `lib/features/`：账号、节点、Bot、聊天、记忆、文件、扩展与设置。
- `lib/screen/`、`rust/`：认证 WSS、RFB 解码、原生控制权与输入。
- `lib/platform/`：Windows 托盘/窗口、Android FCM 和系统通知。
- `lib/ui/design.dart`：黑白 tokens（Windows 实色、Android 毛玻璃）、圆形猫头像与页面转场；`lib/ui/parts.dart`：共用组件。
- `integration_test/`：显式启用的真实远程旅程；日常测试不调用模型。

只持久保存登录态、语言、选择项与系统设置。聊天正文来自服务器，草稿只在当前进程保留。
一个 Bot 仍对应一个 Hermes profile，不实现另一套 agent 或打断状态机。

## 开发与构建

从仓库根目录运行。要求 Flutter 3.47 / Dart 3.13、Rust 1.90 和平台官方构建工具。
默认使用仓库私有运行目录内的 SDK，也可通过 `FLUTTER_ROOT`、`PUB_CACHE` 指定现有安装。

```sh
node scripts/flutter.mjs flutter pub get --enforce-lockfile
node scripts/flutter.mjs flutter analyze
node scripts/flutter.mjs flutter test
node scripts/build-native.mjs windows
node scripts/build-native.mjs android --firebase <private-google-services.json> --signing <private-signing.json>
```

Android applicationId 为 `app.nekodot.client`，最低 Android 10，版本 `0.2.0+3`。
默认构建 arm64；模拟器使用 `--target-platform android-x64 --debug`。
正式包沿用原有私有签名；Firebase、签名及真实测试 defines 不得提交或随测试包分发。
Windows 要求 VS 2022 Desktop C++ 工具链及 Windows SDK。编译通过不代替安装与通知验收。
服务地址只在构建时使用 `--relay <https-url>` 设置，不提供明文公网模式。

桥接 API 变化后通过 `node scripts/flutter.mjs bridge generate` 重新生成代码。

## 真实旅程

在专用设备运行 `integration_test/live_journey_test.dart`。私有 defines 包含
`RELAY_URL`、`QA_EMAIL`、`QA_PASSWORD`、`QA_NODE`、`QA_CONVERSATION`。
`QA_SCREEN=true` 验证原生屏幕，`QA_INSPECT=true` 暂停以便人工观察。
测试必须沿用设备已有包的签名及 `--keep-app-running`，不卸载替换用户客户端。

`integration_test/ui_tour_test.dart` 走查主要页面并输出截图（`QA_TOKEN`、`QA_NODE`、`QA_DM`、`QA_GROUP`、`TOUR_OUT`），用于设计复核。

旅程核对新消息 ID、实际 streaming 与最终回复，再验证画面、接管/交还和 Android 返回导航。
原生输入、后台/锁屏通知、Android 真机、双端完整页面及开发中的服务端接口分别验收，
不以模拟器或 widget 测试替代。最新结果与限制见仓库 `docs/side-phase-3-progress.md`。
