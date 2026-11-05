# 原生客户端：Bot 附件不再被直接执行（Windows）

## 问题

推送后的自动安全审查指出 `apps/native/windows/runner/file_actions.cpp`：文件预览的「打开」把 Bot 发来的附件复制到临时目录后，直接以 `ShellExecuteExW("open")` 打开。附件若是 `.exe`、`.bat`、`.lnk`、`.hta`、`.ps1` 等，点一下「打开」就会运行，而且临时副本没有「来自网络」标记，Windows 不会给出下载文件通常有的 SmartScreen / 受保护视图提示。代码来自此前的提交 `5fc78e8f14`。

## 处理

- 「打开」前用系统的 `AssocIsDangerous` 判断类型，并补充一份固定的可执行/脚本扩展名清单（`.bat .cmd .exe .hta .js .lnk .msi .ps1 .reg .scr .url .vbs …`，不区分大小写），命中即返回 `blocked_type`，不调用 `ShellExecuteExW`。
- 每个预览副本在任何操作（打开、打开方式、在文件夹中显示）之前写入 `Zone.Identifier`（`ZoneId=3`，即 Mark of the Web），之后无论从哪里打开都由 Windows 套用 SmartScreen、受保护视图与宏拦截；写入失败则拒绝操作，不在无保护的情况下继续。
- 「打开方式」（由人明确选择程序）和「在文件夹中显示」保持可用。
- 预览页对 `blocked_type` 显示中英文说明：程序和脚本不会直接打开，可以在文件夹中查看或用「打开方式」选择应用；其余平台错误显示原生消息，不再显示原始异常字符串。

## 验证

- `integration_test/file_actions_safety_test.dart` 在真实 Windows 运行器中调用产品的 `app.nekodot/files` 通道：6 种载荷（`.bat`、大写 `.CMD`、`.ps1`、`.vbs`、`.hta`、`.url`）全部返回 `blocked_type`，每个副本都带 `ZoneId=3`，且载荷若被执行会写入的标记文件始终不存在。
- 受影响 Dart 文件 `flutter analyze` 无问题；文件预览 widget 测试见提交记录。

## 未覆盖

- Android、macOS、Linux 使用 `url_launcher` 交给系统处理（Android 安装器、macOS 隔离属性/Gatekeeper 各自把关），本次未改动、未实测。
- 未接入 `IAttachmentExecute`（含杀毒扫描的完整附件策略）；当前以拒绝可执行类型 + Mark of the Web 覆盖主要风险。
