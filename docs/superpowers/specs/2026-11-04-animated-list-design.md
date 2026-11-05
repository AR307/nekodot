# ReactBits Animated List

用户指定 https://reactbits.dev/components/animated-list 作为全局列表交互。范围为共用 React 的 Web / Tauri 界面；Flutter 不能直接使用 React 组件，暂不改动。

使用 ReactBits Animated List 的 pop 入场、错位延迟、滚动显隐、随指针移动的弹性描边和上下渐隐，适配现有暖色明暗主题。统一容器直接渲染原有行，不把包含按钮、复选框、文件链接的内容变成单一 option。列表保留原有布局、滚动归属、业务选择状态和键盘事件。减少动效时立即展示全部行。

覆盖会话、电脑菜单/设置/已配对电脑、命令结果、Skills/插件目录和文件/安装状态/安装成员、群成员与 @ 候选、资料库与消息附件、问答/审批选项、新建菜单、计划任务/历史、记忆审阅/历史与操作结果。消息正文流和 Markdown 列表、横向头像/颜色/接力、原生 select 的 option、步骤说明和普通表单字段遵守原有语义，不作为业务列表替换。已有 Gooey Nav 导航继续由对应组件管理。

验收：组件浏览器测试覆盖内部/外部滚动、动态更新与减少动效；现有业务浏览器旅程检查操作和语义；TypeScript、相关 lint/format、Web 构建。连接现有真实 Node/Relay/Hermes 时另记真实模型结果，回放仅作辅助。保留所有既有未提交改动，文档与本模块单独本地提交。
