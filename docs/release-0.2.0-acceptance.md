# 0.2.0 发布验收

版本为 **0.2.0 开发者预览版**，Flutter `0.2.0+5`，Android arm64 versionCode `2005`。原生界面、官网和 README 采用本轮重新设计的黑白视觉。保留旧包、参考资料、profiles、历史和其他人的未提交截图。

## 构建与独立候选

- Windows x64 release 与 NSIS 安装器构建通过，安装器未做 Authenticode 签名。
- Android arm64 release 构建通过，应用标识不变，APK 签名验证通过，与已发布包使用同一签名证书；最低 Android 10。
- Node 使用发布者提供的生产 Ed25519 密钥盖章，版本 `20261031080359`；私钥留在仓库外，没有上传服务器。普通 build 之后不再覆盖盖章产物。
- Relay 镜像在本地 Docker Desktop 构建，脱离源码实际启动，并检查发布清单和 argon2 可用。补齐 `.dockerignore` 的发布清单条目。
- 工作区 frozen install、lint、typecheck、23 文件 / 36 项测试、build 通过；Flutter analyze 无问题，11 项测试通过。
- 服务器独立候选使用生产 Relay 数据库的副本，原有账号与密码保持；既有账号进入邮箱补验，缺验证码注册被拒绝。候选账号的密码登录、业务 WS、退出关闭 WS、撤销凭证失效通过。
- 候选服务的 SMTP TLS 和认证通过。本次未将其写成新的外部收码验收；先前真实收码结果见 Side Phase 3 账号报告。
- Edge 覆盖 390 / 768 / 1440px、中英文、浅深色和 reduced-motion，共 12 组；所有图片加载，语言、主题、头像选择、演示切换和 Android 下载优先级通过。官网截图为演示数据。

机器记录：`evidence/release-0.2.0-packages.json`、`evidence/release-0.2.0-candidate-accounts.json`、`evidence/release-0.2.0-candidate-site.json`。

## 部署与发布

准备阶段已保存账号数据库副本和服务基线；线上服务切换、实际公网旅程与 GitHub 发布结果在完成后追加。原有服务仍保持可用，未把候选测试写成线上通过。

## 保留的验收边界

此前真实 Hermes、自定义 API、Codex 原生授权、共享记忆、原生屏幕及 Windows / Android 模拟器旅程沿用模块报告，不重复冒称本次全部重跑。Android 真机、后台 / 锁屏通知、干净 Windows 用户安装、完整系统选择器和全原生视觉矩阵仍未完成。Phase 3 的长期通路与手机真机恢复项目继续保留。
