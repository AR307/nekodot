# ShiningText 加载状态

## 接入

Web 已有 React、TypeScript、Tailwind v4 和 `motion`，无需重新初始化或安装第二套动画库。
可复用组件放在 `apps/web/src/components/ui/`，样式在 `apps/web/src/styles/`。
`apps/web/components.json` 和 Vite/TypeScript 的 `@/` 别名供 shadcn 组件使用；公共 UI 单独放置，避免业务页面之间互相导入。

```tsx
import { ShiningText } from '@/components/ui/shining-text';

<ShiningText text="nekoDOT is thinking…" />;
```

`text` 必填，也支持普通 span 属性与 `className`。组件使用行内语义，适合按钮、状态行和页面加载位置。示例在同目录 `shining-text-demo.tsx`。
组件不需要额外 provider、图片、图标或状态库。业务状态由调用方维护。

统一加载入口为 `ui.tsx` 的 `LoadingText`：可传实际状态文字，或使用中英文 `loading/saving/creating/installing/submitting/connecting`。
Motion `useAnimate` 控制两秒、110°、200% 渐变背景循环；卸载清理动画。系统减少动画变化会停止循环，强制颜色模式显示普通文本。
深浅主题及反色按钮分别设置文字基色。

原生 Flutter 对应组件为 `apps/native/lib/ui/shining_text.dart`，通过 ShaderMask 和两秒控制器实现相同扫光；`LoadingTextScope` 提供当前语言的默认加载文案。
应用启动、异步页面、保存、命令列表、文件、记忆、扩展等入口已接入。真实安装与下载百分比仍保留进度条。

## 验证 / 2026-11-04

- Web 类型检查、构建和相关 ESLint/Prettier 检查通过；项目原有大块资源提示保留。
- 候选 Web 使用本机真实 Relay `4319`；浏览器实际添加电脑等待状态显示扫光文字。
- 浏览器连续读取 350ms：背景位置从 `-87.4% 0%` 到 `-157.4% 0%`，确认动画正在运行。
- 减少动画设置后显示普通文字，390px 视口无横向溢出。
- Flutter analyze 无问题，现有 Windows 登录窗口/退出测试 3 项通过。Windows Release 的整合构建由聊天模块协调任务执行；本模块未独立宣称原生真实模型验收。
- 本次未配置模型密钥，未验实际 AI 回复或转写。
