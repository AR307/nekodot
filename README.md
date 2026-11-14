<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/nekodot-mark-dark.svg">
    <img src=".github/assets/nekodot-mark.svg" alt="nekodot" width="72" height="72">
  </picture>
</p>

<h1 align="center">nekodot</h1>

<p align="center">
  <strong>Your new-generation personal AI assistant.</strong><br>
  Your own model, your own computer, in reach from Windows and Android.<br>
  Ask a Dot to research, work with files, use a browser, or build a small tool you can keep.
</p>

<p align="center">
  <a href="https://github.com/AR307/nekodot/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/AR307/nekodot/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/AR307/nekodot/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/AR307/nekodot?label=release&color=000000"></a>
</p>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a><br>
  <a href="https://www.nekodot.com">Website</a> ·
  <a href="https://www.nekodot.com/en/#start">Download</a> ·
  <a href="deploy/README.md">Self-hosting</a> ·
  <a href="LICENSE">MIT License</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/desk-group-dark.webp">
  <img src=".github/assets/desk-group-light.webp" alt="nekodot for Windows: a conversation with a Dot, the rail and Recent list">
</picture>

<p align="center"><sub>The native client, using a demonstration account.</sub></p>

## Talk to your Dot

Give your Dot a task. It can search, browse, read and write files, run tools, and hand back a result. When it delegates work, your conversation stays with that Dot: it brings back the result and asks any necessary questions in the chat.

Approvals and questions appear in the conversation. Add instructions while it works, queue another request, or stop the current task. The activity line stays above the composer; Flow shows the actual steps of the current or latest task.

For a team, create a group, choose its lead Dot, and give each member a role. Mention a member or use `@everyone`; Dots can hand work to one another. A group runs one Dot at a time and pauses after six handoff turns.

## Build a Space

Ask for a ledger, word cards, a packing list, or another small tool. Your Dot builds a page with its own icon and publishes it to **Spaces**. Open it from the preview gallery, use it on desktop or phone, and ask the Dot for changes.

Space records sync through your Node. Downloaded pages and cached records remain available offline; features that use a remote service still need a connection.

## What is included

| Area           | Capabilities                                                                                                                            |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Models         | Select a source and model for each Dot; use the model catalog and supported reasoning controls.                                         |
| Files          | Attach files and images; read Markdown, PDF and supported Office documents inside the app.                                              |
| Plugin center  | Manage Skills, plugins, MCP servers and account connectors. Connector access requires your authorization.                               |
| Memory         | Edit Dot memory and instructions; share your account-level user memory across your computers.                                           |
| Routines       | Schedule tasks or trigger them through Webhooks; inspect runs and follow up on their results.                                           |
| Secret handoff | Enter credentials in encrypted chat cards. The Dot receives a reference; reusable credentials stay scoped to that Dot and approved use. |
| Screen         | View and take over supported Linux browser/desktop sessions. Windows desktop control is enabled separately per Dot.                     |
| Statistics     | View the usage calendar, input/output/cache tokens and conversation/task shares; export CSV.                                            |
| Native clients | Windows and Android, light/dark themes, English/Chinese, desktop side panels and mobile navigation.                                     |

## Get started

1. Install [Windows x64](https://github.com/AR307/nekodot/releases/latest/download/nekodot-windows-x64.exe) or [Android arm64](https://github.com/AR307/nekodot/releases/latest/download/nekodot-android-arm64.apk).
2. Create and verify your account, then sign in.
3. Connect a computer. On Windows, choose **This computer** to install the managed runtime. For a Linux x64 server or WSL2 Ubuntu with systemd, run the pairing command provided by the app.
4. Add a model source, select its model, and create a Dot.
5. Start a conversation, build a Space, or add a group for collaboration.

The computer running your Dots must stay on. Nodes connect outward to the Relay, so no inbound port is required on that computer. Phone notifications depend on system permissions and background delivery.

Published installers target Windows 10/11 x64 and Android 10+ arm64. The Android APK is signed; the Windows installer is not Authenticode-signed. Android physical-device and macOS/Linux desktop validation remain outstanding. See [release notes](https://github.com/AR307/nekodot/releases) for the actual validation scope.

## How it works

    Flutter app (Windows / Android)
        │ HTTPS / WebSocket
        ▼
      Relay — accounts, pairing, routing, usage statistics, updates
        ▲ outbound connection
      Node — chat history, files, Spaces, Dot settings, group coordination
        │ local management API and canonical WebSocket
      Hermes — a separate profile for each Dot

Hermes owns the model/tool loop, native sessions, memory and extensions. nekodot supplies the interface, connectivity and coordination, without a second Agent execution engine. The managed runtime remains Hermes v0.22.6 / v0.22.6-r3.

The app stores login state, preferences and local caches. The Relay stores account, pairing and usage metadata and forwards chat/file traffic. Your Node and Hermes profiles keep conversations, delivered files, Space records and credentials.

Model requests go to the provider you choose. Ordinary chat is not end-to-end encrypted; secret cards use a separate encrypted handoff. Official website: **www.nekodot.com**. API, WebSocket, installation and download endpoints: **api.nekodot.com**.

## Development and self-hosting

Flutter clients; TypeScript, Fastify, WebSocket and SQLite services. Build with Node 24 and pnpm 10.34.5:

    pnpm install --frozen-lockfile
    pnpm lint && pnpm typecheck && pnpm test
    pnpm build
    pnpm native:analyze && pnpm native:test

See [native client setup](apps/native/README.md) and [Relay deployment](deploy/README.md).

    apps/native          Flutter clients and native platform integrations
    apps/relay           Accounts, pairing, routing, usage and releases
    apps/node            Persistence, Hermes integration and coordination
    packages/protocol    Shared protocol and validation schemas
    packages/fake-hermes Test-only recorded event replay
    third_party          Native document preview dependencies and notices
    deploy               Images, installers and service definitions
    scripts              Build, package and release tooling
    tests                Test helpers and recorded events

Component and replay tests supplement real-client validation; they do not prove model or device behavior.

## Credits and license

- [Hermes Agent](https://hermes-agent.nousresearch.com) by Nous Research powers the Dots.
- [Nunito](https://fonts.google.com/specimen/Nunito) and [JetBrains Mono](https://www.jetbrains.com/lp/mono/) use the SIL Open Font License 1.1.
- [Material Symbols](https://fonts.google.com/icons) uses the Apache License 2.0.
- See [third-party notices](third_party/README.md) for native Office preview dependencies.

[MIT License](LICENSE). Third-party dependencies retain their own licenses.
