# nekodot

面向非技术用户的多智能体产品。Web/PWA 通过 Relay 连接用户自己的 Node，
Node 以官方 CLI/API 管理 Hermes。Node 是本地业务状态的唯一数据源。

## 架构

- apps/web：React 用户界面。
- apps/relay：连接与路由入口。
- apps/node：本机代理与 Hermes 集成。
- packages/protocol：Zod 边界协议及 TypeScript 类型。
- packages/fake-hermes：仅测试使用的真实事件回放服务。
- scripts：开发和真实 Hermes spike。
- docs/references、design：完整技术及视觉原件。

## 更新记录

### 2026-10-27 / 0.0
- 创建独立产品目录，保留原 PDF 和完整 HTML，提取 19 页伴随文本。
- 建立参考索引、凭证示例与工作约定。真实模型接入尚未验收。
