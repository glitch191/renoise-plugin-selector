<#
.SYNOPSIS
  Builds the renoise-plugin-selector .xrnx package and its SHA-256 checksum.

.DESCRIPTION
  Validates manifest.xml, checks Lua syntax when luajit or luac is
  available, then writes a zip archive whose root holds the tool files
  directly, named <project>-<label>.xrnx, plus <file>.sha256.
  Used both locally and by .github/workflows/release.yml.

.PARAMETER Tag
  Release tag, for example v1.2. The leading "v" is removed to form the
  label. When the result is a plain number such as 1.2, it is also written
  into the packaged manifest's <Version>. Otherwise the repository
  manifest version is kept. Without a tag, the label is "dev".

.PARAMETER OutDir
  Output folder, relative to the repository root. Default: dist.
#>
param(
  [string]$Tag = "",
  [string]$OutDir = "dist"
)

$ErrorActionPreference = "Stop"

$ProjectName = "renoise-plugin-selector"
$ToolFiles = @("manifest.xml", "main.lua", "grouping.lua", "LICENSE")

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

# 1. Validate the manifest.
[xml]$Manifest = Get-Content -Raw -Encoding UTF8 "manifest.xml"
foreach ($Field in @("ApiVersion", "Id", "Version", "Name")) {
  if (-not $Manifest.RenoiseScriptingTool.$Field) {
    throw "manifest.xml: missing <$Field>."
  }
}
Write-Host "manifest.xml is valid XML (Id: $($Manifest.RenoiseScriptingTool.Id))."

# 2. Check Lua syntax when an interpreter is available.
$Lua = Get-Command luajit, luac -ErrorAction SilentlyContinue | Select-Object -First 1
if ($Lua) {
  foreach ($File in Get-ChildItem -Filter *.lua) {
    if ($Lua.Name -like "luajit*") {
      $Bytecode = [System.IO.Path]::GetTempFileName()
      & $Lua.Source -b $File.FullName $Bytecode | Out-Null
      Remove-Item -LiteralPath $Bytecode -ErrorAction SilentlyContinue
    } else {
      & $Lua.Source -p $File.FullName
    }
    if ($LASTEXITCODE -ne 0) { throw "Lua syntax error in $($File.Name)." }
  }
  Write-Host "Lua syntax OK ($($Lua.Name))."
} else {
  Write-Host "No Lua interpreter found: Lua syntax check skipped."
}

# 3. Work out the label and the packaged version.
$Label = $Tag -replace "^[vV]", ""
if (-not $Label) { $Label = "dev" }
if ($Label -notmatch "^[A-Za-z0-9._-]+$") { throw "Unsupported tag: '$Tag'." }

$Stage = Join-Path ([System.IO.Path]::GetTempPath()) ("$ProjectName-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $Stage | Out-Null
try {
  foreach ($File in $ToolFiles) {
    Copy-Item -LiteralPath $File -Destination $Stage
  }

  if ($Label -match "^\d+(\.\d+)?$") {
    $Manifest.RenoiseScriptingTool.Version = $Label
    $Settings = New-Object System.Xml.XmlWriterSettings
    $Settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $Settings.Indent = $true
    $Writer = [System.Xml.XmlWriter]::Create((Join-Path $Stage "manifest.xml"), $Settings)
    $Manifest.Save($Writer)
    $Writer.Close()
    Write-Host "Packaged manifest version set to $Label."
  } else {
    Write-Host "Packaged manifest keeps version $($Manifest.RenoiseScriptingTool.Version)."
  }

  # 4. Build the archive with the files at its root.
  $Out = Join-Path $Root $OutDir
  New-Item -ItemType Directory -Force -Path $Out | Out-Null
  $XrnxName = "$ProjectName-$Label.xrnx"
  $XrnxPath = Join-Path $Out $XrnxName
  if (Test-Path $XrnxPath) { Remove-Item -LiteralPath $XrnxPath }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $Zip = [System.IO.Compression.ZipFile]::Open($XrnxPath, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($File in $ToolFiles) {
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $Zip, (Join-Path $Stage $File), $File, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
  } finally {
    $Zip.Dispose()
  }
} finally {
  Remove-Item -Recurse -Force -LiteralPath $Stage
}

# 5. Checksum file in the usual "<hash>  <file name>" format.
$Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $XrnxPath).Hash.ToLower()
$ShaPath = "$XrnxPath.sha256"
[System.IO.File]::WriteAllText($ShaPath, "$Hash  $XrnxName`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Built $OutDir/$XrnxName"
Write-Host "SHA-256 $Hash"
