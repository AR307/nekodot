# Flowchart 文案审核稿

状态：用户已修改并确认采用。标题为 Flow；不新增解释段落。Bot 名称、原生计划标题和工具名属于实际数据。

| 占位词            | 中文候选   | English candidate |
| ----------------- | ---------- | ----------------- |
| FLOW_TITLE        | Flow       | Flow              |
| FLOW_CLOSE        | 关闭       | Close             |
| FLOW_FOLLOW       | 当前步骤   | Current step      |
| FLOW_RETRY        | 重试       | Retry             |
| FLOW_DISCONNECTED | 连接中断   | Disconnected      |
| FLOW_THINKING     | 思考中     | Thinking          |
| FLOW_REPLY        | 回复       | Reply             |
| FLOW_BROWSER      | 浏览器     | Browser           |
| FLOW_SEARCH       | 搜索       | Search            |
| FLOW_READ         | 读文件     | Read file         |
| FLOW_WRITE        | 写文件     | Write file        |
| FLOW_CODE         | 执行代码   | Run code          |
| FLOW_TERMINAL     | 终端       | Terminal          |
| FLOW_APPROVAL     | 等待授权   | Approval          |
| FLOW_QUESTION     | 等待回答   | Question          |
| FLOW_RUNNING      | 执行中     | Running           |
| FLOW_WAITING      | 等待中     | Waiting           |
| FLOW_QUEUED       | 排队中     | Queued            |
| FLOW_DONE         | 已完成     | Done              |
| FLOW_FAILED       | 失败       | Failed            |
| FLOW_CANCELLED    | 已停止     | Stopped           |
| FLOW_PAUSED       | 已暂停     | Paused            |
| FLOW_UNKNOWN      | 状态待确认 | Status unknown    |

节点旁只显示动作名称；状态用于图标提示与无障碍读屏，不另加状态说明段落。未知工具直接显示原生名称。

已确认视觉补充：完成绿色、运行/等待蓝色、失败红色、未执行灰色；节点框 32px、行高 56px、触控区域 44px。原生 Plan 标题为父层，完成后自动收起，可手动展开。仅保留最新聊天图，不包含定时和 webhook。
