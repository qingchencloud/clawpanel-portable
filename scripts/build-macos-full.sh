#!/usr/bin/env bash
set -euo pipefail

ARCH="arm64"
CLAWPANEL_APP=""
OUTPUT_DIR="./output"
SKIP_HERMES_BUILD="false"
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
    --skip-hermes-build)
      SKIP_HERMES_BUILD="true"
      shift
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
if [[ ! -d "$CLAWPANEL_APP" ]]; then
  echo "ClawPanel.app not found: $CLAWPANEL_APP" >&2
  exit 1
fi

for cmd in curl tar jq shasum zip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
done
# gh is optional: preferred (handles auth + convenient glob patterns), but the
# OpenClaw standalone repo is public, so a missing/unauthenticated gh falls
# back to the public REST API further down (download_github_asset).
HAVE_GH="false"
if command -v gh >/dev/null 2>&1; then
  HAVE_GH="true"
fi

MANIFEST="$ROOT_DIR/manifests/macos-${ARCH}.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing manifest: $MANIFEST" >&2
  exit 1
fi

manifest_get() {
  jq -r "$1" "$MANIFEST"
}

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
rm -rf "$STAGE/ClawPanel.app"
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

download_file() {
  local url="$1" out="$2"
  # Must go to stderr: download_github_asset() is invoked via command
  # substitution ($(...)), so anything this prints to stdout would get
  # concatenated onto its returned path (silently corrupting the caller's
  # "$openclaw_archive" etc. into a multi-line string — this bit us during
  # real-machine testing: tar received a two-line filename argument).
  echo "Downloading: $url" >&2
  curl -fsSL --retry 3 -A "ClawPanelPortableBuilder" -o "$out" "$url"
}

# Downloads a single GitHub release asset matching a glob pattern, mirroring
# Download-GitHubAsset in build-windows-full.ps1 so both platforms share the
# same manifest-driven asset resolution.
#
# Prefers `gh release download` (handles private repos, real glob matching).
# Falls back to the public REST API + curl when gh is missing or its stored
# credentials are broken/expired — OpenClaw standalone is a public repo, so
# asset listing and download work fine unauthenticated (subject to GitHub's
# lower unauthenticated rate limit, ~60 req/hour/IP).
download_github_asset() {
  local repo="$1" tag="$2" pattern="$3" dest="$4"
  mkdir -p "$dest"
  if [[ "$HAVE_GH" == "true" ]] && gh release download "$tag" --repo "$repo" --pattern "$pattern" --dir "$dest" --clobber 2>/dev/null; then
    local match
    match="$(find "$dest" -maxdepth 1 -type f | head -1)"
    if [[ -n "$match" ]]; then
      echo "$match"
      return 0
    fi
  fi
  echo "gh unavailable/failed, falling back to public GitHub API for $repo@$tag..." >&2
  local regex asset_url filename
  # Only translate the glob's "*"; asset names in practice don't contain other
  # regex metacharacters that would cause a false match, and BSD sed (macOS)
  # vs GNU sed disagree on `\&`-in-bracket-class escaping enough that a
  # "proper" glob->regex escaper isn't worth the portability risk here.
  regex="$(printf '%s' "$pattern" | sed 's/\*/.*/g')"
  asset_url="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${tag}" \
    | jq -r --arg re "$regex" '.assets[] | select(.name | test($re)) | .browser_download_url' \
    | head -1)"
  if [[ -z "$asset_url" ]]; then
    echo "No GitHub release asset matched via API fallback: $repo $tag $pattern" >&2
    exit 1
  fi
  filename="$(basename "$asset_url")"
  download_file "$asset_url" "$dest/$filename"
  echo "$dest/$filename"
}

# uv ships each platform archive with a single top-level dir (uv-<target>/uv);
# search recursively instead of assuming the nesting depth.
extract_and_find() {
  local archive="$1" dest="$2" binary_name="$3"
  rm -rf "$dest"
  mkdir -p "$dest"
  tar -xf "$archive" -C "$dest"
  find "$dest" -name "$binary_name" -type f | head -1
}

