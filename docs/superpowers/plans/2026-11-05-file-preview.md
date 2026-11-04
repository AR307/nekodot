# 文件附件右侧预览 Implementation Plan

> 执行方式：在当前任务逐步实现与验证，不创建并行代理。

**Goal:** 修复 Windows SVG 显示，并让聊天附件在右侧预览，支持源码、缩放、保存及系统打开方式。

**Architecture:** 文件选择绑定原始 Node；聊天通过预览作用域将选择交给 Home 右侧面板，窄屏打开独立页面。SVG 使用隔离的 WebView2 文档中的 data 图片渲染，不执行附件脚本或访问网络。操作系统文件操作通过专用 Windows MethodChannel，不拼接 shell 命令。

**Tech Stack:** Flutter、flutter_inappwebview（Windows WebView2）、现有 FilePicker/pdfrx、Windows Shell API。

## Constraints

- 保留原始附件与聊天数据，UI 隐藏已交付附件的 MEDIA 技术行。
- 保留现有 PDF、文本、保存与分享能力；预览与 Bot 详情面板互斥。
- 宽窗口保持聊天可用，窄窗口整页预览，标题避让窗口控制按钮。
- 不删除文件、不提交运行目录/凭证、不 push；安装前备份原程序。

## Tasks

- [x] 回归测试：Node 绑定、SVG 文档隔离、MEDIA 文本处理、右侧/窄屏布局。
- [x] 实现文件预览模块与 Windows 默认打开、打开方式、文件夹定位；安全保留临时副本。
- [x] 接入聊天附件和 Home，修复 SVG 渲染与源码/缩放工具栏。
- [x] Flutter analyze、37 项辅助测试；真实本地 Node/Hermes 已交付 SVG 的 Windows 集成验收。
- [x] 构建 Release、备份与安装、40 个文件一致、5 个启动入口恢复；更新 Summary/progress。

## 验收实现调整

真实窗口发现当前 Flutter 无法合成插件的原生 WebView 画面，DOM 解码成功仍然空白。因此 SVG 由隔离浏览器内核先渲染为高分辨率有界位图，再由 Flutter 显示；原始 SVG 仍用于源码、保存及外部打开。集成测试增加预览区域的实际非空像素断言，已用原始 900×1100 小丑 SVG 通过；右侧与窄窗口截图均人工检查。

默认应用打开调用成功；Windows 打开方式进程/对话框已观察并取消，未改变关联；没有替用户选择其他应用。文件夹定位、系统保存/分享对话框和其他设备未真实交互验收。

## Acceptance

- 本次 clown-portrait.svg 完整显示渐变/模糊，不经过 Image.memory。
- 点击附件右侧打开，关闭后聊天保留，切文件/切 Node 不串内容。
- 源码与原文件一致；缩放/适合窗口；菜单可保存、系统默认打开及 Windows 打开方式。
- 小窗口无溢出，明确未验平台与外部程序交互范围。
