#!/usr/bin/env bash
set -euo pipefail

ARCH="arm64"
CLAWPANEL_APP=""
OUTPUT_DIR="./output"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCH="$2"
      shift 2
      ;;
    --clawpanel-app)
      CLAWPANEL_APP="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$CLAWPANEL_APP" ]]; then
  echo "Pass --clawpanel-app /path/to/ClawPanel.app" >&2
  exit 2
fi
if [[ "$ARCH" != "arm64" && "$ARCH" != "x64" ]]; then
  echo "Unsupported arch: $ARCH" >&2
  exit 2
fi

MANIFEST="$ROOT_DIR/manifests/macos-${ARCH}.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing manifest: $MANIFEST" >&2
  exit 1
fi

PLATFORM="macos-${ARCH}"
STAGE="$OUTPUT_DIR/$PLATFORM/ClawPanelPortable"
WORK="$OUTPUT_DIR/work/$PLATFORM"
rm -rf "$STAGE" "$WORK"
mkdir -p \
  "$STAGE/data/clawpanel" \
  "$STAGE/data/openclaw" \
  "$STAGE/data/hermes" \
  "$STAGE/data/media" \
  "$STAGE/engines/openclaw" \
  "$STAGE/engines/hermes/bin" \
  "$STAGE/runtimes/uv/bin" \
  "$WORK"

cp "$ROOT_DIR/templates/portable.json" "$STAGE/portable.json"
cp "$ROOT_DIR/templates/README-USB.md" "$STAGE/README-USB.md"
cp -R "$CLAWPANEL_APP" "$STAGE/ClawPanel.app"

cat > "$STAGE/data/clawpanel/clawpanel.json" <<'JSON'
{ "accessPassword": "123456", "engine": "openclaw" }
JSON
cat > "$STAGE/data/openclaw/openclaw.json" <<'JSON'
{ "gateway": { "host": "127.0.0.1", "port": 18789 }, "agents": { "main": { "name": "main" } } }
JSON
cat > "$STAGE/data/hermes/config.yaml" <<'YAML'
# Hermes config is managed by ClawPanel.
YAML

echo "macOS portable staging created: $STAGE"
echo "TODO: download OpenClaw standalone, uv, build Hermes, rewrite relative launchers, sign and notarize."
