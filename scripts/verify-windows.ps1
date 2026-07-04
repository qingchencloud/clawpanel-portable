param(
  [Parameter(Mandatory = $true)]
  [string]$PortableRoot
)

$ErrorActionPreference = "Stop"

function Assert-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing file: $Path"
  }
}

function Assert-Dir {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Missing directory: $Path"
  }
}

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$File,
    [string[]]$Arguments = @()
  )
  $output = & $File @Arguments 2>&1
  $code = $LASTEXITCODE
  if ($code -ne 0) {
    throw "Command failed ($code): $File $($Arguments -join ' ')`n$($output -join "`n")"
  }
  return $output
}

$root = (Resolve-Path -LiteralPath $PortableRoot).Path
$openclawDir = Join-Path $root "engines\openclaw"
$hermesBin = Join-Path $root "engines\hermes\bin"
$uvBin = Join-Path $root "runtimes\uv\bin"
$gitCmd = Join-Path $root "runtimes\git\cmd"

Assert-File (Join-Path $root "portable.json")
Assert-File (Join-Path $root "ClawPanel.exe")
Assert-Dir (Join-Path $root "data")
Assert-Dir $openclawDir
Assert-Dir (Join-Path $root "engines\hermes")
Assert-File (Join-Path $uvBin "uv.exe")
Assert-File (Join-Path $gitCmd "git.exe")

$openclawCmd = Join-Path $openclawDir "openclaw.cmd"
if (-not (Test-Path -LiteralPath $openclawCmd -PathType Leaf)) {
  $openclawCmd = Join-Path $openclawDir "openclaw.exe"
}
Assert-File $openclawCmd

$hermesCmd = Join-Path $hermesBin "hermes.cmd"
if (-not (Test-Path -LiteralPath $hermesCmd -PathType Leaf)) {
  throw "Missing Hermes entrypoint: $hermesCmd"
}

$oldPath = $env:PATH
$oldPortableRoot = $env:CLAWPANEL_PORTABLE_ROOT
$oldHermesHome = $env:HERMES_HOME
$oldUvToolDir = $env:UV_TOOL_DIR
$oldUvToolBinDir = $env:UV_TOOL_BIN_DIR
$oldUvCacheDir = $env:UV_CACHE_DIR
$oldUvPythonInstallDir = $env:UV_PYTHON_INSTALL_DIR

try {
  $env:CLAWPANEL_PORTABLE_ROOT = $root
  $env:HERMES_HOME = Join-Path $root "data\hermes"
  $env:UV_TOOL_DIR = Join-Path $root "engines\hermes"
  $env:UV_TOOL_BIN_DIR = $hermesBin
  $env:UV_CACHE_DIR = Join-Path $root "runtimes\uv\cache"
  $env:UV_PYTHON_INSTALL_DIR = Join-Path $root "runtimes\uv\python"
  $env:PATH = "$hermesBin;$openclawDir;$uvBin;$gitCmd;$env:SystemRoot\System32;$env:SystemRoot"

  $uv = Invoke-Checked -File (Join-Path $uvBin "uv.exe") -Arguments @("--version")
  $git = Invoke-Checked -File (Join-Path $gitCmd "git.exe") -Arguments @("--version")
  $hermes = Invoke-Checked -File $hermesCmd -Arguments @("version")
  $openclaw = & $openclawCmd --version 2>$null
  if (-not $openclaw) {
    $openclaw = & $openclawCmd 2>$null
  }
  if ($LASTEXITCODE -ne 0) {
    throw "OpenClaw check failed: $openclawCmd"
  }

  [pscustomobject]@{
    ok = $true
    root = $root
    uv = ($uv -join "`n")
    git = ($git -join "`n")
    hermes = ($hermes -join "`n")
    openclaw = ($openclaw -join "`n")
  } | ConvertTo-Json -Depth 4
} finally {
  $env:PATH = $oldPath
  $env:CLAWPANEL_PORTABLE_ROOT = $oldPortableRoot
  $env:HERMES_HOME = $oldHermesHome
  $env:UV_TOOL_DIR = $oldUvToolDir
  $env:UV_TOOL_BIN_DIR = $oldUvToolBinDir
  $env:UV_CACHE_DIR = $oldUvCacheDir
  $env:UV_PYTHON_INSTALL_DIR = $oldUvPythonInstallDir
}
