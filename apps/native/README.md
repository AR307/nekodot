# nekodot native

Windows / Android 的 Flutter 客户端。界面由 Flutter 绘制，屏幕通过
`vnc-rs → flutter_rust_bridge → ui.Image` 解码与显示。
Space HTML 使用系统 WebView2 / Android WebView；其他页面仍为 Flutter 原生。
Hermes 和 Node 在用户本机或 VPS 运行，客户端不增加 Agent 执行循环。

## 结构

- `lib/data/client.dart`：HTTPS、业务 WSS、RPC、snapshot/since/seq/offset、草稿及安全登录存储。
- `lib/features/`：账号、节点、Bot、聊天、记忆、文件、扩展与设置。
- `lib/data/spaces.dart`：按账号、Node、空间隔离的记录与离线修改队列。
- `lib/features/spaces.dart`、`space_webview.dart`：空间入口、缓存资源拦截及受限记录桥。
- `lib/screen/`、`rust/`：认证 WSS、RFB 解码、原生控制权与输入。
- `lib/platform/`：Windows 托盘/窗口、Android FCM 和系统通知。
- `lib/ui/design.dart`：黑白 tokens（Windows 实色、Android 毛玻璃）、圆形猫头像与页面转场；`lib/ui/parts.dart`：共用组件。
- `integration_test/`：显式启用的真实远程旅程；日常测试不调用模型。

本端保存登录态、偏好、草稿、已缓存聊天与空间；空间内容和使用记录的服务端副本仅在所属 Node。
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
Windows 要求 VS 2022 Desktop C++ 工具链、Windows SDK 和 NuGet CLI。
NuGet 用于 WebView 插件的构建依赖，可放在 PATH 或仓库 `.runtime/tools/nuget.exe`，不随客户端分发。
运行 Space 需要系统 WebView2 Runtime。编译通过不代替安装与通知验收。
`android/space_webview/build.gradle` 仅替换固定 WebView 插件的旧 Gradle 配置以使用本项目 AGP 9；不修改共享 Pub 缓存、Java 实现或依赖版本。
Windows 0.6.0 插件的 environment 工厂使用了错误的 MethodChannel ID；Space 适配层将它绑定回实际实例 ID，正常释放 WebView2，不吞掉销毁异常。
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
不以模拟器或 widget 测试替代。
