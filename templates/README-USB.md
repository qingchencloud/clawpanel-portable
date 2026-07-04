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
- `runtimes/`：内置 uv、Python、Git 等运行时。
- `portable.json`：便携模式开关。

## 注意

- 不要只复制 exe 或 app，需要复制整个 `ClawPanelPortable` 目录。
- 不要把 API Key、模型配置、聊天记录提交到公开仓库。
- Windows 极简系统如果缺少 WebView2 Runtime，可能需要先安装系统组件。
