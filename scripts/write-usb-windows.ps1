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
  if (Get-Command tar -ErrorAction SilentlyContinue) {
    & tar -xf $archivePath -C $temp
    if ($LASTEXITCODE -ne 0) {
      throw "Archive extraction failed: $archivePath"
    }
  } else {
    Expand-Archive -LiteralPath $archivePath -DestinationPath $temp -Force
  }
  $inner = Join-Path $temp "ClawPanelPortable"
  if (-not (Test-Path -LiteralPath $inner -PathType Container)) {
    $dirs = Get-ChildItem -LiteralPath $temp -Directory
    if ($dirs.Count -eq 1) {
      $inner = $dirs[0].FullName
    } else {
      throw "Archive does not contain a single portable root directory."
    }
  }

  New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null
  if (Get-Command robocopy -ErrorAction SilentlyContinue) {
    & robocopy $inner $TargetRoot /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) {
      throw "robocopy failed with exit code $LASTEXITCODE"
    }
  } else {
    Copy-Item -LiteralPath (Join-Path $inner "*") -Destination $TargetRoot -Recurse -Force
  }
  & (Join-Path $PSScriptRoot "verify-windows.ps1") -PortableRoot $TargetRoot
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
