# Node 自动更新实现计划

状态：实现及本地验收完成，尚未发布生产。结果与范围见 [验收记录](node-auto-update-acceptance.md)；以下保留原实施方案。实现前先读 `AGENTS.md`。

## 目标

服务器（Relay）知道每台在线 Node 的版本。用户正在使用客户端时，如果 Node 比服务器发布的版本旧，就让 Node 在空闲时自动更新并重启。这样用户不用手动处理客户端和 Node 的版本不一致。

已知的实际问题：新版客户端新建 Bot 时默认随机头像形状，旧 Node 只接受 `dot`，约 7/8 的情况会返回 `invalid_params`。

## 已定决策

| 问题           | 决定                                        | 原因                                                                               |
| -------------- | ------------------------------------------- | ---------------------------------------------------------------------------------- |
| 谁决定更新     | Relay 通知，Node 自己校验、下载和切换       | Relay 不应在用户电脑上执行任何东西                                                 |
| 更新到哪个版本 | 始终是服务器发布的版本，客户端不上报版本    | 发布顺序固定为先 Relay 和 Node、后客户端，所以在用的客户端都不会比已发布的 Node 新 |
| 何时检查       | Node 连上时，以及该账号的客户端连上时       | 只替换 `downloads` 目录、不重启 Relay 的发布也能被发现，并且不需要轮询             |
| 何时重启       | 只在 Node 空闲时                            | 不打断正在运行的任务                                                               |
| 如何防篡改     | Ed25519 签名，私钥不进服务器和仓库          | 否则 Relay 被攻破就等于能在所有用户电脑上执行代码                                  |
| 坏版本怎么办   | 启动后连不上 Relay 就自动回滚，并跳过该版本 | Node 本身可能已坏，回滚逻辑放在 shell 启动脚本里                                   |

## 现有 Node 无法自动升级

已安装的 Node 没有更新逻辑，这些 Node 必须手动运行一次安装命令，之后才能自动更新。代码无法绕过这一点。

- 旧 Node 的版本号写死为 `1.0.0`（`apps/node/src/connection.ts:83`），可以据此识别。
- **绝不能给旧 Node 发 `node.update`。** 旧版 `envelopeSchema.parse` 遇到未知类型会抛错并关闭连接（`connection.ts:86-88`），之后不断重连。
- 客户端要提示这些 Node 运行一次安装命令。`install.sh` 已支持不带配对码重跑，身份和历史都会保留。

## 版本与发布

- **版本号：** 14 位 UTC 时间戳（`YYYYMMDDHHmmss`），只增不减。回退也要发布一个更高版本号的旧代码。
- **占位符：** 新建 `apps/node/src/release.ts`：
  ```ts
  export const nodeVersion = '__NEKODOT_NODE_VERSION__';
  export const releaseKey = '__NEKODOT_RELEASE_KEY__';
  export const isRelease = /^\d{14}$/.test(nodeVersion);
  ```
  未盖章的开发版 `isRelease` 为 false，永远不自更新。
  注意：盖章是全文字符串替换，判断时不能写 `nodeVersion === '__NEKODOT_NODE_VERSION__'`，否则这段比较也会被替换。
- **发布脚本：** 新建 `scripts/release-node.mjs`，并加入根 `package.json` 的 `release:node`：
  1. 读取 `NEKODOT_RELEASE_KEY_FILE` 指向的 Ed25519 私钥（PEM）。缺失就报错退出，没有回退。
  2. 把 `dist/distribution/nekodot-node.cjs` 里的两个占位符替换为版本号和公钥（SPKI DER 的 base64）。如果任一占位符不存在就报错。
  3. 计算盖章后文件的 sha256，并对 `nekodot-node:<version>:<sha256>` 签名。
  4. 写入 `dist/distribution/nekodot-node.json`：`{ version, sha256, signature }`。
- **避免旧清单：** `scripts/build-distribution.mjs` 要清掉已有的 `nekodot-node.json`，否则新 bundle 会配上旧清单。普通 `pnpm build` 不需要私钥，产物就是开发版。
- **私钥：** 由发布者生成，放在仓库外，并要备份。**Codex 不要生成或提交生产私钥。** 验收用的测试私钥放 `.runtime/`。私钥丢失或轮换后，所有 Node 都要手动重跑一次安装命令。
- **发布规则（写进 `deploy/README.md`）：** 用户的 Node 会自动升级，而客户端不一定已更新，所以新版 Node 要继续兼容还在使用的旧客户端。

