# Gooey Nav 导航替换

用户指定 ReactBits Gooey Nav，并确认范围为 Web 与共用 React 的 Tauri 客户端。

- 使用 ReactBits 官方 DOM/CSS 粒子胶囊实现，来源固定为 `DavidHDev/react-bits@c83b5e7e026f003af33ff9ebc3d93afb5c86ad22` 的 `src/ts-default/Components/GooeyNav`，保留来源和许可证。
- 统一替换聊天/技能/插件主导航、Bot 详情/记忆/资料库标签、SOUL.md/MEMORY.md/USER.md 文档导航。
- 可复用组件由现有页面状态控制；保留中英文、图标、点击、Enter/Space，并支持方向键、Home/End。异步消息更新不重启动效。
- 沿用现有字体、橙色 accent 和明暗主题；选中项使用深色文字以保证对比度。窄屏等分、文档标签完整单行显示，触摸目标至少 44px。
- 装饰粒子不参与命中测试、朗读或布局；遵从减少动态效果，并在切换和卸载时清理。
- 不改 Flutter 路由、认证、Hermes、Node/Relay 协议、官网或一次性返回/设置按钮。
- 使用本次候选 Web 和本地真实 Relay/Node 做浏览器验收；模型能力如无法实测要单独披露，不以回放宣称通过。Tauri 设备验收单独记录。
