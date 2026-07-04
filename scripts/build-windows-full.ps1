param(
  [string]$ManifestPath = "",
  [string]$ClawPanelRepo = "",
  [string]$ClawPanelExe = "",
  [string]$OutputDir = "",
  [switch]$SkipHermesBuild
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
  $ManifestPath = Join-Path $PSScriptRoot "..\manifests\windows-x64.json"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $PSScriptRoot "..\output"
}

function Read-JsonFile {
  param([string]$Path)
  Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

function Download-File {
  param([string]$Url, [string]$OutFile)
  Invoke-WebRequest -Uri $Url -OutFile $OutFile -Headers @{ "User-Agent" = "ClawPanelPortableBuilder" }
}

function Download-GitHubAsset {
  param([string]$Repo, [string]$Tag, [string]$Pattern, [string]$Destination)
  Require-Command gh
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  gh release download $Tag --repo $Repo --pattern $Pattern --dir $Destination --clobber
  if ($LASTEXITCODE -ne 0) {
    throw "gh release download failed: $Repo $Tag $Pattern"
  }
  $files = Get-ChildItem -LiteralPath $Destination -File
  if ($files.Count -lt 1) {
    throw "No GitHub release asset matched: $Repo $Tag $Pattern"
  }
  if ($files.Count -gt 1) {
    return ($files | Sort-Object Length -Descending | Select-Object -First 1).FullName
  }
  return $files[0].FullName
}

function Expand-Zip {
  param([string]$ZipPath, [string]$Destination)
  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -LiteralPath $Destination -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
}

function Copy-DirectoryContents {
  param([string]$Source, [string]$Destination)
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
  }
}

function Resolve-ClawPanelExe {
  param([string]$Repo, [string]$Exe)
  if (-not [string]::IsNullOrWhiteSpace($Exe)) {
    return (Resolve-Path -LiteralPath $Exe).Path
  }
  if ([string]::IsNullOrWhiteSpace($Repo)) {
    throw "Pass -ClawPanelExe or -ClawPanelRepo."
  }
  $repoPath = (Resolve-Path -LiteralPath $Repo).Path
  Push-Location $repoPath
  try {
    npm ci
    npm run tauri build
  } finally {
    Pop-Location
  }
  $candidate = Join-Path $repoPath "src-tauri\target\release\clawpanel.exe"
  if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
    throw "ClawPanel exe not found after build: $candidate"
  }
  return $candidate
}

function Install-Uv {
  param($Manifest, [string]$WorkDir, [string]$UvBin)
  $zip = Join-Path $WorkDir "uv.zip"
  Download-File -Url $Manifest.uv.url -OutFile $zip
  $extract = Join-Path $WorkDir "uv"
  Expand-Zip -ZipPath $zip -Destination $extract
  $uvExe = Get-ChildItem -LiteralPath $extract -Recurse -Filter "uv.exe" | Select-Object -First 1
  if (-not $uvExe) {
    throw "uv.exe not found in uv archive."
  }
  New-Item -ItemType Directory -Force -Path $UvBin | Out-Null
  Copy-Item -LiteralPath $uvExe.FullName -Destination (Join-Path $UvBin "uv.exe") -Force
}

function Install-MinGit {
  param($Manifest, [string]$WorkDir, [string]$GitRoot)
  $release = Invoke-RestMethod -Uri $Manifest.git.apiUrl -Headers @{ "User-Agent" = "ClawPanelPortableBuilder" }
  $asset = $release.assets |
    Where-Object {
      $_.name -like $Manifest.git.assetPattern -and
      $_.name -notlike $Manifest.git.excludePattern
    } |
    Select-Object -First 1
  if (-not $asset) {
    throw "MinGit asset not found in latest Git for Windows release."
  }
  $zip = Join-Path $WorkDir $asset.name
  Download-File -Url $asset.browser_download_url -OutFile $zip
  Expand-Zip -ZipPath $zip -Destination $GitRoot
  $gitExe = Join-Path $GitRoot "cmd\git.exe"
  if (-not (Test-Path -LiteralPath $gitExe -PathType Leaf)) {
    throw "git.exe not found after MinGit extraction: $gitExe"
  }
}

function Install-OpenClaw {
  param($Manifest, [string]$WorkDir, [string]$OpenClawDir)
  $asset = Download-GitHubAsset `
    -Repo $Manifest.openclaw.standaloneRepository `
    -Tag $Manifest.openclaw.standaloneTag `
    -Pattern $Manifest.openclaw.assetPattern `
    -Destination (Join-Path $WorkDir "openclaw")
  $extract = Join-Path $WorkDir "openclaw-extract"
  Expand-Zip -ZipPath $asset -Destination $extract

  $candidate = $extract
  $children = Get-ChildItem -LiteralPath $extract -Directory
  if ($children.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $children[0].FullName "openclaw.cmd"))) {
    $candidate = $children[0].FullName
  }
  Copy-DirectoryContents -Source $candidate -Destination $OpenClawDir
}

