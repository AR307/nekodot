# 文件预览

Windows 聊天附件点击后在右侧打开，聊天保留；窗口不足 1000px 时使用整页预览。右侧预览与 Bot 详情互斥。文件库也复用同一入口。

- SVG：预览/源码切换、25%–400% 缩放及适合窗口；保留渐变、滤镜、图案填充。
- 普通图片：现有图片解码与手势缩放；PDF 继续使用 pdfrx；文本可选择复制。
- 保存保留原始字节；打开菜单提供系统默认应用、Windows「打开方式」、文件夹定位和原有分享。
- 外部应用使用独立临时副本，文件名在边界处理，不使用 shell 命令拼接；不修改原文件或默认关联。
- 下载与文件元数据绑定选择时的 Node；切换节点不复用另一节点的文件请求。
- 已交付附件的消息隐藏独立 `MEDIA:` 技术行，保留代码块与原始聊天数据。

SVG 通过 `flutter_inappwebview` 的系统浏览器内核在后台渲染，再以最高 3 倍、最长边 4096px 的有界位图交给 Flutter 显示和缩放；原始 SVG 的保存、源码与外部打开不变。这样解决当前 Windows Flutter 对原生浏览器画面合成为空白的问题。附件只作为 base64 SVG 图片加载到独立文档，禁用附件脚本、导航、权限与文件访问；CSP 禁止网络资源。Windows 需要 Microsoft Edge WebView2 Runtime。构建需在 PATH 提供官方 NuGet CLI，供插件下载 WebView2 SDK、WIL 和 JSON 依赖；不应修改插件的 SDK 版本约束或关闭校验。

实现：`features/file_preview.dart` 管理界面与交付，`file_transfer.dart` 管理下载和展示转换，`svg_file_preview.dart` 管理隔离渲染，`platform/file_actions.dart` 对接 Windows runner 的 Shell API。

辅助回归：`flutter test test/file_preview_test.dart`。真实验收：`integration_test/file_preview_journey_test.dart`，通过 dart-define 提供本地 Relay、账号文件、Node/会话/附件 ID 与私有证据目录。可选的窗口截图和打开方式观察器脚本由调用方提供；截图仅捕获候选应用或其系统文件对话框。测试同时检查浏览器图片解码与 Flutter 预览区域的实际非空像素，防止仅有 DOM 成功而界面空白。

本次设备验收与安装结果在 Summary.md、docs/progress.md 记录。Web 预览布局未在本模块中改动。
