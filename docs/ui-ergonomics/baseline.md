# W0 基线（2026-11-05）

设计与准则：`docs/superpowers/specs/2026-11-05-ui-ergonomics-motion-design.md`。本页记录改造前的工程门禁与人体工学基线；发现逐条登记在 `findings.md`。

## 工程门禁（改造前）

| 项                                 | 结果                                            |
| ---------------------------------- | ----------------------------------------------- |
| `pnpm typecheck`                   | 通过                                            |
| `pnpm lint`（ESLint + Prettier）   | 通过                                            |
| `pnpm test`（Vitest）              | 39 文件 / 71 项通过                             |
| `pnpm --filter @nekodot/web build` | 通过；既有提示：主 chunk 723 kB > 500 kB        |
| `pnpm test:e2e`（Edge）            | 13 通过、6 失败、1 跳过（需私有文件的屏幕实测） |

E2E 的 6 项失败均为既有问题，与本次改动无关：

- `foundation`、`groups`、`node-update`、`providers` 四项等待 `继续` 按钮。2026-11-04 账号页改版后提交按钮文字改为当前模式标题（`登录` / `创建账号`），测试选择器未同步。已在本模块更新选择器；`foundation` 原先每次运行覆盖已提交的 `docs/evidence/phase1-account-*.png` 历史证据，改为写入 Playwright 测试输出目录。
- `private-chat` 两项报 `EADDRINUSE 127.0.0.1:4319`：测试自启的 Relay 与本机真实部署占用同一端口。端口已可由 `NEKODOT_BROWSER_RELAY_PORT` 指定，回归时设置为空闲端口即可，无需改代码。

## 人体工学探针

新增工具（仅测试使用，`@axe-core/playwright` 为 devDependency）：

- `tests/support/ergonomics.ts`：axe（WCAG 2.2 AA 标签集）、可点击目标尺寸、正文字号、横向溢出、动效时长是否取 token、减少动态效果、弹层焦点契约（初始焦点、Tab 不外逃、Esc 关闭、背景 inert、焦点归还）、CLS 与长动画帧。
- `tests/support/ergonomics-walk.ts`：按人的路径逐面进入（指针、键盘、触屏），录制与真实验收共用同一条路线。
- `tests/browser/ergonomics.spec.ts`：录制管理数据，桌面/手机 × 明/暗四组。
- `tests/browser/ergonomics-live.spec.ts`：仅在本地提供 `NEKODOT_LIVE_ACCEPTANCE_FILE` 时连接真实 Relay/Node/官方 Hermes 运行；会话文件位于忽略目录，不提交。

基线运行范围：

- 真实环境：候选 Web `127.0.0.1:4420` → 真实 Relay `4319`、Node「This Windows PC」、官方 Hermes；节点已授权 ChatGPT 订阅，已有 Bot `@1`（`gpt-6-sol`）及含工具调用的真实对话。中文桌面浅色 1440×900、中文手机深色 390×844 两组。
- 录制环境：桌面明/暗 1440×900、手机明/暗 390×844 四组。

结果：去重后 104 项（P1 45、P2 35、P3 24），无 P0。各组逐项报告与截图保存在忽略目录 `.runtime/ergonomics/baseline/`。

探针本身的两处修正：手机端应用会在加载时恢复上次会话（属正常产品行为），路线改为每个界面先回到团队列表再进入；各步骤设 15 秒超时，避免被遮挡控件拖住整轮检查。

## 走查观察（人工看图）

- 桌面私聊：悬浮输入框遮住最后一张附件卡；欢迎语换行留下孤字「你。」；「已停止」标签字号过小。
- 手机新建 Bot：底部主按钮固定在拇指区，分组清楚，符合设计板。
- 手机设置 → 授权登录：各提供方之间无分隔，「原生授权说明」看不出是链接，「断开授权」缩进异常，命令未按代码样式显示。
- 新建群组需要至少两个 Bot；本账号只有一个，所以两种布局下都无法进入该界面（预期内），W5 用录制数据覆盖并检查禁用原因提示。