function Install-Hermes {
  param($Manifest, [string]$Root, [string]$UvBin, [string]$GitCmd)
  $uvExe = Join-Path $UvBin "uv.exe"
  $hermesToolDir = Join-Path $Root "engines\hermes"
  $hermesBin = Join-Path $hermesToolDir "bin"
  $pythonDir = Join-Path $Root "runtimes\uv\python"
  $uvCache = Join-Path $Root "runtimes\uv\cache"
  $hermesHome = Join-Path $Root "data\hermes"

  New-Item -ItemType Directory -Force -Path $hermesBin,$pythonDir,$uvCache,$hermesHome | Out-Null

  $oldPath = $env:PATH
  $oldHome = $env:HERMES_HOME
  $oldToolDir = $env:UV_TOOL_DIR
  $oldToolBinDir = $env:UV_TOOL_BIN_DIR
  $oldCache = $env:UV_CACHE_DIR
  $oldPython = $env:UV_PYTHON_INSTALL_DIR
  try {
    $env:HERMES_HOME = $hermesHome
    $env:UV_TOOL_DIR = $hermesToolDir
    $env:UV_TOOL_BIN_DIR = $hermesBin
    $env:UV_CACHE_DIR = $uvCache
    $env:UV_PYTHON_INSTALL_DIR = $pythonDir
    $env:UV_LINK_MODE = "copy"
    $env:PATH = "$UvBin;$GitCmd;$env:SystemRoot\System32;$env:SystemRoot"

    $extras = ""
    if ($Manifest.hermes.extras.Count -gt 0) {
      $extras = "[" + (($Manifest.hermes.extras | ForEach-Object { [string]$_ }) -join ",") + "]"
    }
    $pkg = "hermes-agent$extras @ git+$($Manifest.hermes.repositoryUrl)@$($Manifest.hermes.tag)"
    & $uvExe tool install --force $pkg --python $Manifest.hermes.python
    if ($LASTEXITCODE -ne 0) {
      throw "uv tool install hermes-agent failed."
    }
  } finally {
    $env:PATH = $oldPath
    $env:HERMES_HOME = $oldHome
    $env:UV_TOOL_DIR = $oldToolDir
    $env:UV_TOOL_BIN_DIR = $oldToolBinDir
    $env:UV_CACHE_DIR = $oldCache
    $env:UV_PYTHON_INSTALL_DIR = $oldPython
  }

  $wrapper = Join-Path $hermesBin "hermes.cmd"
  @(
    "@echo off",
    "setlocal",
    "set ROOT=%~dp0..\..",
    "set HERMES_HOME=%ROOT%\data\hermes",
    "set UV_TOOL_DIR=%ROOT%\engines\hermes",
    "set UV_TOOL_BIN_DIR=%ROOT%\engines\hermes\bin",
    "set UV_CACHE_DIR=%ROOT%\runtimes\uv\cache",
    "set UV_PYTHON_INSTALL_DIR=%ROOT%\runtimes\uv\python",
    "set PATH=%ROOT%\engines\hermes\bin;%ROOT%\runtimes\git\cmd;%ROOT%\runtimes\uv\bin;%SystemRoot%\System32;%SystemRoot%",
    """%ROOT%\engines\hermes\hermes-agent\Scripts\python.exe"" -m hermes_cli %*"
  ) | Set-Content -LiteralPath $wrapper -Encoding ASCII
}

$manifest = Read-JsonFile -Path $ManifestPath
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$outputRoot = (Resolve-Path -LiteralPath $OutputDir).Path

$stage = Join-Path $outputRoot "windows-x64\ClawPanelPortable"
$work = Join-Path $outputRoot "work\windows-x64"
if (Test-Path -LiteralPath $stage) {
  Remove-Item -LiteralPath $stage -Recurse -Force
}
if (Test-Path -LiteralPath $work) {
  Remove-Item -LiteralPath $work -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage,$work | Out-Null

foreach ($dir in @(
  "data\clawpanel",
  "data\openclaw",
  "data\hermes",
  "data\media",
  "engines\openclaw",
  "engines\hermes",
  "runtimes\uv\bin",
  "runtimes\git"
)) {
  New-Item -ItemType Directory -Force -Path (Join-Path $stage $dir) | Out-Null
}

Copy-Item -LiteralPath (Join-Path $repoRoot "templates\portable.json") -Destination (Join-Path $stage "portable.json") -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "templates\README-USB.md") -Destination (Join-Path $stage "README-USB.md") -Force

$panelExe = Resolve-ClawPanelExe -Repo $ClawPanelRepo -Exe $ClawPanelExe
Copy-Item -LiteralPath $panelExe -Destination (Join-Path $stage "ClawPanel.exe") -Force

'{ "accessPassword": "123456", "engine": "openclaw" }' |
  Set-Content -LiteralPath (Join-Path $stage "data\clawpanel\clawpanel.json") -Encoding UTF8
'{ "gateway": { "host": "127.0.0.1", "port": 18789 }, "agents": { "main": { "name": "main" } } }' |
  Set-Content -LiteralPath (Join-Path $stage "data\openclaw\openclaw.json") -Encoding UTF8
"# Hermes config is managed by ClawPanel.`n" |
  Set-Content -LiteralPath (Join-Path $stage "data\hermes\config.yaml") -Encoding UTF8

Install-Uv -Manifest $manifest -WorkDir $work -UvBin (Join-Path $stage "runtimes\uv\bin")
Install-MinGit -Manifest $manifest -WorkDir $work -GitRoot (Join-Path $stage "runtimes\git")
Install-OpenClaw -Manifest $manifest -WorkDir $work -OpenClawDir (Join-Path $stage "engines\openclaw")

if (-not $SkipHermesBuild) {
  Install-Hermes `
    -Manifest $manifest `
    -Root $stage `
    -UvBin (Join-Path $stage "runtimes\uv\bin") `
    -GitCmd (Join-Path $stage "runtimes\git\cmd")
}

& (Join-Path $PSScriptRoot "verify-windows.ps1") -PortableRoot $stage

$zip = Join-Path $outputRoot ("{0}-v{1}.zip" -f $manifest.bundleName, $manifest.clawpanel.version)
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -LiteralPath $stage -DestinationPath $zip -Force
Get-FileHash -Algorithm SHA256 -LiteralPath $zip |
  Select-Object Algorithm, Hash, Path |
  ConvertTo-Json -Depth 3 |
  Set-Content -LiteralPath ($zip + ".sha256.json") -Encoding UTF8

Write-Host "Portable bundle: $zip"
