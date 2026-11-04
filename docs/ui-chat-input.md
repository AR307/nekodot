# 聊天输入框 / 2026-11-04

以本次 `66bf8c6e` 附件的 `ai-chat-input.tsx` 为视觉参考，替代之前的输入框模板。网页与仓库已有 Flutter 客户端同步实现，不另建桌面宿主。

- 空闲时为 320px 胶囊；聚焦、有草稿、附件或任务运行时展开至最多 480px。窄屏受可用宽度约束，文本自动增高，尊重减少动画设置。
- 底部显示当前 Bot 的真实模型目录、模型设置、文件入口及录音/发送/停止状态。模型更改写入 `bots.update`，成功后返回输入焦点。群聊网页入口打开群组配置；原生入口明确操作对应 Bot。
- 网页附件通过既有 `imports.create`、分块 PUT 和 `files.receive` 上传，草稿按电脑与会话保存；支持文件移除、图片缩略图和预览。发送重试保留消息 ID，仅在确认后清除此条文本与附件；正在写的下一条草稿保留。原生继续使用已有上传、附件、命令与群聊 @ 流程。
- 网页麦克风真实录音后转单声道 16kHz WAV，调用 Hermes `voice.transcribe` 并轮询操作结果，结果写回草稿。离开页面或进入后台释放录音资源；失败显示错误。原生使用既有 VoicePage，新增可选回调把识别结果交给当前会话草稿，发送前可编辑。
- 没有照搬模板的示例模型、模拟语音或假成功状态。当前协议未暴露附件中的 effort 档位，因此未显示无效的切换项。

## 验证

- `pnpm typecheck`、Web release build、定向 ESLint/Prettier 通过。
- WAV 头、16kHz 单声道和 PCM16 截断范围测试：1 项通过。
- `flutter analyze --no-pub` 无问题；PromptCard 输入、焦点展开和 390px 适配测试：1 项通过。
- Windows release 构建通过，候选路径为 `apps/native/build/windows/x64/runner/Release/nekoDOT.exe`，本地 Relay 为 `http://127.0.0.1:4319`。
- 专项 Edge 浏览器测试通过：实际 React 页面、独立 Relay/Node、测试用 Hermes 回放服务；覆盖胶囊展开、两次模型写入、真实分块文件上传与移除、390px 无溢出、深浅主题。已查看截图。此项属于辅助验收，不是官方 Hermes 与真实模型链路验收。
- 真实本地账号登录候选网页通过，预览服务为 `http://127.0.0.1:4338`。登录注册页的真实收件、重置密码验证记录见 [ui-auth-refresh.md](ui-auth-refresh.md)。

专项浏览器复验（PowerShell）：

```powershell
$env:NEKODOT_BROWSER_RELAY_PORT='4349'
$env:NEKODOT_RELAY_URL='http://127.0.0.1:4349'
$env:PLAYWRIGHT_WEB_PORT='4348'
$env:NODE_OPTIONS='--import=tsx'
pnpm exec playwright test tests/browser/private-chat.spec.ts -g 'composer expands' --workers=1
```

`tsx` 用于现有 JSON 导入的 Node 24 测试装载。测试使用独立端口，不停止现有本地服务。原完整聊天回放在欢迎介绍的 Hermes HTTP 400 / `inspectRuns()` 数量断言失败，已保留原断言；本次专项测试独立于该已知失败。

## 验收边界

用户选择自行填写 API Key，本地目前没有模型来源；尚未验证真实模型回复、真实语音识别、执行中停止与补充指令的端到端结果。Windows 原生 GUI、实体设备、Android、macOS 与 Linux 未做完整人工交互验收。没有将回放结果作为上述链路通过的证据。
