# Windows 本机安装长路径修复

日期：2026-11-05。仅本地候选，未发布、未 push。

## 根因

用户的 `shutil.Error / [WinError 3]` 出现在 Hermes 将源码复制到账号独立 PM workspace 时。账号 UUID、安装标识和环境代次叠加后，conformance JSON 的完整路径超过 Windows 传统 MAX_PATH；不是这些源码文件没下载。开发机启用了长路径，普通运行掩盖了问题。

本轮仅修改隔离 Python 副本的 longPathAware manifest，不改注册表或原 Python。该进程实际 `RtlAreLongPathsEnabled() == false`。普通复制真实 conformance 目录出现 30 个失败，包含与用户一致的 WinError 3；最长路径 288 字符。

## 修复范围

- 用户明确允许最小 Hermes 安装补丁。`pm/workspace.py` 的核心源码、插件源码和修复快照复制改用 Hermes 已有 `long_root`，只在文件复制调用处使用扩展路径。没有改 Agent、审批、调度、网络或 profile 逻辑。
- Flutter 安装器在 Windows PM 安装、产品构建、安装验证及账号准备前应用该补丁，重复应用不重复改写。原文件保存在所选运行目录的 `logs/workspace-before-long-path.py`。
- `HERMES_HOME`、账号路径、PM facts 和模型运行路径仍为原路径；不搬数据，不要求用户改注册表，不增加 UI 说明。
- 曾验证过仅给 HERMES_HOME 增加扩展前缀的方案：PowerShell 路径提供程序和 Hermes 已有环境归属比较不接受该变化，因此该方案已全部撤回，未进入最终补丁。

## 实际验收

1. Windows 传统路径模式下，调用真正的 `_copy_core_inputs` 后 47 个 JSON 全部复制，最长扩展路径 292 字符。不是只断言字符串。
2. Hermes canonical `scripts/run_tests.sh`：两条 Windows 真实文件测试覆盖核心与插件 workspace。未修改源码上出现 `shutil.Error / WinError 3`；补丁后 2/2 通过。测试 Python 由官方 PM 创建环境，隔离可执行副本关闭 longPathAware；未改系统开关。
3. Flutter Windows integration 执行官方 `python-deps`、`products`、`config`、新账号 `pm install --extra all` 和重复安装，均通过。已有 owner 环境和新账号 facts 均保持普通路径，既有环境仍能启动。
4. 本次 Windows 原生候选、loopback QA Relay 4459、本次 Node 与 Hermes v0.22.6：真实登录，使用原有本机小助手及 `gpt-6.1-sol`，实际 `read_file` 读取中文路径文件、`write_file` 写入内容并核对，再发第二条消息成功。
5. 停止和重新启动同一个 Node 后历史保留，没有增加重复消息，退出后该隔离运行目录的子进程为 0。截图已人工视觉检查。
6. Hermes scripts/check --staged --base HEAD 的 13 项检查通过。Flutter analyze、33 项测试、TypeScript typecheck、ESLint、38 文件 / 75 项服务端测试通过；Windows Release 安装器构建通过，未做 Authenticode 签名。

## 证据和交付

- `docs/evidence/windows-long-path-20261105.json`：安装和原生旅程脱敏记录。
- `docs/evidence/windows-long-path-chat.png`：真实文件操作完成画面。
- `dist/native/nekodot_0.3.1_x64-setup.exe`：本地修复候选；旧候选保留在 `.runtime/windows-long-path/`。
- 原始日志和失败方案现场保留在 `.runtime/windows-long-path/`，不提交 Git。Hermes 补丁单独本地提交，产品集成另行提交。

## 尚未覆盖

未连接用户报错的另一台电脑，不能宣称该电脑已修复；安装修复候选后仍需在原目录点击重试。未发布官网/GitHub，也未改正式 Relay。没有重新验证 Android、macOS/Linux、全新下载所有运行库或桌面权限 UAC；本次针对 Windows PM 复制故障。Hermes 真实回归早期曾因系统 Python 缺 ruamel 无法进入测试，随后改用官方 PM 构建的隔离环境通过，未用 mock 绕过。
