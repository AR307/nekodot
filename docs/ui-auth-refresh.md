# 登录注册页调整 / 2026-11-04

Web 和现有 Flutter 客户端同步采用参考组件的左右双栏：左侧 nekoDOT 品牌与流动线条，右侧窄表单；手机宽度收起左栏。
保留原有产品标题、简短欢迎语、邮箱、密码、验证码、找回密码、语言切换，去除重复功能列表和技术连接路径。
注册、验证邮箱与重置密码继续调用原 Relay 认证接口。参考中的虚构评价、无后端的第三方登录和空链接未引入。

- Web：`apps/web/src/components/ui/auth-page.tsx` 提供视觉布局，认证状态保留在 `features/auth.tsx`；样式为 `styles/pages.css`。
- Flutter：`apps/native/lib/ui/auth_frame.dart` 提供原生布局与 CustomPainter 线条；保留原窗口拖动区域、语言按钮避让、退出和更新操作。
- 表单提交和发送验证码使用公共扫光文字，线条响应减少动画设置。

验证使用本次候选 Web `http://127.0.0.1:4318`、本机真实 Relay `4319` 与 Mailpit 邮件服务：

1. 从注册页发送验证码，实际收件、填写验证码并创建专用验收账号，成功进入添加电脑页。
2. 从登录页进入找回密码，实际收取重置验证码并更新密码，再使用新密码登录成功。
3. 中英切换、登录/注册/重置模式切换正常；1440px 双栏、390px 紧凑表单，深浅主题截图已检查，390px 无横向溢出。
4. Web 类型检查、构建、相关 ESLint/Prettier、Flutter analyze 及原生现有窗口拖动/退出测试 3 项通过。

截图：`docs/evidence/ui-auth-refresh-1440.png`、`docs/evidence/ui-auth-refresh-390-dark.png`。
原生 Windows 完整 GUI 的认证链路和模型回复未在本模块验收；整合 Release 构建由聊天模块协调执行。
验收账号及验证码不提交；不影响用户原账号或模型配置。
