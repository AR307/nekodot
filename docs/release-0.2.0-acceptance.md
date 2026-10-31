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

- 独立源码导出执行 frozen install、lint、typecheck、test、build 全部通过；Edge E2E 为 7 通过 / 1 真实 Linux 屏幕专项跳过。未共享工作区依赖，回归截图写在独立目录。
- 生产 Relay、项目 Node、官网及双端下载已切换至本次版本。切换前保存数据库、程序及站点备份，账号、节点、Bot 与消息数量没有减少；既有 profiles、浏览器资料保留。共享服务器的其他三个容器身份、启动时间和重启次数保持不变。
- Node 安装首次被之前验收留下的 PM 输入目录属主阻断；先保留该目录，再仅修正项目输入子树的属主。重跑官方安装流程后服务上线、Relay 握手通过，未绕过 Hermes 检查或修改全局环境。
- 公网 HTTPS/WSS 经升级后的 Relay 与 Node，调用原 Hermes profile 获得真实流式回复 `NEKODOT_020_RELEASE_OK`；同一 clientMsgId 重复提交返回同一消息，只新增一次用户输入。该检查使用原有 QA 账号的 15 分钟内部验收会话，完成后已撤销，不作为新的邮箱登录验收。
- Windows / Android 官网包实际完整下载通过，分别为 15,684,634 / 34,054,104 字节；Node 发布号为 `20261031080359`。本轮没有重跑所有原生安装、系统通知或屏幕输入旅程。
- 为 www 入口补充规范域名重定向并 reload Caddy，四种 HTTP/HTTPS 与裸域名/www 入口最终均到 HTTPS 官网；没有重启其他产品。
- GitHub 交付入口为 [v0.2.0](https://github.com/AR307/nekodot/releases/tag/v0.2.0)，按开发者预览版发布，保留 v0.1.0。两个资产已上传，名称和大小与官网下载包一致；源码使用正常 fast-forward 推送，不强制覆盖已有分支。
- 发布后以未登录请求完整下载 GitHub 两个资产，均为 HTTP 200，文件大小及 EXE / APK 类型正确。[标签 CI](https://github.com/AR307/nekodot/actions/runs/41186188808) 全部通过。另一轮同提交的群聊测试在配对页显示“准备命令”时提前提取验证码，造成空匹配；后续 main 仅将该断言改为等待真实配对码，再跑隔离 Edge 完整群聊旅程通过。已发布标签及安装包保留不变。

## 官网缓存修复

用户已打开的 Edge 标签实际复现：新 HTML 加载旧 `styles.css`、`main.js` 和截图，表现为米色背景、缺少八个头像及旧 React 界面。干净浏览器检查未覆盖这条路径，不能证明现有用户已经更新。

样式、脚本、图标和截图地址统一增加 `?v=0.2.0`，主题切换产生的截图地址也保留版本参数。只上传站点文件，原文件另存保留，没有重建 Node、客户端包或重启服务。用户原 Edge 标签正常刷新后，背景为白色、8 个头像已渲染，新 Flutter 主图加载成功；无需用户清缓存。

修复后公网 Edge 再次完成 390 / 768 / 1440px、中英文、浅深色与 reduced-motion 的 12 组检查：所有截图加载、无横向溢出，语言、主题、头像与演示切换及 Android 下载优先级通过。记录为 `evidence/release-0.2.0-cache-fixed-site.json`。

机器与视觉证据：`evidence/release-0.2.0-live-model.json`、`evidence/release-0.2.0-downloads.json`、`evidence/release-0.2.0-edge-cache-fixed.json`、`evidence/release-0.2.0-edge-cache-fixed.png`。

## 保留的验收边界

此前真实 Hermes、自定义 API、Codex 原生授权、共享记忆、原生屏幕及 Windows / Android 模拟器旅程沿用模块报告，不重复冒称本次全部重跑。Android 真机、后台 / 锁屏通知、干净 Windows 用户安装、完整系统选择器和全原生视觉矩阵仍未完成。Phase 3 的长期通路与手机真机恢复项目继续保留。
