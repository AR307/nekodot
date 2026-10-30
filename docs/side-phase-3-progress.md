# Side Phase 3 实施与验收

## 范围

本阶段目标为 Flutter Windows / Android 原生客户端与账号、提供方、交互、记忆、扩展、通知更新。旧客户端与线上服务在新客户端实际验收前保持可用；此文档不表示 0.2.0 已完成或发布。

## 3.4 原生提问与输出恢复

- `clarify` 与执行审批分开建模，问题的普通选项不再进入审批枚举。使用原生 `requestId`、`execution_generation` 和当前 `runId` 提交 `/clarify`，不转换成聊天或 steer。
- Hermes 等待提问时 run 仍为 `running`，Node 根据 `pending_controls.kind=clarify` 恢复问题。新建与已存在 profile 的 API toolset 显式包含 Hermes 原生 `clarify`。
- SSE 断流保留文本并显示重新连接；续接同一 run，不重新执行任务。协议解析错误、运行失败、输出终止均显示原因并结束遗留的运行中卡片。
- 真实模型验证：隔离 WSL / Hermes home 中，提问 Amber / Teal，回答 Amber 后相同 run 完成，实际输出 `NEKODOT_CLARIFY_OK Amber`。命令入口为 `scripts/spike-clarify.ts`；脱敏事件与状态在 `docs/fixtures/runs-clarify.*`。
- 自动化：Node 覆盖等待问题时禁止普通发送、回答、重复回答拒绝；Edge 完整私聊旅程覆盖提问中刷新、Node 重建、草稿保留、回答及同 run 完成。截图 `docs/evidence/side-phase3-clarify-answered.png` 是浏览器回放证据，不冒充真实模型截图。
- 本轮复测：TypeScript 检查通过，15 文件 / 27 项测试通过。完整 Edge 4 项通过，真实 Linux 屏幕项因缺少本轮私有现场跳过。Flutter analyze 通过；Flutter 实际原生旅程另行记录。

## 3.1 Flutter 基础闭环（不是完整迁移验收）

- 新增 Windows / Android Flutter 工程、共用 HTTPS/WSS 同步层、原生导航及系统安全存储。产品界面不使用 WebView；Rust RFB 解码通过 Flutter 绘制。
- 独立 Android 模拟器真实账号登录、新流式模型回复、完整 Linux 屏幕、只读/接管/交还、原生键盘输入和返回聊天/列表均通过。远端文件确实保存 `NEKODOT_NATIVE_INPUT_OK`，不是仅检查控件。
- 修复 TLS 根证书与 Rust provider 配置、native assets 对 Cargo feature 变更的缓存，以及 RFB 有界通道积压导致的部分白屏。
- Flutter analyze、1 项账号 widget 场景及 Windows x64 / Android arm64 signed release 构建通过；构建包未发布。详细结果与模拟器截图见 `side-phase-3-native.md`。
- 完整页面、尚未实现的服务端接口、Windows 安装及 Android 真机仍待验收；旧产品不切换。

## 3.2 邮箱与会话基础（外部收码注册已验证）

- 已实现 SMTP 验证码、已有账号补验、重置/修改密码、可撤销会话与服务端退出，Web 保持可回归。
- 本地真实 SMTP、HTTP、业务 WS 与屏幕转发验证通过；退出关闭通道，撤销凭证不能重用。具体检查和未覆盖范围见 `side-phase-3-accounts.md`。
- 外部 SMTP 已由用户提供并完成真实收码注册、密码登录、验证码重放拒绝和退出失效；详见账号报告及 `evidence/side-phase3-smtp.json`。密码重置/旧账号补验的外部收码与生产代理检查仍待做，线上账号版本未切换。

## 剩余交付

## 3.3 Hermes 多授权、自定义来源与模型信息

