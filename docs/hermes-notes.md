# Hermes Phase 0 调研与真实接入记录

验证日期：2026-10-27。针对固定官方源码，不声称覆盖其他版本。

## 环境与复现

- 原仓库 D:/nekodot 只读；官方 baseline：a382af23f4c067d23463b5781958684c2cda82bc。
- Ubuntu-24.04，使用 bash --noprofile --norc，没有修复全局 shell。
- 快照 CLI 自报 Hermes Agent vunknown (2026.9.24)，因为归档不带 .git。
- PM Python 3.14.9、OpenAI SDK 2.54.0；独立 Node 24.22.1、pnpm 10.34.5。
- gateway 仅监听 127.0.0.1:18642；Chromium 测试仅监听 127.0.0.1:19222。
- 密钥读自忽略的 .env；fixture 替换 provider key、gateway key、endpoint、模型名。
- 现场位于 runtime 同级的独立缓存目录；最近位置见忽略的 .runtime/hermes-last-spike.json。
  初次 /tmp 现场未跨 WSL 实例重启保留，因此最终脚本改用持久缓存。脚本不删除现场。

Windows 先激活项目 Node 24，再构建：

```powershell
. ./scripts/activate.ps1
pnpm install --frozen-lockfile
pnpm spike:build
wsl -d Ubuntu-24.04 -- bash --noprofile --norc -c "/root/.cache/nekodot-phase0/node/bin/node /mnt/d/nekodot-app/dist/scripts/spike-hermes.mjs --root /mnt/d/nekodot-app --source /root/.cache/nekodot-phase0/hermes-source --runtime /root/.cache/nekodot-phase0/tools"
```

--source 指向真实官方源码，--runtime 指向官方 PM 工具目录，上述为本机实际路径。
脚本创建 default hub、bot profile，并在 gateway 启动后新增 profile。
Node 的 CLI 调用全部经过 apps/node/src/hermes/cli.ts，显式绑定两个隔离环境目录。

## 1. 官方安装入口与非交互参数

官方入口为 https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh 。
scripts/install.sh:65–76 支持 --non-interactive、--skip-setup、--dir、--hermes-home、--skip-browser。
审核脚本后可执行：

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
  | bash -s -- --non-interactive --hermes-home "$HERMES_HOME" --dir "$HERMES_SOURCE"
```

本轮实际不是上述 curl 全安装：将固定源码归档至独立目录，运行官方
bash setup-hermes.sh --runtime-only，再由 scripts/run-in-hermes-env 启动。
PM 完成独立 Python、依赖及 Chromium 安装，没有使用裸 pip/uv 修改既有环境。

## 2. 自定义 HERMES_HOME 是否有效

有效。实际 CLI 形态：

```bash
HERMES_HOME=<isolated-home> HERMES_RUNTIME_DIR=<isolated-tools> \
  bash scripts/run-in-hermes-env python hermes profile create nk-xxxxxx --no-alias --no-skills
HERMES_HOME=<isolated-home> HERMES_RUNTIME_DIR=<isolated-tools> \
  bash scripts/run-in-hermes-env python hermes gateway run
```

profile 位于隔离 home 下的 profiles/<name>；所有真实测试走 /p/<name>/...。
源码依据：hermes_cli/profiles.py:2390–2417。共享结果见 docs/fixtures/spike-report.json；
最近现场路径保留在忽略的运行索引中。

## 3. 新增 profile 是否要重启

本次 multiplex 实测不需要。配置 gateway.multiplex_profiles: true，gateway 健康后再创建
profile、写配置并轮询其 /p/<name>/health，成功且未重启。报告 hotAdd:true 对应该检查。
源码 profile 创建路径调用 _notify_multiplexer。

## 4. 自定义 provider 与 OpenRouter 密钥

本次真实有效配置：

```yaml
model:
  provider: custom
  base_url: <configured-endpoint>
  default: <configured-model>
  api_key: '${NEKODOT_PROVIDER_API_KEY}'
  api_mode: chat_completions
gateway:
  multiplex_profiles: true
