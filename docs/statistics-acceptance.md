# 统计：实现与验收

日期：2026-11-06。仅本地候选，不发布、不 push，不改正式服务。

## 架构

- `packages/protocol/src/usage.ts`：四项 Token、原生调用身份、统计对象和汇总类型。
- `apps/node/src/hermes/usage-plugin.ts`：profile 级原生观察插件，SQLite 保存数字记录；通过官方管理 command.dispatch 增量读取。新 profile 在首回合前使用原生 reload-plugins。
- `apps/node/src/usage.ts`：admission/会话归属、Cron/Webhook 分区、增量同步；ACK 后推进游标。相同 Cron 添加 Webhook 后保持 jobId 身份。
- `apps/relay/src/usage.ts`：账号隔离持久汇总；POST `/api/usage/query` 与 `/api/usage/refresh`；IANA 时区分日。
- `apps/native/lib/data/usage.dart` 与 `features/statistics.dart`：原生页面、日历、两张占比卡、系统 CSV 保存。仅大卡片有边框；内部行/头像/数值无边框。

从插件启用起采集，不扫描旧累计、不保存请求正文。总量为未缓存输入＋输出＋缓存命中＋缓存写入；不额外累加推理。缺少原生 usage 保持不可得。MoA 主汇总与成功 aggregator 辅助记录去重，不用估算补数。

## 真实环境

| 项目    | 本次范围                                                               |
| ------- | ---------------------------------------------------------------------- |
| Windows | 本机原生 Flutter 候选，真实 UI 登录、聊天、设置入口、统计与导出        |
| Android | 固定 NekodotNativePhase3 / emulator-5554，未新建或清空 AVD             |
| Node    | 本机两个隔离 Node，各自 profiles 和 Hermes 进程                        |
| Relay   | `http://127.0.0.1:4467` + WS；不是公网 HTTPS/WSS                       |
| Hermes  | v0.22.6，官方后端运行包 r1，`f0d94882e89ab8d4098b5bb2f166adfb9ee0a0ab` |
| 模型    | 项目既有自定义来源的真实 `gpt-6.1-sol`，凭据未提交                     |

## 已实测

- 私聊真实 terminal 计算、两个 Dot 群聊各自执行 terminal；群聊归入独立统计项，不再额外计入成员 Dot。
- Webhook 经本地 HTTP 入口接收，真实回复 `WEBHOOK_USAGE_OK`；原生单次 Cron 真实回复 `CRON_USAGE_OK`。两者进入后台任务卡。
- 原生 delegate_task 建立子会话，真实调用已保存父 admission 关联；`/compress` 产生原生压缩摘要和辅助调用记录。
- 对单次真实调用前后读原生 SessionDB，新增插件数字逐项相等：输入 285、输出 8、缓存命中 12544、缓存写入 0。见 `evidence/statistics/native-comparison.json`。
- Node B 新建 profile 的真实欢迎回合立即记入 16788 Token，无需重启。
- 两个真实账号隔离：另一账号总量为 0，指定他人节点查询/刷新均为 404；同账号两节点之和等于账号汇总。
- 节点 B 断开时已有汇总保持 744728；刷新报告该节点未同步而不清空数据。两个 Node、Relay、Hermes 重启后汇总不变；重复刷新不翻倍。
- Node B 断开 Relay 时原生模型产生 30632 Token；重连后从 744728 补传到 775360。将已采集的真实身份重发一次，总量不变，没有重新调用模型。见 offline-collection.json。该 QA 驱动最初误读 active-run API，修正后仅恢复原已接收任务，没有再发送提示。
- Windows/Android 真实候选核对时间筛选、单节点/全部节点、日历精确数字、Dot/群聊/任务头像、两卡滚动、浅深色和中英文。Windows 悬停、Android 点击可查看精确消耗；Windows 窄窗无溢出。
- Windows 系统 Save File 导出由用户完成。保存文件 6 行，UTF-8 BOM，输入 212105、输出 1782、缓存命中 530841、缓存写入 0，总计 744728，与当时页面一致。见 `windows-system-export.json`。用户按 Esc 停止 Computer Use 后未继续鼠标/窗口操作。

## 验收中发现与处理

1. 主请求失败重试复用 requestId 与 started_at，错误记录占用了成功记录身份，导致成功 Token 被去重。错误按 ended_at 单独记录，成功数字不再丢失。
2. canonical in-process 回合没有 worker ledger，改为读取原生 admission ContextVar；worker identity 归一到同一个 admission。子 Agent 通过原生 child/session 关系归属，不按名称猜测。
3. 新 profile 的插件文件写入后未必立刻进入共享 gateway，接入原生 reload-plugins 后新欢迎回合真实验证成功。
4. 最初深色截图抓在 Theme 动画中途，文字尚未完成颜色过渡；等待实际动画完成后复核可读，没有添加页面特例颜色。
5. Windows 扩展旅程滚动后列表顶部被卸载，测试定位失败；测试改为滚回顶部。扩展断言运行至系统保存入口，保存单独由用户完成，不把被手动中断的整条自动化说成全绿。
6. 第一条 Cron 验收配置使用 CLI pin 后丢失 named provider 凭据，原生失败且未产生模型用量；另建跟随 profile 的任务完成。未改核心或绕过该失败。

## 未完成或不能外推

- 非零缓存写入：本次服务没有返回非零 cacheWrite，不能由测试构造值宣称真实通过。
- MoA、多来源缓存字段、组合任务两种触发合并尚未逐项真实复跑。
- 手动 `/compress` 的官方辅助 hook 在没有 turn 时不提供 sessionId/admission；本次记录按真实 profile 归到所属 Dot。自动压缩有 turn 身份；手动压缩的更细粒度会话归属仍待上游原生身份支持，未伪造匹配。
- Android 真机、系统 CSV 保存/分享、横屏；本轮在用户停止电脑操作后没有继续操作模拟器补验。
- 真正等待跨日/DST、长期运行、会话切换/重命名/归档的完整消费矩阵、主动停止时已消耗用量仍需补验。时区和幂等辅助测试不替代这些真实旅程。
- QA 开发早期存在未采集调用；不以整个旧 SessionDB 累计对比当前总量。本次精确性证据是修复后的单次差值和新记录，不回填历史。

## 工程

- Node 24：typecheck、全量 ESLint、41 文件/84 项辅助测试、Node/Relay bundle 通过；最后 jobId 修复的两个用量测试重新通过。
- Flutter：analyze、36 项辅助测试通过；Windows 原生基础旅程和 Android 扩展真实旅程通过，截图在 `evidence/statistics/`。
- Windows Release 构建与未签名安装器生成；Android arm64 原签名 Release 构建通过（33.6 MB）。保持 0.3.1+7，仅本地候选，不发布。
- 全仓 Prettier 受 6 份原有文件格式问题影响，未混改；本轮文件单独格式化检查。
- 正式包命令复核：Node CJS、Relay/协议 ESM bundle 通过。本次 QA 的 4467、19242–19244、19252–19254 监听已退出，保留所有验收目录；未操作其他服务。