echo "Installing uv $(manifest_get '.uv.version')..."
uv_archive="$WORK/uv.tar.gz"
download_file "$(manifest_get '.uv.url')" "$uv_archive"
uv_extract="$WORK/uv"
uv_bin_found="$(extract_and_find "$uv_archive" "$uv_extract" "uv")"
if [[ -z "$uv_bin_found" ]]; then
  echo "uv binary not found in uv archive." >&2
  exit 1
fi
cp "$uv_bin_found" "$STAGE/runtimes/uv/bin/uv"
chmod +x "$STAGE/runtimes/uv/bin/uv"
UV_BIN="$STAGE/runtimes/uv/bin/uv"

echo "Installing OpenClaw standalone $(manifest_get '.openclaw.version')..."
openclaw_archive="$(download_github_asset \
  "$(manifest_get '.openclaw.standaloneRepository')" \
  "$(manifest_get '.openclaw.standaloneTag')" \
  "$(manifest_get '.openclaw.assetPattern')" \
  "$WORK/openclaw")"
openclaw_extract="$WORK/openclaw-extract"
rm -rf "$openclaw_extract"
mkdir -p "$openclaw_extract"
tar -xzf "$openclaw_archive" -C "$openclaw_extract"
openclaw_src="$openclaw_extract"
# Release archives nest everything under a single "openclaw/" directory
# (verified against the real mac-arm64/x64 assets); fall back to the
# extract root if a future release ever flattens it.
if [[ -f "$openclaw_extract/openclaw/openclaw" ]]; then
  openclaw_src="$openclaw_extract/openclaw"
fi
cp -R "$openclaw_src/." "$STAGE/engines/openclaw/"
chmod +x "$STAGE/engines/openclaw/openclaw" 2>/dev/null || true
chmod +x "$STAGE/engines/openclaw/node" 2>/dev/null || true
# Quarantine attribute blocks execution of binaries copied outside Finder/curl;
# Gatekeeper re-flags them on first USB copy, so strip it up front.
xattr -cr "$STAGE/engines/openclaw" 2>/dev/null || true

write_hermes_wrapper() {
  local path="$1" import_path="$2" function_name="$3" uv_version="$4" python_version_info="$5"
  cat > "$path" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/../../.." && pwd)"
export HERMES_HOME="\$ROOT/data/hermes"
export UV_TOOL_DIR="\$ROOT/engines/hermes"
export UV_TOOL_BIN_DIR="\$ROOT/engines/hermes/bin"
export UV_CACHE_DIR="\$ROOT/runtimes/uv/cache"
export UV_PYTHON_INSTALL_DIR="\$ROOT/runtimes/uv/python"
export PATH="\$ROOT/engines/hermes/bin:\$ROOT/runtimes/uv/bin:\$PATH"

python_home=""
for d in "\$ROOT"/runtimes/uv/python/cpython-*/bin; do
  [[ -d "\$d" ]] && python_home="\$d"
done
if [[ -z "\$python_home" ]]; then
  echo "Portable Python runtime not found." >&2
  exit 1
fi

cat > "\$ROOT/engines/hermes/hermes-agent/pyvenv.cfg" <<CFG
home = \$python_home
implementation = CPython
uv = ${uv_version}
version_info = ${python_version_info}
include-system-site-packages = false
CFG

exec "\$ROOT/engines/hermes/hermes-agent/bin/python3" -c "from ${import_path} import ${function_name}; raise SystemExit(${function_name}())" "\$@"
WRAPPER
  chmod +x "$path"
}

