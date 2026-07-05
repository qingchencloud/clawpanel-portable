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

## Windows / macOS 现状

Windows 和 macOS 用同一套思路，两个平台的构建脚本（`build-windows-full.ps1` /
`build-macos-full.sh`）结构基本对称：

- `ClawPanel.exe` / `ClawPanel.app`
- OpenClaw standalone（对应平台的 release 包）
- uv
- uv-managed Python
- Hermes Agent（`uv tool install` + 相对路径 wrapper，见下）
- Git：Windows 自动下载 MinGit 到 `runtimes/git`；macOS 依赖系统自带 git
  （见 `docs/macos.md` 已知缺口 1），这是刻意的取舍，不是遗漏

Windows 版已经在真实环境跑通过一次完整构建（含 Hermes 的 `uv tool install`
从 `NousResearch/hermes-agent` 拉取真实依赖），`verify-windows.ps1` 四项检查
（uv/git/hermes/openclaw）全部通过真实调用验证。macOS 版脚本结构已对齐，
但还没有在真实 Mac 上跑过——发布前必须补这一步，详见 `docs/macos.md`。

## Hermes 便携化的核心技巧

`uv tool install` 生成的入口脚本（Windows 上的 `.exe` shim、POSIX 上的
shebang 脚本）会把构建时的绝对路径烤进去，U 盘换机器/换盘符就会失效。
两个平台的构建脚本都用同一个技巧规避：

1. 用 `uv tool install --force "hermes-agent[web] @ git+<repo>@<tag>" --python 3.11`
   安装到便携目录（`UV_TOOL_DIR`/`UV_TOOL_BIN_DIR`/`UV_CACHE_DIR`/
   `UV_PYTHON_INSTALL_DIR` 全部指向便携根目录下的子目录）。
2. 删除 uv 自动生成的 `hermes` / `hermes-agent` / `hermes-acp` 入口脚本。
3. 改写成一个自定义 wrapper（Windows `.cmd` / POSIX shell），每次运行时
   根据自身路径（`%~dp0` / `$BASH_SOURCE`）动态算出当前的便携根目录，
   重新生成 venv 的 `pyvenv.cfg`（指向当前路径下的 Python 运行时），
   再用 `-c "from <module> import <func>; raise SystemExit(<func>())"`
   直接调用对应的入口函数（对应 `pyproject.toml` 里 `[project.scripts]`
   的三个入口：`hermes_cli.main:main`、`run_agent:main`、
   `acp_adapter.entry:main`）。

这样即使 U 盘换了盘符/挂载路径，wrapper 每次启动都会用当前实际路径重新
生成 `pyvenv.cfg`，不依赖构建时烤死的绝对路径。
