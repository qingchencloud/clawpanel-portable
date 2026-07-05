# macOS 便携包

macOS 支持目标：

- `macos-arm64`
- `macos-x64`

## 构建

```bash
./scripts/build-macos-full.sh \
  --clawpanel-app /path/to/ClawPanel.app \
  --arch arm64 \
  --output ./output
```

流程和 Windows 一致：下载 uv → 下载 OpenClaw standalone（tar.gz，`gh release download`）→
通过 `uv tool install` 装 Hermes Agent → 重写 `hermes`/`hermes-agent`/`hermes-acp` 三个
wrapper 为相对路径可执行脚本 → 打包 zip + sha256。

用 `--skip-hermes-build` 可以跳过 Hermes（uv tool install 会真实拉取
`NousResearch/hermes-agent` 仓库和一堆 Python 依赖，第一次验证目录结构/签名流程时
建议先跳过，跑得快）。

依赖（构建机需要预装）：`curl`、`tar`、`jq`、`shasum`、`zip`。`gh` 可选——OpenClaw
standalone 是公开仓库，`gh` 缺失或登录状态失效时会自动回退到公开 REST API + curl。

## 验收

```bash
./scripts/verify-macos.sh --portable-root ./output/macos-arm64/ClawPanelPortable
```

验收重点：

- `portable.json` 存在。
- `ClawPanel.app` 存在。
- `engines/openclaw/openclaw` 存在且可执行。
- `engines/hermes/bin/hermes` 存在且可执行。
- `runtimes/uv/bin/uv` 存在。
- 收窄 PATH（只留便携目录 + `/usr/bin:/bin`）后仍能跑 `openclaw`、`hermes`、`uv`、`git --version`。

## 已知缺口（发布前必须在真实 macOS 机器上确认）

### 1. Git 依赖系统自带，不随包分发

Windows 版会自动下载 MinGit 到 `runtimes/git`（`ensure_portable_git()`，
`src-tauri/src/commands/hermes.rs`）。**macOS 版没有做等价的自动下载**，这是刻意的决定，
不是遗漏：

- macOS 上没有官方维护的"MinGit"等价物——git-for-windows 项目专门发布了体积小、
  免安装的 MinGit 供第三方分发；macOS 上能找到的等价方案基本都是社区自行静态编译的
  第三方产物，供应链可信度不如"git-for-windows 官方 release"，在没有确认可信来源前
  不适合直接内嵌到发行包里。
- macOS 通常通过 Xcode Command Line Tools 自带 `git`（`/usr/bin/git`），大多数开发者
  机器上已经有。全新的消费级 Mac（没装过 CLT）第一次执行 `git` 会弹系统安装对话框，
  这个体验在便携模式首次启动时会比较突兀。
- **现状**：`hermes_enhanced_path()`（hermes.rs）已经把 `runtimes/git/bin` 加进了
  PATH 探测列表（只在目录存在时才生效），意味着如果以后要接入一个可信的便携 git
  来源，只需要把 git 二进制放到这个路径下，Rust 侧不需要再改代码。
- **对用户的要求**：便携包首次使用前建议先在终端跑一次 `git --version`
  （或 `xcode-select --install`），确认系统已具备可用的 git。`README-USB.md`
  和这里都需要写清楚这一条。

### 2. 签名 / 公证 / Gatekeeper

构建脚本产出的是**未签名、未公证**的 `.app`。没有 Apple Developer ID 证书和
notarization 凭据的情况下：

- 直接分发这个 zip，用户解压后双击会被 Gatekeeper 拦截（"无法打开，因为无法验证开发者"）。
- 临时绕过：`xattr -cr ClawPanelPortable/ClawPanel.app` 清除 quarantine 属性，
  或右键 → 打开，走"我已了解风险仍要打开"的路径。
- 正式对外发布前，需要：
  1. 用 Developer ID Application 证书对 `ClawPanel.app` 做 `codesign --deep --force --sign`；
  2. 用 `xcrun notarytool submit` 提交公证，`stapler staple` 回贴票据；
  3. 确认 hardened runtime + entitlements 配置正确（Tauri 项目本身的签名配置，
     不在这个仓库范围内，需要在 ClawPanel 主仓库的 Tauri 打包配置里做）。
  这一步需要真实的 Apple Developer 账号，本仓库目前没有相应凭据，留给有账号的人接手。

### 3. Python venv 路径可迁移性 —— 已在真机验证 ✅

`uv tool install` 生成的 venv 会在 `pyvenv.cfg` 里写入构建时的绝对路径。
`build-macos-full.sh` 用和 Windows 相同的技巧规避：删除 uv 自动生成的
`hermes`/`hermes-agent`/`hermes-acp` shim，改写成 shell wrapper，每次运行时
根据 `$0` 动态算出当前 `ROOT`，重新生成 `pyvenv.cfg` 后再执行
`hermes-agent/bin/python3`。

**2026-07-05 已在真实 Apple Silicon（M4，macOS 26.5）上跑通完整流程**：
`build-macos-full.sh`（含真实 `uv tool install` 从
`NousResearch/hermes-agent` 装 Hermes）成功产出便携包，`verify-macos.sh`
四项真实调用（uv/git/hermes/openclaw）全部通过。并且把整个
`ClawPanelPortable` 目录复制到完全不同的路径后重新验证依然全部通过——
证明 pyvenv.cfg 动态重写技巧确实是路径无关的。

验证过程中发现并修复了两个真实 bug（见 commit `554533c`）：
- glob→正则转换的 sed 表达式在 BSD sed（macOS）上转义行为和 GNU sed 不一致，
  转出的正则匹配不到任何资产；简化成只处理 `*`，规避 sed 方言差异。
- 内部辅助函数的进度提示写到了 stdout，污染了被 `$(...)` 捕获的返回值，
  导致传给 `tar` 的路径参数变成两行乱码；改为写 stderr。

### 4. 尚未做的事

- 验证用的是一台已经装过 Xcode Command Line Tools 的 Mac，**没有验证"全新
  Mac 没装过 CLT，第一次执行 git 弹系统安装对话框"这个首次体验**——缺口 1
  依然需要有全新 Mac（或干净虚拟机）时补验证。
- 签名/公证/Gatekeeper（缺口 2）仍未测试，需要 Apple Developer 凭据。
- CI（`.github/workflows/release-portable.yml`）目前只有 Windows job 会自动
  发布 Release；macOS job 已加（`workflow_dispatch` 手动 opt-in，产物只进
  workflow artifact），但没有接入自动发布，因为签名/公证凭据没有着落，
  直接发一个未签名 `.app` 到 Release 容易被当成"能用的正式包"，反而增加
  支持成本。等有 Apple Developer 凭据后再补。
- 没有做 arm64/x64 的 universal binary 合并，两个架构分别打包。
- x64（Intel Mac）架构还没有真机验证过，本次验证的是 arm64。