```

profile .env 提供 NEKODOT_PROVIDER_API_KEY、API_SERVER_ENABLED=true、
API_SERVER_HOST=127.0.0.1、API_SERVER_PORT=18642 和随机 API_SERVER_KEY。
新建配置与密钥文件指定 0600；key 没有内嵌 YAML。
官方写法见 hermes_cli/model_setup_flows_custom.py:167–184。
OpenRouter provider 为 openrouter，密钥入口 OPENROUTER_API_KEY，见
`plugins/model-providers/openrouter/__init__.py:208`。本轮没有真实调用 OpenRouter。

## 5. SSE 实际事件与字段

真实 wire format 没有 event: 行，事件名在 JSON event 字段：

```text
id: 1
data: {"event":"tool.started","run_id":"...","timestamp":1793094168.4,"tool":"terminal","preview":"sleep 45 + 1 command","tool_call_id":"call_...","seq":1}
```

所有已录制事件带 event、run_id、timestamp、seq，SSE id 对应 seq。

| 事件             | 实测附加字段                                                         |
| ---------------- | -------------------------------------------------------------------- |
| message.delta    | delta                                                                |
| tool.started     | tool, preview, tool_call_id                                          |
| tool.completed   | tool, duration, error, tool_call_id, preview                         |
| approval.request | kind, prompt_id, execution_generation, command, description, choices |
| approval.settled | prompt_id, execution_generation                                      |
| run.completed    | output, usage, runtime, completed, partial, interrupted              |
| run.cancelled    | completed:false, partial, interrupted:true, turn_exit_reason         |

Hermes duration 单位为秒，产品 durationMs 映射时乘 1000；本轮短工具常为 0。
查询审批状态为 waiting_for_approval，pending_controls 返回 prompt_id、kind、execution_generation。
审批请求使用 request_id 字段；实际响应为 {run_id,status:"resolved",prompt_id}。POST stop 返回 stopping，流结束后查询最终 cancelled。
工具拒绝时 error:true，但模型正常解释拒绝后整个 run 仍可 completed。

证据：runs-basic、runs-tools、runs-tools-approval、runs-approval-deny、runs-stop 的 .sse 与
同名 .state.json；run-states.json 还保存实际审批和停止响应。

## 6. 工具关联 ID

本次 started/completed 均有配对的 tool_call_id。关联使用 (run_id, tool_call_id)，不靠工具名。
源码依据：gateway/platforms/api_server_runs.py:93–101。
其他版本若缺 ID，仅在确认单 run 串行执行时才可用 start 事件序号标记当前工具、与下一完成事件配对；
并发场景不能仅凭工具名可靠恢复关联。本轮没有加入任何运行时降级代码。

## 7. 自有 Chromium 与工具名

持久配置 browser.cdp_url: http://127.0.0.1:19222，也支持 BROWSER_CDP_URL 与 /browser connect。
作用域读取见 tools/browser_session_cdp.py:92–108。
当前主工具是 browser_exec，伴随工具为 browser_cdp、browser_dialog、browser_vault。
其中 cdp/dialog 仅在配置 CDP endpoint 时提供。旧 browser_navigate 等不适用于本 baseline。
源码依据：website/docs/user-guide/features/browser.md:10–21,499,525–531。

scripts/spike-browser.py 实际启动独立 Chromium，通过 Hermes browser_cdp 的
Browser.getVersion 与 Target.getTargets 成功读取 Chrome 145.0.7632.6 和一个页面；
browser_exec_available() 为 true。结果见 docs/fixtures/browser-cdp.json。
这是配置连接与工具可用性验证，不声称完成过浏览器模型任务或 Phase 4 接管。

```bash
HERMES_HOME=<isolated-home> HERMES_RUNTIME_DIR=<isolated-tools> \
  bash scripts/run-in-hermes-env python /mnt/d/nekodot-app/scripts/spike-browser.py \
  --root /mnt/d/nekodot-app --runtime <isolated-tools> \
  --chromium <isolated-tools>/chromium-1208/chrome-linux64/chrome
