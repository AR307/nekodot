<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/nekodot-mark-dark.svg">
    <img src=".github/assets/nekodot-mark.svg" alt="nekodot" width="72" height="72">
  </picture>
</p>

<h1 align="center">nekodot</h1>

<p align="center">
  <strong>A team of Bots, working on your own computer.</strong><br>
  Research, reports, spreadsheets, and browser tasks—give each Bot a role.<br>
  They work with your files and browser, collaborate in group chats, and follow your approval settings.<br>
  Each Bot is a native <a href="https://hermes-agent.nousresearch.com">Hermes Agent</a> profile.
</p>

<p align="center">
  <a href="https://github.com/AR307/nekodot/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/AR307/nekodot/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Node 24 LTS" src="https://img.shields.io/badge/node-24%20LTS-000000">
  <a href="https://github.com/AR307/nekodot/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/AR307/nekodot?label=release&color=000000"></a>
</p>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a><br>
  <a href="https://www.nekodot.com">Website</a> ·
  <a href="https://www.nekodot.com/#start">Download</a> ·
  <a href="LICENSE">MIT License</a><br>
  <a href="#what-you-can-do">What you can do</a> ·
  <a href="#features">Features</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#development">Development</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/desk-group-dark.webp">
  <img src=".github/assets/desk-group-light.webp" alt="nekodot for Windows: Bot sidebar and a collaborative group chat">
</picture>

<p align="center"><sub>A weekly-report team: one Bot drafts, another checks the sources. The screenshot uses demo data.</sub></p>

