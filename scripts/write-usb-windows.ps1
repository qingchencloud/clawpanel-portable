param(
  [Parameter(Mandatory = $true)]
  [string]$Archive,

  [string]$DriveLetter = "",
  [string]$TargetRoot = "",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
  if ([string]::IsNullOrWhiteSpace($DriveLetter)) {
    throw "Pass -DriveLetter or -TargetRoot."
  }
  $letter = $DriveLetter.Replace(':', '').ToUpperInvariant()
  $TargetRoot = $letter + ":\ClawPanelPortable"
}

$archivePath = (Resolve-Path -LiteralPath $Archive).Path
$parent = Split-Path -Parent $TargetRoot
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
  throw "Target drive or parent directory does not exist: $parent"
}

if (Test-Path -LiteralPath $TargetRoot) {
  if (-not $Force) {
    throw "Target already exists: $TargetRoot. Pass -Force to replace it."
  }
  Remove-Item -LiteralPath $TargetRoot -Recurse -Force
}

$temp = Join-Path $env:TEMP ("clawpanel-portable-write-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp | Out-Null

try {
  Expand-Archive -LiteralPath $archivePath -DestinationPath $temp -Force
  $inner = Join-Path $temp "ClawPanelPortable"
  if (-not (Test-Path -LiteralPath $inner -PathType Container)) {
    $dirs = Get-ChildItem -LiteralPath $temp -Directory
    if ($dirs.Count -eq 1) {
      $inner = $dirs[0].FullName
    } else {
      throw "Archive does not contain a single portable root directory."
    }
  }

  Copy-Item -LiteralPath $inner -Destination $TargetRoot -Recurse
  & (Join-Path $PSScriptRoot "verify-windows.ps1") -PortableRoot $TargetRoot
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
