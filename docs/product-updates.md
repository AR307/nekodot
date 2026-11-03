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

实现中；真实客户端和隔离服务结果将在完成后补充。静态检查不等于真实覆盖安装通过。
