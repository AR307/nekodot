# W1 动效与排版基础

范围：共用 React 的 Web / Tauri（`apps/web`）。设计依据 `design/08-motion.png`、`design/09-tokens.png`。

## 单一来源

- `styles/tokens.css` 新增动效（8 档时长 + 4 档循环、`--ease`/`--ease-pop`/`--ease-exit`、4/8/12px 位移、30ms 错开）、间距（4px 栅格）、字号（28/20/16/14/12）、`--target: 44px` 与阅读宽度。
- `src/motion.ts` 镜像同一组数值，供 `motion/react` 使用；`tween()`、`springy()`、`useMotion()` 已内置减少动态效果：所有档位收拢为 80ms 淡入淡出，弹簧改为同一淡入淡出。
- 设计板数值与档位的对应：消息出现 220ms；Bot 接力标签 200→220ms、头像上跳 300→280ms 并延迟 160ms；工具卡 spring 400/32；状态图标切换 150→160ms；配对成功 600ms 回弹 + 8 点散开；耳朵 600ms、眼睛 1.6s、在线点 1.4s、接管呼吸 1.2s、流式光标 1s steps。工作中头像花瓣 9.6s 写作 `calc(var(--dur-sway) * 16)`，与耳朵同相。
- 原有 7 组弹簧统一为 `spring`（400/32）与 `springPop`（420/18）；`ui.tsx` 不再导出 `ease`，不保留兼容导出。

## 静态守卫（`apps/web/src/design-system.test.ts`）

1. CSS token 与 `motion.ts` 数值一致；
2. 除 `tokens.css` 外 CSS 的 transition/animation 不含字面时长或 `cubic-bezier`；
3. 组件中的 `duration`/`delay`/`stiffness`/`damping`/曲线只能来自 `motion.ts`；
4. `@media` 宽度只允许 767/768/1023/1024/1279/1280。组件按自身宽度换行的三处改为容器查询（审批卡、扩展页头、设置卡片/电脑列表），不再用视口近似。

改造前 127 处违规；迁移后 4 项全部通过。

## 交互基础组件

- `components/ui/dialog.tsx`：独立图层渲染；应用根节点与下层弹层 `inert`；初始焦点取 `[data-autofocus]` 或首个字段；Tab/Shift+Tab 循环；Esc 只关闭最上层；关闭后焦点回到原处；锁定页面滚动；`center`/`sheet`/`top`/`side`/`full` 五种位置的 token 动效，手机底部弹层可下拉关闭；`dismissible={false}` 时提交中不可关闭。
- 迁移：`Sheet` 及全部表单弹层、命令面板、Bot 详情（桌面右侧滑入 / 手机自下）、扩展详情、扩展全文（叠在详情之上，Esc 先回到详情）、扩展导入（安装中不可关闭）、文件预览。删除各自的 CSS 进场关键帧与窗口级 Esc 监听。
- `components/ui/state-view.tsx`：加载 / 空 / 错误（assertive，附重试）/ 离线四态统一排版与入场，供各波替换零散写法。

## 全局人体工学修正

- 对比度：`--ink-3` 浅色 #9a9186→#736b61、深色 #7a7268→#9c9489；深色 `--danger` #c8432f→#ec7a63；导航轨道底色改为 `--hover`，未选项保持 ≥ 4.5:1；导航选中项的深色文字只在橙色胶囊绘出后启用；扩展仓库链接改用 `--accent-text`（设计板：accent 只做图形）。
- 字号：20 处 10–11px 声明与浏览器默认的 `small` 统一为 12px（`--text-meta`）。
- 点击目标：`.tiny-icon`、`.text-button` 及 17 处局部覆盖提升到 44px；附件移除按钮用负边距保持原有胶囊尺寸。
- 名称一致：电脑选择与模型选择改为可见文字 + 视觉隐藏前缀，不再用 `aria-label` 覆盖可见名称；Markdown 代码块与文件预览文本可键盘聚焦滚动。
- 侧栏分隔条保留 8px 宽度，作为可键盘调节的等效例外记录（F07）。

## 验证

- 工程门禁：`pnpm lint`、`pnpm typecheck`、`pnpm test`（40 文件 / 75 项，含 4 项新守卫）、Web 构建通过。
- 录制探针（桌面/手机 × 明/暗）：P1 由基线 45 项降至 2–3 项（剩余为 W6/W7 的设置链接与电脑菜单展开时的目标重叠）；E4 弹层焦点、E3 字号、E7 减少动态效果均为 0；非 token 时长仅剩 Gooey 粒子抖动（接受）。深色下导航选中项被 axe 误判（看不到滤镜后的胶囊），探针改为直接测量文字与胶囊颜色（6.2:1）。
- E2E 回归：19 通过。`groups` 与 `private-chat` 两项原先停在过期选择器或端口冲突处，现可走完全程：同步了节点直接转发 Hermes 网关错误信息的现行行为、验证码邮件改为等待送达、模型/电脑选择改用组件定位（W1 去掉了覆盖可见名称的 `aria-label`）。私聊旅程需独立 Web 开发服务器代理到测试 Relay：`NEKODOT_BROWSER_RELAY_PORT=4359 NEKODOT_RELAY_URL=http://127.0.0.1:4359 PLAYWRIGHT_WEB_PORT=4421`。
- 既有未解决：`node-update` 在 W0 代码上同样失败——`/me` 加载时计算更新命令，测试节点在其后才连上时提示不出现。属节点更新流程的时序问题，不在本次人体工学范围，单独记录。
- 期间曾误让私聊旅程经候选 Web 代理到本机真实 Relay，向本地 Mailpit 发出数封 `browser-…@example.test` 验证码邮件；未完成注册，未产生账号。