- 设置拆为原生授权和自定义 API；多个来源共存，自定义设置只填名称、URL 与 Key，Bot 表单再选择来源和模型。移除旧的全节点单提供方写入路径及 OpenRouter 专用入口。
- 一个 Bot 仍对应原生 profile；OAuth grant 留在项目 root，由 Hermes 继承及刷新，不复制 grant 或重建运行中的 agent。模型容量与压缩直接读取原生接口及日志；无法识别显示未知，当前版本不支持的最大输出覆盖不伪造实现。
- 持久隔离 WSL 中，两自定义来源完成真实回复；用户完成 OpenAI Codex 设备授权后，其 profile 真实回复，自定义来源仍可用。Node/Hermes 重启后来源及授权保留，欢迎消息不重复。真实 `/compress` 的输入与原生 telemetry 分别留证，详见 `side-phase-3-providers.md`。
- Edge 的来源设置、授权状态、Bot 表单、欢迎、刷新与模型信息通过，390 / 768 / 1440px 留图。Android 专用模拟器通过原生来源表单、建 Bot、欢迎及重连，不再把 RPC 创建等同于表单验收；但设备码状态使用真实录制回放，与 WSL 真实授权分开记录。
- 收尾 Node 24 lint/typecheck、18 文件 / 30 项测试、build 通过；完整 Edge 5 通过 / 1 真实 Linux 屏幕跳过；Flutter analyze、2 项测试及 Windows x64 / Android arm64 signed release 构建通过。
- 本轮未做全新检出、Windows 干净安装或 Android 真机旅程，不切换线上服务、不分发候选包、不 push。既有共享记忆、通知及安全实测待验收项继续保留。

## 3.7 通知预览与设备归属

- Node 通知携带 Bot/群组名和最终纯文本预览，区分提问、审批及失败；Relay 只持久保存投递标识，FCM 根据实际 UTF-8 载荷预算截断预览。
- 双账号 HTTP 实测复现设备注册可覆盖另一账号绑定的问题，修复为 409；跨账号注销不生效，正常绑定/注销、通知去重和 WS 归属测试通过（2 文件 / 2 项）。TypeScript 检查通过。
- Flutter 已接原生权限、显示、点击与当前会话抑制；真实 FCM/Windows toast 未完整验收。当前模拟器 Google Play 服务不足，Android 真机仍待提供。报告见 `side-phase-3-notifications.md`；不部署或发布。

## 待完成项

### 3.6 本轮扩展与交互进展

- 已完成说明文件 / 列表、来源链接、图标及独立完整页；真实 Hermes 管理读取、Edge 响应式与 Android 模拟器 RPC 阅读 / 返回通过，报告见 `side-phase-3-extensions.md`。
- 修复原生刷新和连接释放的实际错误。系统导入选择器、原生全部视觉及真机仍待验收。

- 外部邮件重置/旧账号补验、账号级 USER 记忆、扩展安装原生旅程与原生通知仍需逐项验收；真实 OpenAI Codex 授权与自定义 API 共存已在 3.3 验证。
- Flutter 的基础构建与最小真实闭环已通过，全部页面和新后端接口尚未完成，不能切换产品或发布安装包。
- Windows 完整安装、Android 真机、跨设备共享记忆及后台通知不得以构建、模拟器或浏览器手机尺寸替代。

## 3.4 Bot 原生欢迎回合

- 创建 Bot 后由对应 Hermes profile 在原私聊 session 生成介绍与任务询问，不伪造用户消息。沿用原生 run、SSE、停止、steer 和恢复，失败保留错误并提供手动重试。
- 隔离 WSL 中真实模型通过：只有一次 createRun，无用户气泡，Node 重建及 snapshot/since 后不重复。录制与脱敏证据已保留，详见 `side-phase-3-welcome.md`。
- Node 24 下 17 文件 / 29 项场景、lint/typecheck/build 通过，Edge 完整回归 4 通过 / 1 跳过（本轮真实 Linux 屏幕现场未提供）。Flutter analyze 和 2 项 widget 场景通过。Android 专用模拟器另外通过真实 RPC 的介绍显示、重连保持消息 ID、失败与手动重试，截图已核对。
- 本项当时仅验 RPC 创建；后续 3.3 已补齐 Android 多来源创建表单旅程。Windows / Android 真机及本项后台通知仍待验收。未切换产品、未发布、未 push。
