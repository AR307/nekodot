# 0.3.1 正式发布记录

## 基线与范围

- 2026-11-04 用户授权发布0.3.1并push。候选代码从`1f48d3ad73`独立归档构建，补入文档格式修正和测试版本断言；产品行为未在验收后变更。
- 产品0.3.1+7；Android arm64 versionCode 2007，应用标识及签名与上版一致。Windows x64未做Authenticode签名。
- 没有纳入工作区未提交的历史截图、设计草稿或私有运行配置。

## 构建和运行

- 独立目录frozen install、ESLint/Prettier、TypeScript、38文件69项服务端测试、build通过；Flutter frozen pub、analyze、24项辅助测试通过。
- 初次lint发现五份既有文档/JSON格式问题，修正并复查；初次服务端测试发现版本断言写死0.3.0，改为引用产品版本并重跑通过。
- Windows release EXE、同签名Android arm64 APK、Relay Docker归档均本地构建。安装包元数据见`evidence/release-0.3.1-packages.json`。
- Windows实际运行0.3.1 release客户端，已有登录态和节点列表正常绘制。此次未替用户点击系统安装授权，也未重复Android真机验收。
- 本机安装/真实工具/桌面操作等发布内容的真实原生旅程见`local-desktop-acceptance.md`及对应证据；不是仅以本轮辅助测试宣称功能验收。

## 服务器与下载

- 正式Relay切换为`nekodot-relay:product-0.3.1`，health与公开版本接口返回0.3.1/build7。独立候选先验证复制数据库、SMTP认证、匿名拒绝和分发目录。
- 产品Node通过既有空闲更新机制切换到`20261104070530`，一次正常服务重启后上线；pending已解除，没有rejected标记。没有升级Hermes源码。
- 账号3、节点4、Bot2保留；发布前58条消息保留，专用QA验收后63条。Node身份配置不变；原数据、下载、官网和镜像保留在服务器本次release备份目录。
- 对照受保护容器ID、启动时间及重启次数，Caddy、QA Relay、getplus和其他产品未重启；没有重启整机。
- 公网HTTPS/WSS使用专用QA账号及gpt-6.1-sol完成真实流式回复；重复clientMsgId仅产生一次输入。原生Session和153条命令目录可读。
- 公网Webhook错误密钥401、正确请求202，真实模型结果回投；重复delivery只执行一次。验收任务已暂停，临时QA会话已注销。详见`evidence/release-0.3.1-live-model.json`。
- 官网和两端安装包实际下载返回200；版本化地址和官网固定下载地址内容一致。Relay归档入口返回200。见`evidence/release-0.3.1-downloads.json`。

## 边界

- 本轮未重做Android真机、macOS或完整Linux桌面安装。macOS不提供包；Linux不作为已验收正式平台发布。
- 独立候选首次端口与既有QA Relay冲突，原服务未受影响；改用空闲loopback端口4379，失败容器保留未删除。
- Windows候选界面由工具观察；用户正在操作窗口时停止额外UI检查，未将版本页面交互记为通过。
- GitHub源码、v0.3.1标签和正式Release按本次授权同步；MIT许可不变。
