# 0.3.2 发布记录

2026-11-06。用户授权正式发布 Windows、Android、配套 Relay/Node，并同步 GitHub 源码、标签与正式 Release；简短发布说明已获批准。

## 版本与范围

- 产品最终构建 0.3.2+9；Windows x64 安装器未做 Authenticode 发布者签名，最终包大小见结构化证据。
- Android arm64 APK；实际 applicationId 为 `app.nekodot.client`，versionName 0.3.2，versionCode **2009**。APK 签名验证通过，证书与 0.3.1 相同。
- Relay `nekodot-relay:product-0.3.2-b9`，health build 9；Node 发布号 `20261106120623`。
- Hermes 后端运行包 `v0.22.6-r1`：Windows x64 770,308,773 字节，Linux x64 642,321,596 字节。配套描述文件与可续传下载一同部署。
- 初始 App/服务端从已提交源码 `a4c871ea7f1462bc1feab0018ba3adbf058960f2` 独立归档构建；最终 build 9 基于 `9ef626b813`，只追加公网下载修复和构建号。用户随后追加授权上线 Claude 最新官网，采用 `abef886066` 的文案、导航、滚动开场和截图，加上本轮版本化下载链接；官网发布快照为 `938fae11ab`。此新授权替代此前冻结旧官网的决定。

## 正式切换

- 先只读核对正式路由、容器、端口、磁盘和 Node 空闲状态。保留数据库在线备份、原安装包、官网、启动配置、Node 身份及 Hermes profiles 副本；旧源码和运行目录保留。
- 独立候选 Relay 使用生产数据库副本和 loopback 4379；真实 SMTP TLS/认证、账号及统计 schema、匿名访问拒绝、版本和运行包 Range 下载通过。没有对候选发送真实通知。
- 正式 Node 原 Hermes 源码不含本轮 Cron 审批扩展。先并排准备已验收的 v0.22.6-r1，官方 PM 同步现有账号插件，再将下次启动入口切到此包；不搬动 profiles，不修改原源码。Node 经现有 idle updater 完成切换并恢复 online，pending 标记正常消费，无 rejected 标记。
- Relay 切到 0.3.2 后先做真实公网检查，再切换安装包别名及 `latest.json`。版本化文件先就位，`latest.json` 最后发布。候选容器停止但保留。
- 其他四个受保护服务的容器 ID、启动时间、重启次数前后相同；Caddy、其他产品和整机没有重启。

### 公网续传修复

- build 8 首次公网检查发现：大于 CDN 缓存上限的 Hermes 归档，在源站/直连 Caddy 为 206，经过 CDN 则收到 200 整包，断点续传不可用。原生包和普通聊天检查不受影响。
- 运行包下载响应增加 `Cache-Control: no-store`，避免 CDN 填充缓存时丢弃 Range；不改客户端协议，不添加 fallback。用原入口实际首段和续段请求复测，结果在 downloads 证据记录。
- 构建号升为 9，重新构建双端及 Relay；build 8 的版本化产物保留，GitHub build 8 仅保留为未发布 draft，不替换旧文件。最终安装包、manifest 和正式 Release 使用 build 9。
- 另外实测固定安装包别名仍被 CDN 命中旧 build 8。官网和 README 已改用 `releases/0.3.2-9/`，与 App 更新相同，直接取得最终包。旧无版本别名保留，部分 CDN 缓存过期前可能仍返回 build 8；不把带随机查询串的正确响应当成固定别名已刷新，也不宣称已执行 CDN 全网清除。
- 12:45 UTC 最终复测：两种正式版本化下载和无查询串的固定别名均与最终本地包逐字节一致；记录到的 Windows 别名为 EXPIRED，Android 为 MISS。官网 HTML、JS、CSS 与已授权最新快照一致。

## 本轮真实公网验收

通过正式 HTTPS/WSS、正式 Node、新 Hermes 运行包与 **gpt-6.1-sol**：

- 读取原生会话、156 条命令目录、授权目录及屏幕状态；不把读取屏幕状态称为实际屏幕操作。
- 真实调用 1 次工具计算 `17 × 19 = 323`，模型流式返回；同一 clientMsgId 重复提交只生成一条用户输入。
- Flow 保留 5 个真实步骤，含完成的工具节点，最终状态 done。
- 本次私聊用量从 0 增至 **25,668 Token**，真实采集并同步到账号统计。
- 公网 Webhook 错误密钥返回 401，正常请求返回 202；Hermes 真实执行并回投结果。相同 delivery ID 返回 duplicate，仅 1 条执行记录；后台执行没有替换私聊 Flow。测试任务验后暂停。
- 使用已有专用 QA 账号的短期内部会话，验后已撤销。不代表邮箱注册/密码登录本轮重新验收。
- 第一次探针在 Node 首次启动完成前触发，得到未就绪，未发送模型请求；Node 约 52 秒恢复 online 后重新验收通过。早期探针保留在本地发布目录，没有重放已完成的工具。

## 工程辅助检查

- 独立归档源码：pnpm frozen install、全量 ESLint、typecheck、41 文件 / 84 项测试、服务端正式 build 通过。
- Flutter 锁定依赖、analyze、40 项测试、Windows Release/安装器、原签名 Android arm64 Release 通过；build 9 仅改变原生版本号，双端重新构建。Relay 下载修复另跑相关 ESLint、typecheck 和真实 HTTP 续传辅助测试。
- 本轮改动文件 Prettier 检查通过；此前无关文件的全量格式问题没有混改，不宣称全仓格式全绿。
- GitHub 源码/main、v0.3.2 标签及 Release 安装包按本次授权发布。最终远端状态与公网文件结果见下列证据。

## 未验范围

- 用户此前停止窗口操作，本轮没有恢复许可，因此没有操作原生窗口，也没有用其他自动化绕过。Ferris 新交互真实窗口、当前最终包覆盖安装和 Android 真机未复测。
- 统计、Flow、运行包各模块之前的真实 Windows/固定 Android/模型验收仍按原报告记录；本轮工程检查不替代其真实验收。
- 非零缓存写入、MoA、完整组合触发矩阵、低内存 Linux 屏幕、完整公网冷安装、macOS 实机等原先待验项不因此转为通过。不提供 macOS/Linux 桌面包。
- 不在此次发布中删除旧客户端回收物、用户数据、profiles、未提交设计、截图或并行编辑的官网文件。

## 证据

- `evidence/release-0.3.2-packages.json`：版本、包大小、Android 签名连续性。
- `evidence/release-0.3.2-builds.json`：独立构建与辅助检查。
- `evidence/release-0.3.2-candidate.json`：候选 SMTP、schema、权限与下载。
- `evidence/release-0.3.2-live-model.json`：真实模型、工具、Flow、统计和 Webhook。
- `evidence/release-0.3.2-production.json`：数据、身份与其他服务保留。
- `evidence/release-0.3.2-downloads.json`：公网版本、正式版本化下载字节一致、旧别名实际缓存状态及最新官网。

原始日志、私有备份和回滚产物保留在忽略的本地发布目录与正式服版本目录，不提交凭据。