```

## PDF 裁切字段的定稿

- Envelope 的 p... 根据第 8 页心跳文字补齐为 pong。
- tool error?: boo... 补为 boolean，以真实 tool.completed.error 为依据。
- approval prompt: s... 补为 string，取真实 description/command；requestId 对应 prompt_id，
  executionGeneration 对应 execution_generation；只提供 once/deny。
- durationMs 保留 PDF 产品单位，未来映射层将 Hermes 秒转换为毫秒。
- text/commentary/system 内容使用 {text}；审批卡可带可选 choice 记录已作选择。
- 工具执行中的消息状态保持 streaming，活动状态才用 tool。
- 实体按 RPC 和可见 SQL 字段闭合；本阶段不猜测裁切 SQL 建表，数据库留待 Phase 1。
- models.options 按 PDF 透传，screen.status 只定义协议；错误定义集中在 errors.ts。

## 发现并修正的问题

1. 初版从 event: 行读取事件名，导致审批未响应超时；改读 JSON event，真实 fixture 验证分块/CRLF。
2. 最初 Python stop 探针可能等待审批；停止后不响应失效审批，最终改用无写入的 sleep 45。
3. 一轮模型未读就覆盖已有文件，被 Hermes 拒绝；场景固定为完整读取后 patch，没有关闭检查。
4. 失败尝试没有标记通过，已收集的失败 fixture 保留在忽略的 .runtime/spike-attempts/。

## Phase 1：原生 steer 与产品整栈实测

验证日期仍为 2026-10-27；沿用上述官方 baseline、Ubuntu 24.04、Node 24.22.1 与独立 PM runtime。
Windows 编辑仓库与 WSL 检出各自安装 node_modules。真实产品走 Edge → WSL Relay → Node CLI → Hermes → 本地配置的自定义 API；没有改 Hermes 核心。

### 运行命令和保留现场

独立检出在 `/root/.cache/nekodot-phase1/acceptance-20261027-223030/app`，Node 数据在同级 `node`。
实际使用的命令形态如下，JWT_SECRET 仅在启动 shell 中本地生成：

```bash
PORT=4329 WEB_DIR="$APP/apps/web/dist" DATA_DIR="$CASE/relay" \
  PUBLIC_URL=http://127.0.0.1:4329 node apps/relay/dist/index.js
NEKODOT_HOME="$CASE/node" node apps/node/dist/index.cjs pair \
  --relay http://127.0.0.1:4329 --code <browser-pairing-code> --name 'nekodot WSL computer'
NEKODOT_HOME="$CASE/node" node apps/node/dist/index.cjs run \
  --hermes-source /root/.cache/nekodot-phase0/hermes-source \
  --hermes-runtime /root/.cache/nekodot-phase0/tools
```

WSL 会话退出时直接派生的后台进程曾被回收；最终使用仅属于本验收的 transient systemd unit
`nekodot-phase1-acceptance.service` 保持 Node，Relay 在独立工具会话前台运行。
未修改全局 shell 或 WSL 网络设置；现场、日志、失败尝试与 profile 都保留，未执行删除。

### API 行为与映射

- 原生补充入口：`POST /p/<profile>/v1/runs/<runId>/steer`，body 为 `{ "input": "..." }`。
  接口接受后才保存新的用户消息；后续文本进入该 run 的新回复段。
- 普通回合 thread 为 `nk_dm_<conversationId>`，Idempotency-Key 使用产品用户消息 ID。
- SSE 实测事件为 `run.steered`，`accepted:true` 仅表示接受；终态 `pending_steer` 非空表示尚未消费。
  产品保留该提示及放回输入框的入口，不自动新建 run。
- `run.completed.output` 只校正最后的回复段，已有文本与工具卡不被替换。
- stream 与普通 HTTP 的超时分开；Last-Event-ID 使用已持久化的 SSE seq。节点重启查询已知 run，不重新发送用户任务。
- 审批始终取实际 pending_controls 的 prompt_id/execution_generation，操作只有 once/deny，结果卡留在历史。

单独 steer spike 记录于 `runs-steer.sse` 和同名 state；完整产品资料为
`phase1-live-allow`、`phase1-live-deny`、`phase1-live-steer`、`phase1-live-stop` 的 SSE/state。
所有 fixture 去除 endpoint、模型名、API key 与实际临时路径。

### 实际结果

产品验收从 2026-10-27 14:44:15 UTC 开始，于 14:48:08 UTC 完成：

- 网页注册、CLI 配对、提供方配置、热建 bot，真实文本回复 NEKODOT_PHASE1_REAL_OK。
- 受保护测试 AGENTS.md：审批中刷新仍能允许；允许后文件增加指定一行。拒绝后文件不变，无重试或换路径。
- 工具运行时网页补充指令，保持同一 run，最终 NEKODOT_PHASE1_STEER_OK；实际 terminal 调用和文件效果各一次。
- 执行中网页停止，Hermes 最终状态 cancelled；Node 实际结束再启动，bot 与历史恢复。
- 实际浏览器无 pageerror。后续用最新 WSL 构建重看保留历史，390/768/1440px 均通过；该视觉复验不新增模型调用。

完整场景和 runId 见 `docs/evidence/phase1-live-report.json`，最终视口复验见
`phase1-live-visual-report.json`。OpenRouter 只完成网页配置、托管文件和密钥切换场景检查，未调用其付费模型。
