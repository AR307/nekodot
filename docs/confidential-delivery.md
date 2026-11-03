# 聊天内保密交付

## 结构

- `packages/protocol/src/secrets.ts`：请求元数据、Bot 专属保存条目、密文信封与显式 RPC。消息只保存请求标识、接收 Bot、用途和状态。
- `apps/node/src/secret-crypto.ts`：X25519 / HKDF-SHA256 / AES-256-GCM；关联 Node、Bot、请求。各 Bot 私钥与静态加密密钥放在 Node 私有目录，数据库只保存已选择复用的密文。
- `apps/node/src/secrets.ts`：卡片生命周期、精确用途匹配、目标配置应用、原生技能请求响应及 vault 临时条目回收。明文不通过 Relay 返回。
- `apps/node/src/hermes/secrets-plugin.ts`：`hermes secret request/status/apply` 和工具结果脱敏。沿用 `routines.sock`，profile 自有 token 绑定引用访问；脚本按引用应用并读取已确认目标，不批量导出其他服务资料到 profile 全局环境。
- Flutter 原生卡片在聊天内填写；Bot 详情提供保密资料元数据管理入口。

## Hermes v0.22.5 的实际边界

原生 `secret` server request 会将已交付值写入所属 profile 的 `.env`，可选保存仅控制额外的可复用副本。请求超时和取消由 canonical WebSocket 原生事件关闭。

稳定版 vault 的原生填充只负责密码，账号名是原生可见元数据，canonical 也尚未绑定新的 vault 输入提示。插件的 `nekodot_secret_browser` 在原进程调用原生 vault、supervisor 和 lease 检查，补齐保密账号名及一次性验证码输入，不改 Hermes 核心、不实现浏览器驱动。客户端和模型仍只提交引用。

通用请求结束创建回合后等待用户；交付后使用固定 submission ID 向原会话排队一次继续指令，不制造用户气泡，也不接管原群聊接力。

## 保存与停用

默认不保存额外副本；用户授权的目标文件与网站登录状态可能持续存在。网站密码保留在所属 profile 的原生加密 vault；未保存的 vault 项目在使用回合结束后撤回。API / 私钥等配置仅写入卡片展示的准确目标。多行值不裁剪空格或换行。

保存匹配包括 Bot、服务、用途、字段和目标。更换用途、目标或接收 Bot 均不可直接复用。停用不撤销已经写入的目标配置或网站登录状态。

## 状态与恢复

原生请求收到响应只标记「已交付」；回合结束后读回所属 profile 的实际环境，确认写入才标记「已完成配置」。通用文件应用、vault 录入和浏览器登录是不同结果：vault 就绪不代表网站已登录，任务结果继续由真实 Hermes 回合展示。

管理页替换凭据只更新已确认目标和保存条目，不发送聊天继续指令。普通聊天交付使用固定原生 submission ID；双端重复提交不会生成第二次应用或虚假用户气泡。另一端取消或交付后，聊天和管理表单都会同步实际状态并清空输入。

Node 重启不重跑任务：未完成的临时值要求重新交付，已保存条目继续可用；原生等待请求遵循 Hermes 的取消/超时。配置失败展示真实原因；停用和取消均不会暗中撤销用户已确认写入的文件。

## 验收与候选包

2026-11-03：Windows 原生候选和固定 Android 模拟器、隔离真实 Node/Relay、官方 Hermes v0.22.5、真实 gpt-6.1-sol 已完成 API 配置及实际调用、多行私钥、原生技能密钥、网站登录、保存复用、OTP、跨 Bot/账号拒绝、重复提交、Node 重启和管理操作。Android 真机与完整视觉/恢复组合仍待验，不将模拟器或单元测试作为真机结果。

详细旅程、截图、工程检查和限制见 [真实验收记录](confidential-delivery-acceptance.md)。本轮只提供本地候选包及 commit，没有发布或部署正式环境，没有修改 Hermes 核心。