## 协议（`packages/protocol`）

- `envelope.ts`：`type` 增加 `node.update`，`payloadSchemas` 增加 `z.strictObject({ version: nodeVersionSchema })`。
- 增加并导出 `nodeVersionSchema`（14 位数字）和 `nodeReleaseSchema`（`version`、64 位十六进制 `sha256`、`signature`）。
- `helloSchema` 的 `version` **保持宽松**，旧 Node 和现有测试都依赖这一点。
- `http.ts`：`nodeSummarySchema` 增加 `updateCommand: z.string().nullable()`。

## Relay（`apps/relay`）

- `downloads.ts`：
  - 增加 `GET /downloads/nekodot-node.json`，`no-store`，文件不存在返回 404。
  - 导出 `latestNodeRelease(directory)`：每次读取并按 schema 校验清单，文件不存在时返回 undefined。清单非法时记日志，并同样返回 undefined。
- `routing.ts`：
  - `registerRouting` 增加参数 `latestRelease: () => Promise<NodeRelease | undefined>`。没有配置 `distributionDirectory` 时传返回 undefined 的函数。
  - 新增内存 `versions: Map<nodeId, string>`，在 Node hello 时写入（`routing.ts:115`），断开时移除。注意只有当前 socket 断开才移除，和 `nodes` 的处理一致（`routing.ts:224`）。
  - 新增 `offerUpdate(nodeId)`：只有当前版本匹配 14 位数字、且小于清单版本时才发 `node.update`。
  - 在 `hello.ok` 之后触发：Node 连上时检查它自己；客户端连上时检查该账号的所有在线 Node。
  - 导出 `needsManualUpdate(id)`，即 `versions.get(id) === '1.0.0'`。
- `auth.ts`：`/api/me` 增加 `updateCommand`。`needsManualUpdate` 为真时返回 `curl -fsSL '<publicUrl>/install.sh' | bash`，否则返回 null。

## Node（`apps/node`）

新建 `src/updater.ts`，只提供一个 `NodeUpdater` 类，收到通知时的流程如下。

1. **检查条件：**
   - `isRelease` 为真。
   - 运行文件 `__filename` 等于 `<NEKODOT_HOME>/bin/nekodot-node.cjs`。
   - 上次失败超过 10 分钟，且当前没有更新在进行。
2. 从 `credentials.relayUrl` 下载清单，用 `releaseKey` 验证签名。
3. 版本必须大于当前版本，也大于 `bin/update-rejected` 记录的版本。**这里以签名过的清单为准，不信任 `node.update` 里的版本号。**
4. 下载 bundle 到 `bin/nekodot-node.cjs.next`（上限 32 MB），校验 sha256，再用当前 Node 执行 `node --check`。
5. 等待空闲：`app.idle` 为真才继续，否则每 30 秒再查一次。空闲时重新下载清单，如果版本变了就回到第 2 步。
6. **切换，顺序不能变：**
   1. 复制当前文件到 `nekodot-node.cjs.previous`。
   2. 把版本写入 `bin/update-pending`。
   3. 删除 `bin/update-tried`。
   4. `rename` `.next` 到 `nekodot-node.cjs`。
7. 走 `index.ts` 现有的 `shutdown()`，然后以退出码 75 退出。两种 service 都是 `Restart=on-failure`，非零退出才会重启。

其他改动：

- `connection.ts`：hello 的版本改用 `options.version`；收到 `node.update` 时校验 payload 并调用 `options.onUpdate`。
- `index.ts`：连接 `NodeUpdater`。`onReady`（即 `hello.ok`）时清掉 `update-pending` 和 `update-tried`，表示新版本确认可用。
- `app.ts`：增加 `get idle()`，要求 `activeRuns` 和 `consumers` 都为空。实现时确认群聊接力轮次之间（`group_chains`）和 welcome 运行是否也算忙；如果重启不能恢复，就要算忙。
- 失败只写日志，不影响 Node 正常工作。

## 回滚（`deploy/install.sh`）

修改第 185 行生成的启动脚本，在 `exec` 之前加入：

