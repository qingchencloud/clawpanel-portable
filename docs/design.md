# 设计说明

## 目标

ClawPanel Portable Full 解决的是“用户不想安装 Node、Python、Git、uv，也不想在第一次启动时等待大量下载”的问题。

便携包应满足：

- 解压或写入 U 盘后即可启动。
- 默认不写宿主机 PATH、Home、全局 npm、全局 pip。
- OpenClaw、Hermes、uv、Python、Git 均位于便携根目录内。
- 数据、配置、媒体产物默认写入 `data/`。

## 仓库边界

主仓库 `qingchencloud/clawpanel`：

- 面板功能
- 便携模式运行时识别
- OpenClaw / Hermes 启停
- 配置迁移

本仓库 `qingchencloud/clawpanel-portable`：

- 版本 manifest
- 便携完整包构建
- U 盘写入
- 发布验收

## 不把大文件提交到 git

runtime 和 engine 都是发布产物，不是源码。它们应放在 GitHub Release 或对象存储中。

## Windows 优先

Windows 是第一优先级：

- `ClawPanel.exe`
- OpenClaw standalone
- uv
- MinGit
- uv-managed Python
- Hermes Agent

macOS 后续补齐签名、公证、quarantine、可执行权限和 app bundle 细节。
