# 2026-11-05 原生客户端 UI 改进验收

本轮只处理已确认的 10 项 UI 改进。未处理 Windows 本机安装的长路径报错，未发布安装包、更新正式服务或 push。

## 改动

| 需求         | 实现                                                                                                                  |
| ------------ | --------------------------------------------------------------------------------------------------------------------- |
| Bot 列表悬停 | 移除灰色退场渐变，保留选中态；最窄 240px 时名称正确省略，不再出现 RenderFlex overflow                                 |
| 输入框       | 文件加号固定在右侧，移除输入框模型控件                                                                                |
| 模型选择     | 创建/编辑 Bot、Bot 详情和 `/model` 共用来源＋可搜索的真实模型目录，不手填模型代号；辅助、委派及定时模型使用相同选择器 |
| 模型与压缩   | 支持修改最大上下文，空值使用原生自动值；详情只保留容量、压缩状态与次数，底层设置默认折叠                              |
| 命令通知     | `/new`、`/resume` 显示“已创建新会话”“已切换会话”；有信息输出的其他命令可以点开原生结果，保留文件交付                  |
| 例行任务     | 创建、修改、启停、运行和执行结果使用同一居中灰字通知；单次任务原生完成不冒充用户停止                                  |
| 旧客户端     | 按授权回收 Web/Tauri 和专用入口，保留官网、Relay、Node、Flutter、历史和用户数据                                       |
| 工作状态     | 有意义的回应保留在聊天；简短“正在…”进度仅进入闪光状态行，不重复成为气泡或步骤说明                                     |
| 复制         | 鼠标悬停/键盘聚焦时显示复制图标，平时隐藏；原有文本选择不改                                                           |

没有增加新的解释性 UI 段落。既有高级设置的原生说明保留。没有可靠目录的 TTS/live-voice 模型字符串、MoA 原始预设和备用提供方数组入口已隐藏，原生配置不删除、不改写；本轮不宣称为这些服务补齐了专用模型目录。

## 真实环境

- 本次源码构建的 Windows 原生客户端和固定 Android AVD `NekodotNativePhase3`（`emulator-5554`），未新建、未清空模拟器。
- 独立 QA Relay `127.0.0.1:4459`、本次构建的本机 Node、官方 Hermes checkout `v0.22.6`。Android 通过 `adb reverse` 连接 loopback；没有放开公网明文或证书限制。
- 已有隔离测试账号、profile 和真实自定义 API；主模型 `gpt-6-sol`，辅助压缩模型 `gpt-6.1-sol`。未触碰正式账号和服务。

## 实际操作与结果

1. 双端真实登录，打开原有 Bot 私聊；Windows 侧栏缩至 240px，未出现布局异常。空输入框和展开输入框的加号均在右侧，没有模型按钮。
2. 从 Bot 详情进入模型页，目录实际返回多个 `gpt-6` 型号；选择 `gpt-6-sol`，设置最大上下文 128000，保存后 `models.info` 从 Hermes 读回相同值。不是把单个当前模型当成完整目录。
3. 打开默认关闭的高级设置，搜索上下文压缩模型，从真实来源目录选择 `gpt-6.1-sol` 并保存；原生配置读回一致。定时模型配置也通过真实 RPC 保存为该来源的 `gpt-6.1-sol`，但本轮没有独立验收定时模型弹窗和委派执行。
4. 双端执行真实 `/new` 和 `/resume`，聊天显示短通知；随后发出真实任务，让模型调用 `terminal` 执行 `python -c "print(17*19)"`，实际得到 323。
5. 普通回应（例如“好的，我现在执行你指定的命令。”）保留；“正在运行 Python 计算”仅在工作状态行出现。模型把回应和进度放在同一条 commentary 时，仍保留回应，去掉其中的进度行。
6. Windows 模型真实创建三分钟后的单次 cron，原生实际执行并返回“UI例行任务执行完成”。新增通知为创建、执行，没有错误的“已停止”。此前失败验收产生的历史消息原样保留；截图上方若有旧停止通知，不属于新执行。
7. Windows 复制按钮普通状态透明不可点击，鼠标移入后可见；Android 聊天实拍没有常驻复制图标。
8. 旧网页移除后，真实 HTTP 验证官网 `/`、`/main.js`、`/health` 返回 200，未定义的客户端和 API 路径返回 404，不再返回旧 SPA。

## 截图与证据

- [结构化记录](evidence/ui-refinements-20261105.json)
- [Windows 窄侧栏](evidence/ui-refinement-windows-narrow-sidebar.png)
- [Windows 模型目录](evidence/ui-refinement-windows-model-catalog.png)
- [Windows 工作状态](evidence/ui-refinement-windows-working.png)
- [Windows 例行任务执行](evidence/ui-refinement-windows-routine-executed.png)
- [Android 模型与上下文](evidence/ui-refinement-android-model-details.png)
- [Android 辅助模型选择](evidence/ui-refinement-android-auxiliary-model.png)
- [Android 真实聊天](evidence/ui-refinement-android-chat-result.png)

## 工程结果

- frozen install、TypeScript typecheck、ESLint、服务端 build 通过。
- 服务端 38 文件 / 75 项测试通过；Flutter analyze 无问题，Flutter 33 项测试通过。自动化仅辅助上述真实旅程。
- Windows Release EXE 安装器、Android arm64 签名 Release APK 构建成功，仍为本地候选；Windows 安装器未做 Authenticode 签名。
- 全量 `pnpm lint` 的 ESLint 阶段通过，但 Prettier 被以下 5 个既有文件阻挡，未为凑通过混入无关格式化：`docs/evidence/product-updates-acceptance.json`、`docs/evidence/side-phase5-commands-android.json`、`docs/evidence/side-phase5-commands-windows.json`、`docs/local-desktop-plan.md`、`docs/side-phase5-command-adapters.md`。本轮提交文件单独格式检查通过。
- Android 扩展旅程初次未找到屏幕外的模型行；测试改为使用实际搜索框过滤后选择，重跑通过，没有增加产品 fallback。

## 未覆盖边界

Android 真机、macOS/Linux、第二家来源切换、委派模型实际调用、TTS/MoA 专用模型目录、此次变更后的完整公网 webhook 启停与执行、暗色/英文/reduced-motion 全旅程、手机长按复制未在本轮逐项重验。原有旅程不当作本轮通过；没有重放已完成的工具，也没有重写历史。