```bash
if [ "${1:-}" = run ] && [ -f "$home/bin/update-pending" ]; then
  if [ -f "$home/bin/update-tried" ]; then
    mv -f "$home/bin/nekodot-node.cjs.previous" "$home/bin/nekodot-node.cjs"
    mv -f "$home/bin/update-pending" "$home/bin/update-rejected"
    rm -f "$home/bin/update-tried"
  else
    : > "$home/bin/update-tried"
  fi
fi
```

（写进 heredoc 时要转义 `$`。）

- 含义：切换后第一次启动留下 `update-tried`，`hello.ok` 会把它清掉。如果下次启动它还在，说明上次没连上 Relay，于是回滚。
- 已知代价：切换后如果恰好 Relay 长时间不可用，或机器在这段时间重启，可能误回滚并跳过该版本，下个版本会恢复。这个代价可以接受。
- 第 184 行改为先下载到临时文件再 `mv`，并清除 `update-pending`、`update-tried`、`update-rejected`，让手动重装成为确定的恢复手段。

**发布规则（写进 `deploy/README.md`）：** Node 的数据库迁移必须和上一版兼容。回滚后旧代码要能打开已迁移的库。当前 `apps/node/src/database.ts` 只处理升级，不拒绝更高版本，这条规则目前靠发布者遵守。

## 客户端（`apps/native`、`apps/web`）

- 当前选中的 Node 在线且 `updateCommand` 不为 null 时，在主界面显示一条提示：一句话、命令和复制按钮。文案尽量短，如“这台电脑需要更新一次 / This computer needs one update”。样式复用 `features/pairing.dart` 的命令面板，网页版用 `apps/web/src/features/pairing.tsx` 的对应部分。
- 收到 `node.status` 且 `online: true` 时，重新请求 `/me`。否则用户更新完提示也不会消失。实现时确认两端现有的处理位置。
- 自动更新期间不加新状态，沿用现有的离线和恢复显示。

## 文档

更新 `deploy/README.md`（`pnpm build:distribution` 之后运行 `pnpm release:node`，以及私钥说明）、`deploy/product/README.md` 的部署顺序，加上 `Summary.md` 和 `docs/progress.md`。

建议按模块分别做本地提交：① 协议和发布脚本 ② Relay ③ Node ④ 安装脚本 ⑤ 客户端 ⑥ 验收文档。

## 测试

**自动化：**

- `protocol`：`node.update`、版本和清单 schema；宽松 hello 仍然通过。
- `relay`：
  - 旧 Node 发 `1.0.0` 时不收到 `node.update`，连接不断开，且 `updateCommand` 有值。
  - 版本较低时收到通知；版本相同或更高时不收到。
  - 客户端连接会触发检查；没有清单时不发通知。
- `node`（`updater.test.ts`，用临时目录和测试密钥）：
  - 签名错误、sha256 不符、版本不高于当前、被拒版本都不切换。
  - 下载和校验之后等待空闲，空闲后才切换。
  - 文件切换顺序正确。
  - 开发版或文件路径不符时不执行。
- `release-node.mjs`：占位符缺失时失败；产物能通过 `updater` 的校验。

**真实验收（不可用单元测试替代）：** 在 WSL Ubuntu-24.04 里用隔离的 `NEKODOT_HOME` 和本地 Relay，通过真实 `install.sh` 和 systemd user service，用测试私钥盖章 v1、v2。逐项确认：

1. v1 → v2 自动更新，Node 身份和历史不变，客户端显示恢复在线。
2. 任务运行中不重启，结束后才更新。
3. v2 启动即崩溃时，回滚到 v1、写入 `update-rejected`，之后不再反复尝试。
4. 签名被篡改的清单、内容被篡改的 bundle 都不切换，Node 继续工作。
5. 真实旧 bundle（`1.0.0`，取 `apps/node/dist/index.cjs` 的旧提交构建）连接新 Relay 不会断线循环；Windows 客户端和 Edge 显示提示；运行命令后提示消失，以后能自动更新。
6. 升级后新建非 `dot` 头像的 Bot 成功，这是这次功能要解决的问题。

## 不在范围内

- 自动更新 Hermes 和私有 Node.js 运行时（固定 24.22.1）。发布的 bundle 必须能在这个运行时上运行。
- 客户端（App）自身的更新。
- Windows App 一键安装 Node。

## 约束

- 不推送，不部署，不碰生产 `nekodot.com` 和生产 Node。
- 不提交私钥、`node.json` 或运行目录。
- 工作区里其他 agent 未提交的 `docs/evidence` 文件不要暂存或还原。
