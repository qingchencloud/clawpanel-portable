# ClawPanel U 盘版

这是 ClawPanel Portable Full 包。

## 使用方式

1. 把整个 `ClawPanelPortable` 目录复制到 U 盘。
2. Windows 双击 `ClawPanel.exe`。
3. macOS 双击 `ClawPanel.app`。
4. 首次启动后按面板提示修改默认访问密码。

## 目录说明

- `data/`：面板、OpenClaw、Hermes 和产物数据。
- `engines/`：内置 OpenClaw / Hermes。
- `runtimes/`：内置 uv、Python、（Windows 上还有）Git 等运行时。
- `portable.json`：便携模式开关。

## 注意

- 不要只复制 exe 或 app，需要复制整个 `ClawPanelPortable` 目录。
- 不要把 API Key、模型配置、聊天记录提交到公开仓库。
- Windows 极简系统如果缺少 WebView2 Runtime，可能需要先安装系统组件。
- **macOS**：Hermes 安装/更新依赖系统自带的 Git。如果这台 Mac 从没装过开发者工具，
  第一次用之前请在终端跑一次 `git --version`（或 `xcode-select --install`），
  避免首次使用时卡在系统弹出的安装对话框上。
- **macOS**：这个包目前未签名、未公证。双击打不开时，右键 `ClawPanel.app` →
  「打开」，在弹窗里确认「打开」即可；或者在终端执行
  `xattr -cr ClawPanelPortable/ClawPanel.app` 清除隔离属性。
