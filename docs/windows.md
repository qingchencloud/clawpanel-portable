# Windows 便携包

## 构建

```powershell
.\scripts\build-windows-full.ps1 `
  -ClawPanelRepo D:\Data\PC\ClawPanel `
  -OutputDir .\output
```

## 验收

```powershell
.\scripts\verify-windows.ps1 -PortableRoot .\output\windows-x64\ClawPanelPortable
```

验收重点：

- `portable.json` 存在。
- `ClawPanel.exe` 存在。
- `engines/openclaw` 存在。
- `engines/hermes` 存在。
- `runtimes/uv/bin/uv.exe` 存在。
- `runtimes/git/cmd/git.exe` 存在。
- 收窄 PATH 后仍可运行 `openclaw`、`hermes`、`uv`、`git`。

## 写入 U 盘

```powershell
.\scripts\write-usb-windows.ps1 `
  -Archive .\output\ClawPanelPortable-Windows-x64-full-v0.18.5.zip `
  -DriveLetter E
```

脚本不会格式化 U 盘，只负责解压和校验。

## 自动发版

推送 `v*-portable.*` tag 后，GitHub Actions 会构建 Windows x64 完整包并创建 Release。

## 验证记录

2026-07-05 本地全量构建（含 Hermes `uv tool install`）跑通一次，`verify-windows.ps1`
四项检查全部通过真实调用（不只是文件存在性检查）：

```json
{
  "ok": true,
  "uv": "uv 0.7.12 (dc3fd4647 2025-06-06)",
  "git": "git version 2.55.0.windows.2",
  "hermes": "Hermes Agent v0.18.0 (2026.7.1) ... Python: 3.11.13 ... Up to date",
  "openclaw": "OpenClaw 2026.6.1-zh.1 (2e08f0f)"
}
```

产物 `ClawPanelPortable-Windows-x64-full-v0.18.5.zip`（约 1.08GB）+ sha256 校验文件。
