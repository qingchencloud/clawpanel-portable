# ClawPanel Portable

ClawPanel Portable 是 ClawPanel 的 U 盘完整包集成仓库。

这个仓库不直接提交大体积运行时文件，而是保存：

- 稳定版 manifest
- Windows / macOS 便携包构建脚本
- U 盘写入和验收脚本
- 用户说明文档

最终面向用户发布的是 GitHub Release 里的完整包：

```text
ClawPanelPortable-Windows-x64-full-v0.18.5.zip
ClawPanelPortable-macOS-arm64-full-v0.18.5.zip
ClawPanelPortable-macOS-x64-full-v0.18.5.zip
```

## 当前稳定基准

| 组件 | 版本 |
|---|---|
| ClawPanel | `0.18.5` |
| OpenClaw zh | `2026.6.11-zh.1` |
| Hermes Agent | `0.18.0` / `v2026.7.1` |
| uv | `0.7.12` |

## 便携包目录

```text
ClawPanelPortable/
  portable.json
  README-USB.md
  ClawPanel.exe
  ClawPanel.app/

  data/
    clawpanel/
    openclaw/
    hermes/
    media/

  engines/
    openclaw/
    hermes/

  runtimes/
    uv/
    python/
    git/
```

## Windows 构建

先在 ClawPanel 主仓库构建出桌面程序，或把主仓库路径交给脚本自动构建：

```powershell
.\scripts\build-windows-full.ps1 `
  -ClawPanelRepo D:\Data\PC\ClawPanel `
  -OutputDir .\output
```

如果已经有 `clawpanel.exe`：

```powershell
.\scripts\build-windows-full.ps1 `
  -ClawPanelExe D:\Data\PC\ClawPanel\src-tauri\target\release\clawpanel.exe `
  -OutputDir .\output
```

验收：

```powershell
.\scripts\verify-windows.ps1 -PortableRoot .\output\windows-x64\ClawPanelPortable
```

写入 U 盘：

```powershell
.\scripts\write-usb-windows.ps1 `
  -Archive .\output\ClawPanelPortable-Windows-x64-full-v0.18.5.zip `
  -DriveLetter E
```

## macOS 构建

macOS 便携包需要额外处理 `.app` 签名、公证、quarantine 和可执行权限。首版脚本入口已经预留：

```bash
./scripts/build-macos-full.sh \
  --clawpanel-app /path/to/ClawPanel.app \
  --arch arm64 \
  --output ./output
```

## 维护原则

- 仓库只放脚本、manifest 和文档。
- runtime、engine、完整 zip 只放 Release 或对象存储。
- 稳定版以 `manifests/*.json` 为准。
- 普通 ClawPanel 仓库继续负责面板功能；本仓库只负责 U 盘完整包产品化交付。
