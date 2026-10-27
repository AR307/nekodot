# Phase 0 进度

| 模块                  | 状态                         | 证据                                                       |
| --------------------- | ---------------------------- | ---------------------------------------------------------- |
| 0.0 参考归档          | 已完成；原 HTML 视觉核对受限 | 两份原件、参考索引；私有 GitHub AR307/nekodot-app 初始归档 |
| 0.1 工程骨架          | 已完成                       | Node 24 workspace；基础页桌面/手机实际浏览器截图           |
| 0.2 协议              | 已完成；按实测定稿           | Zod、导出类型、业务输入样例；裁切依据见 hermes-notes       |
| 0.3 真实 Hermes spike | 已完成                       | 五项真实场景通过；持久现场确认；七项调查与 CDP 连接证据    |
| 0.4 测试回放服务      | 已完成                       | 六类真实 HTTP 接口、13 项场景检查与真实 fixture            |
| 0.5 整体验收          | 进行中                       | 待全新检出验收、最终浏览器复验与本地提交                   |

## 真实结果

- 自定义 API 精确回复 NEKODOT_PHASE0_OK。
- terminal printf 返回 NEKODOT_TOOL_OK，工具 start/completed 带相同 tool_call_id。
- once 后真实 AGENTS.md 增加标记；deny 后保持原内容，没有重试或换路径写入。
- sleep 工具执行中停止，最终 run 为 cancelled；真实 stop 响应为 stopping。
- gateway 启动后新增 profile 无重启可访问。
- 自有 Chromium CDP 实际 Browser.getVersion、Target.getTargets 成功。
- 0.3 最终持久现场在 WSL 重新进入后确认存在，两份文件内容与报告相符。

## 原参考的视觉核对

HTML 九块已静态解析，完整原件保留。查看通道拒绝原稿执行后，未改用别的通道执行该文件。
原稿视觉核对仍待获准查看方式；独立基础页已用实际 Edge 浏览器验证桌面、语言和手机尺寸并留图。
完整参考界面还原属于 Phase 1，不把基础页截图当成原参考视觉核对。