> [!NOTE]
> The product uses native Flutter clients. See [Releases](https://github.com/AR307/nekodot/releases) for changes and platform-specific validation. Screenshots may show features newer than the latest published version.

## What you can do

### Let Bots work together

Create a group, choose its lead Bot, and assign each member a role. Without a mention, the lead responds; mention a Bot to select it, or use @everyone to include the group. Bots can hand work to one another.

> @bibi, draft this week's report, then ask @xiaoyan to check the sources.

- One Bot works at a time within a group; separate groups can run independently.
- The default relay limit is six turns and can be configured.
- Follow the actual tool activity and handoffs in the live Flowchart.

### Run on your own computer

On Windows, choose **This computer** when adding a computer. The app prepares an isolated Node and Hermes installation in your selected directory and pairs it with your account. Bots can work with local files. For an always-on setup, install a node on a Linux server instead.

Nodes connect outbound to the Relay, so you do not need to expose inbound ports on the computer running your Bots.

### Stay in control

Tool use follows Hermes approval rules. When approval is required, respond in chat. You can answer native questions, steer an active task, or stop it. Group-wide stop also clears queued handoffs.

Messages, tool activity, and execution state sync across devices. Previously loaded history and drafts remain available during a connection interruption; reconnecting restores the live state.

### Use your phone away from your desk

The Android app connects to the same nodes as the desktop client. Read replies, respond to questions, and handle approvals from your phone. Notifications depend on system permission and the platform's background-delivery behavior.

## Features

| Feature                      | What it does                                                                                                                                                                                                        |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Bots and models**          | Give each Bot a name, avatar, role, model source, and model. Browse the model catalog and use supported reasoning controls.                                                                                         |
| **Sessions**                 | Create, browse, and switch native Hermes sessions.                                                                                                                                                                  |
| **Files**                    | Attach files and images; drag files into desktop chat. Preview supported documents, including DOCX, XLSX, and PPTX, without leaving the app.                                                                        |
| **Screen access**            | View and take over a supported Linux browser or desktop. On Windows, desktop control is separately enabled per Bot and follows approvals.                                                                           |
| **Memory**                   | Edit SOUL.md, MEMORY.md, and USER.md; use native memory refinement. Account-level user memory can sync across nodes.                                                                                                |
| **Skills, plugins, and MCP** | Browse, install, enable, and configure extensions through the Hermes integration. Availability depends on the environment and extension.                                                                            |
| **Secret handoff**           | Submit keys and passwords through encrypted chat cards. The requesting Bot receives a credential reference, not the secret in ordinary chat. Optional saved credentials remain scoped to that Bot and approved use. |
| **Routines**                 | Create scheduled and Webhook-triggered tasks in chat, inspect their runs, and follow up on selected results.                                                                                                        |
| **Statistics**               | View the usage calendar, token categories, Bot/group and routine shares, and export CSV. Records start when collection is enabled.                                                                                  |
| **Multiple computers**       | Pair several nodes with one account and switch between them.                                                                                                                                                        |
| **Updates**                  | Check client versions in the app. Node updates switch when idle and retain rollback support.                                                                                                                        |
| **Native UI**                | Flutter Windows and Android clients, light/dark themes, English/Chinese, native screen rendering, and no embedded web client.                                                                                       |

nekodot does not implement a second Agent engine. Hermes owns the model/tool loop, profiles, sessions, memory, and extensions; nekodot provides the interface, connectivity, and group coordination.

## How it works

    Flutter app (Windows / Android)
          | HTTPS / WebSocket
          v
        Relay — accounts, pairing, routing, usage metadata
          ^
          | outbound connection from your node
          |
        Node — chat history, Bot settings, files, group coordination
          | local Hermes management API and canonical WebSocket
          v
        Hermes — a separate profile for each Bot

| Component      | Stored data                                                                                                                                                        |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| App            | Login state, preferences, and account-scoped local history/draft caches.                                                                                           |
| Relay          | Accounts, pairing and routing records, release metadata, and synchronized usage statistics. Chat and file traffic is forwarded rather than stored as chat history. |
| Node           | Chat history, run records, Bot configuration, delivered files, and encrypted product credentials.                                                                  |
| Hermes profile | Native sessions, memory, skills, plugins, and Hermes-managed model credentials.                                                                                    |

The Flutter app is the client; a locally installed Node/Hermes runs separately. Model requests go to the provider you configure. This is not an offline model runtime, and ordinary chat traffic is not end-to-end encrypted. Secret cards use their separate encrypted delivery path.

## Quick start

1. **Install the app:** [Windows x64](https://github.com/AR307/nekodot/releases/latest/download/nekodot-windows-x64.exe) (Windows 10/11; no Authenticode signature) or [Android arm64](https://github.com/AR307/nekodot/releases/latest/download/nekodot-android-arm64.apk) (Android 10+; signed APK).
2. **Create an account** with email verification, then sign in with your password.
3. **Connect a computer.** On Windows, choose **This computer**. Alternatively, run the command generated by the app on Linux x64 or WSL2 Ubuntu 24.04 with systemd. The installer prepares the managed Node 24/Hermes runtime and node service.
4. **Add a model source** using a supported account login or a custom API endpoint and key.
5. **Create a Bot:** choose its appearance, role, source, and model. Add a group when you want Bots to collaborate.

The website is **www.nekodot.com**. Official API, WebSocket, download, and installation endpoints use **api.nekodot.com**.

### Self-hosting

Use a Linux x64 server with Docker for the Relay. Build tooling uses Node 24 and pnpm 10.34.5. Bots may run on that server or on other paired computers.

Build the Relay image, deploy it with Docker Compose, and point the client at your Relay. See [deployment instructions](deploy/README.md).

## Development

Stack: Flutter, TypeScript, Fastify, WebSocket, node:sqlite, Zod, and Hermes Agent, with native platform integrations.

    pnpm install --frozen-lockfile
    pnpm lint && pnpm typecheck && pnpm test
    pnpm build
    pnpm native:analyze && pnpm native:test

Recorded-event and component tests supplement real-client validation; they do not prove real model or device behavior. Native client setup and build instructions are in [apps/native](apps/native/README.md).

    apps/native            Native Flutter product clients and screen UI
    apps/relay             Accounts, pairing, routing, files, usage, and updates
    apps/node              Persistence, Hermes integration, group routing, updates
    packages/protocol      Shared protocol and validation schemas
    packages/fake-hermes   Test-only recorded Hermes event replay
    third_party            Pinned native document preview dependencies
    deploy                 Relay image, installers, and service definitions
    scripts                Build, package, release, and validation tooling
    tests                  Test helpers and recorded Hermes events

## Platform status

Published installers target Windows x64 and Android arm64. The managed server runtime supports Linux x64. macOS/Linux desktop and other architectures are not implied to be release-tested merely because source support exists. Consult each release for tested journeys and outstanding device-specific checks.

## Credits

- [Hermes Agent](https://hermes-agent.nousresearch.com) by Nous Research powers the Bots.
- [Nunito](https://fonts.google.com/specimen/Nunito) and [JetBrains Mono](https://www.jetbrains.com/lp/mono/) are licensed under the SIL Open Font License 1.1.
- See [third-party notices](third_party/README.md) for the pinned native Office preview dependencies and their licenses.

## License

[MIT License](LICENSE). Third-party dependencies and fonts retain their own licenses.
