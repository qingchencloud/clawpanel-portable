#!/usr/bin/env bash
set -euo pipefail

PORTABLE_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --portable-root)
      PORTABLE_ROOT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$PORTABLE_ROOT" ]]; then
  echo "Pass --portable-root /path/to/ClawPanelPortable" >&2
  exit 2
fi
if [[ ! -d "$PORTABLE_ROOT" ]]; then
  echo "Portable root not found: $PORTABLE_ROOT" >&2
  exit 1
fi

ROOT="$(cd "$PORTABLE_ROOT" && pwd)"
OPENCLAW_DIR="$ROOT/engines/openclaw"
HERMES_BIN="$ROOT/engines/hermes/bin"
UV_BIN_DIR="$ROOT/runtimes/uv/bin"

assert_file() {
  [[ -f "$1" ]] || { echo "Missing file: $1" >&2; exit 1; }
}
assert_dir() {
  [[ -d "$1" ]] || { echo "Missing directory: $1" >&2; exit 1; }
}

assert_file "$ROOT/portable.json"
assert_dir "$ROOT/ClawPanel.app"
assert_dir "$ROOT/data"
assert_dir "$OPENCLAW_DIR"
assert_dir "$ROOT/engines/hermes"
assert_file "$UV_BIN_DIR/uv"

openclaw_bin="$OPENCLAW_DIR/openclaw"
assert_file "$openclaw_bin"

hermes_bin="$HERMES_BIN/hermes"
if [[ ! -f "$hermes_bin" ]]; then
  echo "Missing Hermes entrypoint: $hermes_bin" >&2
  exit 1
fi

export CLAWPANEL_PORTABLE_ROOT="$ROOT"
export HERMES_HOME="$ROOT/data/hermes"
export UV_TOOL_DIR="$ROOT/engines/hermes"
export UV_TOOL_BIN_DIR="$HERMES_BIN"
export UV_CACHE_DIR="$ROOT/runtimes/uv/cache"
export UV_PYTHON_INSTALL_DIR="$ROOT/runtimes/uv/python"
# Deliberately narrow PATH: this must succeed without relying on Homebrew,
# pyenv, or any other host-installed tool. System git (Xcode CLT) is the one
# accepted host dependency — see docs/macos.md "Known gaps".
export PATH="$HERMES_BIN:$OPENCLAW_DIR:$UV_BIN_DIR:/usr/bin:/bin"

uv_version="$("$UV_BIN_DIR/uv" --version)"
git_version="$(git --version 2>&1)" || {
  echo "System git not found. Install Xcode Command Line Tools (xcode-select --install)" >&2
  echo "or wait for portable git bundling (tracked in docs/macos.md)." >&2
  exit 1
}
hermes_version="$("$hermes_bin" version 2>&1)"
openclaw_version="$("$openclaw_bin" --version 2>&1 || "$openclaw_bin" 2>&1 || true)"

cat <<JSON
{
  "ok": true,
  "root": "$ROOT",
  "uv": "$uv_version",
  "git": "$git_version",
  "hermes": "$hermes_version",
  "openclaw": "$openclaw_version"
}
JSON
