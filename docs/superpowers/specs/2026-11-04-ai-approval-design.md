# AI approval 全局统一

以用户提供的 AIApproval 组件作为视觉与交互要求。覆盖 Web（含共用 React 的 Tauri）以及 Flutter 的私聊、群聊审批消息；不把普通表单、模型提问或权限设置改成审批。

卡片采用现有主题的表面色、细边框、12px 圆角和纵向全宽选项。操作提示、命令、审批范围始终可读；允许一次、会话允许、始终允许和拒绝均直接呈现。选项支持说明、危险色、键盘焦点、窄屏换行与减少动态效果。

审批请求进行中锁定全部选项并显示忙碌状态。只有 RPC 成功或服务端消息确认后，卡片才收起选项并显示一条结果；失败保留选项并显示错误，允许重试。历史结果、其他客户端作出的决定以及取消/失败状态直接由消息驱动，不能因本地初始 state 过期而重新开放审批。

React 组件放在 apps/web/src/components/ui/ai-approval.tsx，沿用已安装的 motion/react、lucide-react 和 cn；Flutter 对应组件放在 apps/native/lib/ui/ai_approval.dart。二者只呈现决策与提交状态，仍通过原有 approvals.respond 调用 Hermes。

验收包括异步成功/失败、重复点击、外部状态更新、历史重放、移动端长文本、深浅主题及减少动画。浏览器与原生测试属于辅助检查；真实 Node/Relay、官方 Hermes 与模型的审批旅程单独记录，无法验证的设备明确标注。
