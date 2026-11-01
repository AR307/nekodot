# Side Phase 4 — Webhook 例行任务

状态：候选实现与隔离真实验收进行中；未部署产品、未发布、未 push。

## 原生任务与接入

- 一个 Bot 继续对应一个 Hermes profile。纯 webhook 使用共享 gateway 的动态订阅及目标 profile；组合任务关联已有原生 `cron_job`，不复制定时任务。
- Node 内置薄插件和 `nekodot-routines` skill，提供 `hermes routine create/update/list/get/send`。CLI 通过用户私有 Unix socket 联系 Node；不增加公网监听、模型工具循环或调度器。
- 共享 gateway 的 webhook 仅监听 loopback。外部经 HTTPS Relay、现有节点出站 WebSocket、Node 登记路由进入原生 webhook。调用方不能选择 profile、原生 URL 或任务提示。
- Node 使用 AES-256-GCM 保存外部凭据，主密钥在数据库外的私有目录。原生内部凭据独立保存。Relay 仅存入口摘要、节点归属和启用状态，不保存事件正文或模型结果。
- 用户确认前 webhook 禁用；给已有定时任务加 webhook 不会暂停定时部分。聊天卡仅包含任务标识及交付状态。脚本调用 `hermes routine send ID`，不嵌入或输出密钥。
- 原生接收回执与模型执行结果分开。插件通过只读命令读取该 profile 的原生 admission 和持久结果，Node 按原生 session 收录、回投私聊和通知。不再依靠 session hook 判断完成，也没有第二套执行或重试引擎；早期验收 outbox 文件保留原地。
- 下一次私聊输入提供新后台结果及原生 session 引用，不修改已缓存前缀、不重跑原任务、不 steer 当前私聊。
- Relay 的 `hello.ok.publicUrl` 是入口地址来源；Node 可以连接同机 loopback，但展示及 helper 使用公网地址。不保留旧协议双路径。

## 已复现的上游问题及授权修复

真实公网请求在共享 listener 切入目标 profile 后返回 503。durable admission 的 `route_digest()` 再次加载动态路由时，错误读取目标 profile 的订阅文件，而非 listener 所属文件，导致 `RuntimeStoreError: not_found`。

用户已明确允许最小原生修复、单独提交和隔离验收。Hermes 本地提交 `67e4f384b8929926438c9bb014f371d0238a532a`：listener 构造时固定动态订阅文件路径，后续 hot reload 仍读取同一文件。没有改变 agent、权限或任务执行逻辑。

- 新回归先在未修复版本失败；修后 canonical runner 四文件共 13 项通过。
- 官方 `scripts/check` 13 检查通过、health 无问题。
- 只在独立验收 checkout 应用此修复，产品 Hermes 未替换；本功能不能据此宣称已在产品可用。

## 当前真实证据

| 旅程                                | 结果                                                                                                                |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| 真实聊天经 skill/CLI 创建纯 webhook | 通过；真实任务卡、默认禁用                                                                                          |
| 公网跨 profile 接收及真实模型结果   | 修复前 503；隔离原生修复后 202，原生 session 完成并回到私聊                                                         |
| Windows 候选 App                    | 完整旅程通过：建任务、详情、复制、保密交付、公网测试、完成结果、暂停 403、轮换后旧钥 401                            |
| 原生重复 delivery ID                | 相同事件返回 200 `duplicate`，没有增加执行                                                                          |
| 非选定事件                          | 原生返回 200 `ignored`，未冒充执行完成                                                                              |
| 错误密钥、另一账号管理入口          | 公网 401；跨账号 get/credentials/grant/test 全部 forbidden                                                          |
| 组合任务                            | 同一个原生 cron 的公网 direct 与定时 builtin 执行均真实完成，session 独立、结果一致；验收后暂停定时部分并保留历史   |
| 模型初始化失败                      | 202 接收后原生 terminal/failed；旧 hook 方案漏报，改为原生持久记录后补回原失败结果，未重新执行；归档 Bot 后入口 403 |
| Android                             | 候选模拟器真实旅程进行中；没有真机通过结论                                                                          |

Windows 原生 UI 测试早期因 offscreen finder、未等待按钮恢复及 Android 截图重复转换失败，分别修正验收脚本；没有将这些失败记录为整条旅程通过。

## 工程检查及未完成项

- 当前 lint、typecheck、29 文件 / 44 项服务端测试、Node/Relay/Web/distribution build 通过；Flutter analyze 无问题。
- 仍需完成：实际定时与 webhook 双触发、Agent helper 脚本、运行中独立任务、原生模型失败及权限、服务重启/离线、Android 候选与双端 release、独立检出与回归。
- 临时公网 `/hooks/` 指向独立 QA Relay。验收结束撤回本轮路由，不覆盖并发 Caddy 改动；保留 QA 数据、日志与 profiles，不重启其他产品或整机。
- 原始响应、凭据和私有配置只保留在隔离现场，不进入 Git。既有 UI 改动及截图不纳入本模块提交。
