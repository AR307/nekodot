# nekodot

面向非技术用户的多智能体小队。当前是 Phase 0 工程基础，不包含聊天或配对业务。

## 开发

要求 Node 24 LTS、pnpm 10.34.5。

```
pnpm install
pnpm dev
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm test:e2e
```

Web：http://127.0.0.1:4318；Relay 健康检查：http://127.0.0.1:4319/health。
Windows 当前项目自带忽略的 Node 24，可在 PowerShell 运行 . ./scripts/activate.ps1。
真实 Hermes spike 在 WSL Ubuntu 24.04 执行；使用方法见 docs/hermes-notes.md。

参考索引见 docs/references/README.md；阶段结果见 docs/progress.md。
复制 .env.example 为 .env 后填入真实 provider。不要提交密钥或运行目录。
