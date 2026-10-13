<#
.SYNOPSIS
  Installs renoise-plugin-selector into Renoise's Tools folder for local use.

.DESCRIPTION
  Copies the tool files into %APPDATA%\Renoise\V<version>\Scripts\Tools\<Id>.xrnx
  as an unpacked (development) tool folder. Only that folder is written:
  no other tool, setting or Renoise file is touched.

  When exactly one Renoise 3.5.x preferences folder exists, it is used.
  Otherwise the script stops and asks for -RenoiseVersion or -ToolsPath.

.PARAMETER RenoiseVersion
  Renoise version folder to use, for example 3.5.4.

.PARAMETER ToolsPath
  Full path of the Renoise Tools folder, if it is somewhere else.

.EXAMPLE
  .\scripts\install-tool.ps1 -RenoiseVersion 3.5.4
#>
param(
  [string]$RenoiseVersion = "",
  [string]$ToolsPath = ""
)

$ErrorActionPreference = "Stop"

$ToolFiles = @("manifest.xml", "main.lua", "grouping.lua", "LICENSE")

$Root = Split-Path -Parent $PSScriptRoot
[xml]$Manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $Root "manifest.xml")
$ToolId = $Manifest.RenoiseScriptingTool.Id
if (-not $ToolId) { throw "manifest.xml has no <Id>." }

if (-not $ToolsPath) {
  $RenoiseRoot = Join-Path $env:APPDATA "Renoise"
  if ($RenoiseVersion) {
    $VersionDir = Join-Path $RenoiseRoot ("V" + ($RenoiseVersion -replace "^[vV]", ""))
    if (-not (Test-Path -LiteralPath $VersionDir)) {
      Write-Error "Renoise folder not found: $VersionDir"
      exit 1
    }
  } else {
    $Found = @(Get-ChildItem -LiteralPath $RenoiseRoot -Directory -Filter "V3.5*" -ErrorAction SilentlyContinue)
    if ($Found.Count -ne 1) {
      if ($Found.Count -eq 0) {
        Write-Host "No Renoise 3.5.x preferences folder found in $RenoiseRoot."
      } else {
        Write-Host "Several Renoise 3.5.x folders found:"
        $Found | ForEach-Object { Write-Host "  $($_.Name)" }
      }
      Write-Host "Run again with the version to use, for example:"
      Write-Host "  .\scripts\install-tool.ps1 -RenoiseVersion 3.5.4"
      Write-Host "or with the Tools folder path:"
      Write-Host "  .\scripts\install-tool.ps1 -ToolsPath <path to Scripts\Tools>"
      exit 1
    }
    $VersionDir = $Found[0].FullName
  }
  $ToolsPath = Join-Path $VersionDir "Scripts\Tools"
}

if (-not (Test-Path -LiteralPath (Split-Path -Parent $ToolsPath))) {
  Write-Error "Folder not found: $(Split-Path -Parent $ToolsPath)"
  exit 1
}
New-Item -ItemType Directory -Force -Path $ToolsPath | Out-Null

$Target = Join-Path $ToolsPath "$ToolId.xrnx"
New-Item -ItemType Directory -Force -Path $Target | Out-Null
foreach ($File in $ToolFiles) {
  Copy-Item -LiteralPath (Join-Path $Root $File) -Destination $Target -Force
}

Write-Host "Installed $ToolId into:"
Write-Host "  $Target"
Write-Host "If Renoise is open, use Tools > Reload All Tools (or restart Renoise)."
