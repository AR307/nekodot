# Windows / Android / Relay 版本与更新

## 产品入口

- 登录页“检查更新”和设置页“版本与更新”均可进入，不依赖 Node 在线。
- 读取系统安装包版本，不再使用设置页硬编码版本。显示当前客户端、最新发布、说明及连接的 Relay 版本。
- 下载流式写入 App 缓存，显示进度与错误；失败后手动重试，不启动不完整文件。
- Windows 点击“退出并安装”后启动现有 NSIS 安装器并退出客户端，不停止服务器任务。
- Android 打开系统安装器确认覆盖安装，未允许安装时显示设置入口，不自动授权。沿用原签名和 applicationId；清单使用 APK 实际 versionCode，包括 ABI 编号。
- Relay 更新限服务器运维 CLI，不向普通账号提供服务器执行权限或 Docker socket。
- 不自动推送或发布；检查更新不会自动下载、安装或重启。

## 发布流程

1. 同步根 package.json 与 pubspec 产品版本，每次发布递增 build number。
2. 按既有流程构建客户端和 Relay；build-distribution 将实际 build number 编入 Relay。
3. 用既有 Dockerfile 构建镜像，执行 `docker save -o /private/nekodot-relay.tar nekodot-relay:<tag>`。
4. 在项目根运行：

```powershell
node scripts/release-product.mjs --relay /private/nekodot-relay.tar --image nekodot-relay:<tag> --aapt /path/to/android-sdk/build-tools/37.0.0/aapt.exe --notes /path/to/release-notes.md
```

可传入 `--windows`、`--android`、`--output`。读取 APK 的实际包标识、versionName 和 versionCode；缺产物或版本目录已存在时拒绝发布。先准备完整 releases/<version>-<build>/，最后写 latest.json。上传同样先放完整产物，最后替换清单；官网固定下载名仍按原发布流程更新。Node 更新沿用已有签名清单。

## Relay 运维

将 update-relay.py 和支持 NEKODOT_RELAY_IMAGE 的 compose.yml 放入独立产品部署目录，不覆盖私有 .env。首次启用需按原部署流程更新一次 Relay，之后运行：

```sh
python3 update-relay.py --check
python3 update-relay.py --apply
```

默认源 https://nekodot.com，健康地址 http://127.0.0.1:4349/health；可设置 --source、--health、--directory。运维账号须已有 Docker 权限。

下载时旧服务继续运行；完成后 docker load，仅 compose up --no-deps relay。实际健康及版本确认后记录镜像到 .env。失败恢复旧镜像并明确报错。数据库、Node、profiles、站点、旧镜像和私有配置不删除。旧 .env 私有备份在 updates/，权限 0600，不得提交 Git。切换会短暂断线，依现有同步恢复，不重放任务。

## 验收

2026-11-03，已实现，未正式发布：

- Windows 原生 debug 候选读取实际 0.3.0 build 5，通过真实隔离 Relay 发现 build 6 并下载完整 NSIS 安装包。用户授权后在客户端点击“退出并安装”，实际退出候选并打开 NSIS 安装窗口。完整覆盖安装与重新启动仍待用户完成，不记为通过。
- 固定 NekodotNativePhase3 / emulator-5554 读取真实 build 6，下载 build 7 的实际同签名 x64 APK；显示未授权安装提示，打开系统权限页并交由用户确认。用户实际授权并完成覆盖安装，系统显示 App installed，dumpsys 确认为 build 7，随后启动登录页；用户明确回复“安卓成功更新了”。Android 真机未验。
- Windows、Android 实际页面已视觉检查；首张 Android 截图缺少产品 Ambient 容器导致透明背景，修正验收宿主后重跑并核对，不改产品主题。
- 测试 VPS 的独立 Compose 项目完成真实 Relay build 5 → 6，健康接口返回新版本，实际 relay.db 中的验收记录保留，.env 备份权限 0600；再次检查显示无需更新。没有替换正式产品容器，正式 Relay/Caddy/其他应用启动时间不变。验收容器已停止，文件、旧镜像和数据保留。
- 本机 Docker Desktop 因旧运行 socket 无法访问启动失败，未清理其数据；Relay 验收改在已有测试服务器的独立目录完成。第一次辅助数据探针误选 .sqlite 扩展，后改为真实 relay.db 并重跑，因此最终结论只依据后一次结果。
- 服务端 TypeScript、限定 ESLint、37 文件65项辅助测试通过；Flutter analyze、原有20项辅助测试通过，另增加版本比较回归。Windows release EXE 和沿用原签名的 Android arm64 release APK 已构建，Windows 仍未做 Authenticode 签名。
- 本功能不改变 Agent 执行逻辑，此次测试没有伪造模型调用或声称跑过聊天/屏幕全量回归。

证据：docs/evidence/product-updates-acceptance.json、product-updates-windows.png、product-updates-android.png。检查/下载自动化入口：apps/native/integration_test/updates_journey_test.dart，必须连接真实候选 Relay，系统权限由用户处理。

发布前仍需：Windows 完整覆盖安装、Android 真机确认，递增产品版本/build 并生成实际全量发布清单；当前候选沿用 0.3.0 build 6，不应作为新正式版本发布。没有 push 或更新官网/正式服务。
