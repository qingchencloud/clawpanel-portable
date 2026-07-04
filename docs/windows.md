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
