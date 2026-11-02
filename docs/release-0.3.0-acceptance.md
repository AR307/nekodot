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

- 正式 Relay 已切换 `nekodot-relay:product-0.3.0`，Node 已切换盖章版本 `20261102164326`，systemd active、NRestarts 0。
- 正式 Hermes 仍基于 v0.22.5，仅应用已授权最小 listener 修复，独立提交 `92c63e4012`；没有升级或替换 Agent 引擎。
- 切换时账号 3、节点 4、Bot 2、消息 53 全部保留，Node 凭据逐字节未变；后续验收仅在专用 QA 账号增加记录。备份包含数据库、原源码、Node state/bin/service、官网与下载。
- 对照发布前后，QA Relay、Caddy、getplus 和其他受保护容器的 ID、启动时间与重启计数未变；不重启其他产品或整机。Caddy 既有整站反向代理已覆盖新路由，无须修改。
- 公网 HTTPS/WSS 的真实 `gpt-6.1-sol` 流式聊天完成，重复发送同一 clientMsgId 仅产生一条用户消息；原生 Session 可读、152 条命令目录可读。见 [正式服真实模型记录](evidence/release-0.3.0-live-model.json)。
- 正式公网 Webhook 错误密钥返回 401，正确事件返回 202；真实原生模型执行完成并回投私聊；重复 delivery 返回 duplicate，执行只有一次。验收任务已暂停，临时 QA 会话已退出失效。
- 官网与 Windows / Android 安装包公网 HTTP 200、版本和文件类型正确；Node 安装脚本生成产品 HTTPS 地址。见 [下载记录](evidence/release-0.3.0-downloads.json)。正式官网 12 组 Edge 检查通过，见 [线上官网记录](evidence/release-0.3.0-live-site.json)。
- 用户随后要求不再追加检查、立即上传。停止追加验收，不等待额外 Windows Session GUI 重跑；不将尚未完成的本轮结果记为通过。既有 Side Phase 5 / Session 真实验收保持原记录，Android 按用户本轮确认记载。

GitHub 按用户追加授权同步源码、标签及正式非 prerelease 安装包，MIT 许可证不变。