install_hermes() {
  echo "Installing Hermes Agent $(manifest_get '.hermes.version') ($(manifest_get '.hermes.tag'))..."
  local hermes_tool_dir="$STAGE/engines/hermes"
  local hermes_bin="$hermes_tool_dir/bin"
  local python_dir="$STAGE/runtimes/uv/python"
  local uv_cache="$STAGE/runtimes/uv/cache"
  local hermes_home="$STAGE/data/hermes"
  mkdir -p "$hermes_bin" "$python_dir" "$uv_cache" "$hermes_home"

  local extras=""
  local extra_count
  extra_count="$(manifest_get '.hermes.extras | length')"
  if [[ "$extra_count" -gt 0 ]]; then
    extras="[$(manifest_get '.hermes.extras | join(",")')]"
  fi
  local repo_url tag python_ver pkg
  repo_url="$(manifest_get '.hermes.repositoryUrl')"
  tag="$(manifest_get '.hermes.tag')"
  python_ver="$(manifest_get '.hermes.python')"
  pkg="hermes-agent${extras} @ git+${repo_url}@${tag}"

  (
    export HERMES_HOME="$hermes_home"
    export UV_TOOL_DIR="$hermes_tool_dir"
    export UV_TOOL_BIN_DIR="$hermes_bin"
    export UV_CACHE_DIR="$uv_cache"
    export UV_PYTHON_INSTALL_DIR="$python_dir"
    export UV_LINK_MODE="copy"
    "$UV_BIN" tool install --force "$pkg" --python "$python_ver"
  )

  # uv's own generated shims embed the build-time absolute path; we replace
  # them with the relative wrappers below (same technique as Windows .cmd).
  rm -f "$hermes_bin/hermes" "$hermes_bin/hermes-agent" "$hermes_bin/hermes-acp"

  local pyvenv="$hermes_tool_dir/hermes-agent/pyvenv.cfg"
  local version_info="3.11"
  if [[ -f "$pyvenv" ]]; then
    version_info="$(grep -E '^[[:space:]]*version_info[[:space:]]*=' "$pyvenv" | head -1 | sed -E 's/^[^=]+=[[:space:]]*//' | tr -d '\r')"
    [[ -z "$version_info" ]] && version_info="3.11"
  fi
  local uv_version
  uv_version="$(manifest_get '.uv.version')"

  write_hermes_wrapper "$hermes_bin/hermes" "hermes_cli.main" "main" "$uv_version" "$version_info"
  write_hermes_wrapper "$hermes_bin/hermes-agent" "run_agent" "main" "$uv_version" "$version_info"
  write_hermes_wrapper "$hermes_bin/hermes-acp" "acp_adapter.entry" "main" "$uv_version" "$version_info"
  xattr -cr "$hermes_tool_dir" 2>/dev/null || true
}

if [[ "$SKIP_HERMES_BUILD" != "true" ]]; then
  install_hermes
fi

verify_script="$ROOT_DIR/scripts/verify-macos.sh"
if [[ -f "$verify_script" ]]; then
  bash "$verify_script" --portable-root "$STAGE"
fi

bundle_name="$(manifest_get '.bundleName')"
panel_version="$(manifest_get '.clawpanel.version')"
archive="$OUTPUT_DIR/${bundle_name}-v${panel_version}.zip"
archive_abs="$(cd "$OUTPUT_DIR" && pwd)/$(basename "$archive")"
rm -f "$archive_abs"
echo "Creating zip: $archive_abs"
(cd "$OUTPUT_DIR/$PLATFORM" && zip -r -y -q "$archive_abs" "ClawPanelPortable")
shasum -a 256 "$archive_abs" | awk -v path="$archive_abs" '{ printf "{\n  \"Algorithm\": \"SHA256\",\n  \"Hash\": \"%s\",\n  \"Path\": \"%s\"\n}\n", toupper($1), path }' > "$archive_abs.sha256.json"

echo "Portable bundle: $archive_abs"
echo "NOTE: this bundle is unsigned/unnotarized. Gatekeeper will block first launch"
echo "until you codesign + notarize ClawPanel.app, or the end user right-clicks"
echo "> Open on first run. See docs/macos.md for the signing checklist."
