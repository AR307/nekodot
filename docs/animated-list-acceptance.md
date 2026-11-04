# Animated List 验收 / 2026-11-04

共享 React 界面的业务列表已接入指定的 [ReactBits Animated List](https://reactbits.dev/components/animated-list)，来源与 MIT + Commons Clause 原许可见 `apps/web/src/components/ui/animated-list.LICENSE.md`。无新增依赖。

## 范围

- Bot/群会话、电脑菜单/设置/配对页、命令搜索结果、手机新建菜单。
- Skills/插件目录、扩展文件、Bot 安装状态与安装成员、群成员、@ 候选。
- 消息附件、资料库、问答和审批选项、计划任务/执行历史、记忆审阅/冲突/历史、批量操作结果。
- 保留原有行元素、按钮/复选框语义、业务选中、滚动容器、字体与明暗主题。消息正文、Markdown、表单原生 select 和已有 Gooey Nav 导航不强制转成业务选择列表。
- Flutter 原生客户端未修改或重打包。Web 与 Tauri 共用源码，Tauri 宿主设备未做本次验收。

## 真实环境

本次源码 Vite 候选运行于 `127.0.0.1:4499`，连接现有本地 Relay/Node `127.0.0.1:4319` 与官方 Hermes；默认 4318 端口属于另一个工作树，未将其当成本次候选。实际浏览器通过原本地账号密码登录、Node 在线同步、授权服务目录、电脑菜单、命令面板方向键/Enter 跳转、真实 Skills 目录筛选与详情。

真实目录共 149 行，在 320/390/768/1440px 的明暗两套主题检查无横向溢出，滚动到最后的 `yuanbao` 行后显示正常。完整私有结果与截图在忽略的 `.runtime/animated-list-real-qa.json` 和 `.runtime/animated-list-skills-*.png`，不提交认证资料和原始 RPC 响应。本地账号仍无模型来源和 Bot，本轮未调用真实模型，不宣称模型回复或设备端验收通过。

## 浏览器和工程检查

- `tests/browser/animated-list.spec.ts` 五项通过：内部滚动/动态增删保留控件状态、实时减少动效、外部滚动/键盘聚焦、全屏预览不受动画裁切、悬停描边在桌面切手机后不造成横向溢出。
- `tests/browser/ai-approval.spec.ts` 四项通过：等待提交/重复点击、失败重试、独立决策、外部结算与窄屏减少动效。
- 现有 `capabilities.spec.ts`、`user-memory.spec.ts` 两个完整旅程通过，覆盖 Bot 详情、资料库预览/下载、扩展与切换、记忆审阅和多节点冲突。这些使用录制 Hermes，属于辅助证据。
- 现有群聊、提供方旅程的列表部分另在忽略目录生成聚焦副本：群成员创建/编辑、@ 选择、三尺寸布局、授权状态、多来源选择通过。账号提交按钮名称按当前界面匹配，原测试未修改。
- 完整群聊回放在运行数量断言处收到 2（期望 4），完整提供方回放在欢迎介绍收到 Hermes HTTP 400。本次未修改 Node/Hermes 或放宽原断言，不宣称这两个全旅程通过。
- TypeScript、全仓 `pnpm lint`（ESLint/Prettier）和 Web production build 通过。构建仍报告既有大 chunk 提示。导入 Relay 源码的 Playwright 旅程通过 `NODE_OPTIONS=--import tsx` 执行，处理当前 JSON 模块导入测试环境限制。

## 修复与交付边界

资料库预览最初被列表遮罩/动画纳入，现已排除弹层并仅对自身可滚动列表启用渐隐；新增失败再通过的回归检查。悬停描边在缩窗时出现滚动溢出，现由列表边界约束并保留 3px 焦点余量。禁用行继续保持禁用外观，减少动效时不移动/缩放。

更新 Summary.md 与 docs/progress.md 后单独本地提交；不发布、不 push、不替换已安装客户端。
