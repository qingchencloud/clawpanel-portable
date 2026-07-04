# macOS 便携包

macOS 支持目标：

- `macos-arm64`
- `macos-x64`

## 额外注意

macOS 比 Windows 多几个发布问题：

- `.app` 签名
- 公证
- quarantine 属性
- shell wrapper 可执行权限
- Python venv 路径可迁移性

## 构建入口

```bash
./scripts/build-macos-full.sh \
  --clawpanel-app /path/to/ClawPanel.app \
  --arch arm64 \
  --output ./output
```

首版 macOS 脚本用于固定目录结构和运行时布局，正式发布前必须在真实 macOS 机器上验收。
