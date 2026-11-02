# 0.3.0 正式发布记录

## 发布授权与基线

- 2026-11-03：用户明确要求直接发布正式环境，并确认 Android 验收已完成。
- 发布前产品源码基线 `1067f8a2b0`；本次版本 `0.3.0+6`，Android arm64 versionCode 2006。
- 正式环境原 Relay 为 0.2.0，Hermes 为官方 v0.22.5（`bf0203a794a0`）；部署前 3 个私聊运行记录均 idle、没有活跃群聊接力。
- 原账号、节点、Bot、历史、profiles、浏览器资料及无关服务保留。不以测试环境或 Android 模拟器替代用户确认的真机验收。

## 本轮结果

### 独立构建与候选

- 独立检出 `51cab6b97b` 完成 frozen install、lint、typecheck、35 文件 / 59 项服务端测试及 build；Flutter frozen pub、analyze 和 18 项测试通过。
- Windows release 安装器构建成功，实际运行 release 客户端并观察到原生页面正常绘制；未做 Authenticode 发布者签名。
- Android 首次构建遇到已知 Kotlin 增量缓存关闭异常。保留失败现场，仅在本次构建设置 `-Dorg.gradle.project.kotlin.incremental=false` 后重试成功；未清理缓存、重建虚拟机或修改全局 shell。
- Android arm64 APK 为 `0.3.0` / versionCode 2006 / minSdk 29，使用官方 apksigner 验证签名，与上一正式版本同一签名证书。安装包数据见 [产物记录](evidence/release-0.3.0-packages.json)。
- Relay 镜像在本机 WSL 构建后上传，不在正式 VPS 源码构建。现有 Docker Desktop 因本机 socket 错误不可用，使用独立目录的官方 Docker 本地构建进程完成；未 reset、清除或改动既有 Docker 数据。
- 隔离候选 Relay 使用复制数据库验证健康、SMTP TLS/认证、账号与例行任务 schema、匿名拒绝及已盖章 Node 分发；正式数据库未用于候选写入。
- Edge 完成官网 390 / 768 / 1440px、中英、浅深色共 12 组检查，含 reduced-motion、图片、主题/语言/场景/头像交互和 Android 下载优先级。结果见 [候选官网记录](evidence/release-0.3.0-candidate-site.json)。

### 正式部署

进行中；线上真实模型、服务状态与公开版本回查完成后追加，不以候选检查冒充正式上线完成。
