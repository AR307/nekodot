# 全功能人体工学验收与动效/排版系统 实施计划

设计：`docs/superpowers/specs/2026-11-05-ui-ergonomics-motion-design.md`。用户已授权自动执行全部步骤，无需逐步确认。

## W0 基线

1. 运行 `pnpm typecheck`、`pnpm lint`、`pnpm test`、`pnpm --filter @nekodot/web build`，结果写入 `docs/ui-ergonomics/baseline.md`。
2. 后台运行 `pnpm test:e2e`（需先构建 Web），既有失败逐条列出，标注“既有”。
3. 新增 `@axe-core/playwright`（devDependency），编写 `tests/support/ergonomics.ts` 探针与 `tests/browser/ergonomics.spec.ts`，在录制环境逐面初跑。
4. 候选 Web 独立端口连接真实 Relay `4319`，以本地账号走查全部功能面，结合探针报告写 `docs/ui-ergonomics/findings.md`。

## W1 基础

1. `styles/tokens.css` 增加动效、间距、字号、目标尺寸 token；新增 `src/motion.ts`，`ui.tsx` 的 `ease` 改从 `motion.ts` 引用（不保留旧导出）。
2. 新增 Vitest 守卫 `apps/web/src/design-system.test.ts`：token 一致、CSS 无字面时长/曲线、TSX 动效参数来源、断点白名单。先让守卫失败，再逐文件迁移到 token 直至通过。
3. 新增 `components/ui/dialog.tsx`（焦点约束/归还、inert、Esc、滚动锁定、token 动效），`Sheet` 基于它重写；`components/ui/state-view.tsx`。
4. 全局减少动效规则统一为 `--dur-instant`、无循环、无位移。
5. 门禁 + 提交。

## W2–W7 每波固定步骤

1. 从 `findings.md` 取该波发现，先在 `ergonomics.spec.ts` 中写出失败检查（尺寸、焦点、溢出、动效）。
2. 修改对应 feature 与样式：迁移到 Dialog/StateView、token 动效、设计板动效、排版刻度、44px 目标、拇指区布局。
3. 跑探针与相关既有 E2E，补真实环境走查截图。
4. 更新 `findings.md` 状态、`docs/ui-ergonomics/wN-*.md`、`Summary.md`、`docs/progress.md`；单独本地提交。

各波文件：

- W2：`features/auth.tsx`、`components/ui/auth-page.tsx`、`styles/auth.css`、`team-app.tsx`（启动页）、`features/pairing.tsx`。
- W3：`features/sidebar.tsx`、`features/team.tsx`、`features/node-picker.tsx`、`features/command-palette.tsx`、`features/notifications.tsx`、`styles/shell.css`、`ui.tsx`。
- W4：`features/chat.tsx`、`components/ui/ai-chat-input.tsx`、`components/ui/ai-approval.tsx`、`features/markdown.tsx`、`features/files.tsx`、`features/pdf-preview.tsx`、`features/voice-input.tsx`、`styles/chat.css`、`styles/ai-approval.css`。
- W5：`features/groups.tsx`、`features/group-chat.tsx` 及 `chat.css` 群聊部分。
- W6：`features/bots.tsx`、`features/bot-details.tsx`、`features/model-info.tsx`、`features/models.tsx`、`features/extensions.tsx`、`features/user-memory.tsx`、`styles/capabilities.css`、`styles/pages.css`、`styles/sheet.css`。
- W7：`features/settings.tsx`、`features/providers.tsx`、`features/operations.tsx`、`features/screen.tsx`、`styles/screen.css`。

## 收尾

1. 全量 lint/typecheck/test/build/E2E 与探针；`ergonomics-live.spec.ts` 在真实环境全旅程（含真实模型，若用户已配置）。
2. Tauri Windows 打包并在 WebView2 冒烟（工具链可用时）。
3. `docs/ui-ergonomics/acceptance.md` 总报告：通过项、未验项（真机、Android、macOS/Linux 等）与证据位置。
