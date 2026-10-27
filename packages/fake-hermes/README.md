# 测试回放 Hermes

仅作为测试 devDependency 使用，不启动产品服务、不调用模型、不执行工具。
读取 docs/fixtures 中真实 spike 的 SSE 和状态；不会用手写回复替代模型验收。

```ts
import { startFakeHermes } from '@nekodot/fake-hermes';

const service = await startFakeHermes({
  fixturesDirectory: '/absolute/path/to/docs/fixtures',
  profiles: ['nk-abcdef'],
  apiKey: 'test-only-key',
});
// 通过 service.url + '/p/nk-abcdef' 使用真实 HTTP 客户端。
// 测试结束调用 await service.close()。
```

随机端口仅绑定 127.0.0.1。六类接口：profile health、POST run、GET events、GET run、POST stop、POST approval。
所有请求使用测试 Bearer key；跨 profile 查询返回 404。

创建 run 的 input 选择录制场景：

| input               | 行为                                           |
| ------------------- | ---------------------------------------------- |
| runs-basic          | 流式文本到 completed                           |
| runs-tools          | 工具开始/完成、文本到 completed                |
| runs-tools-approval | 在真实 approval.request 暂停，接受 once 后继续 |
| runs-approval-deny  | 在真实 approval.request 暂停，接受 deny 后继续 |
| runs-stop           | tool.started 后等待 stop，回放真实取消序列     |

审批请求需要匹配 pending_controls 的 prompt_id 和 execution_generation，字段名为 request_id。
每个审批场景使用对应实测结果，未录制的选择返回 409。其他场景也能 stop，复用实测 run.cancelled 事件。
响应保留录制字段，只替换本次 run/session 标识；事件以短间隔发送，不模拟原始模型耗时。
服务刻意只覆盖 Phase 0 依赖的接口，不提供模型兼容替代或完整 Hermes 仿真。
