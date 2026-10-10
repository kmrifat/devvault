# Writes DevVault.appinstaller for a built MSIX (ADR-0007 §4, P6-05):
# where Windows finds the latest release when the user presses Update… in
# DevVault. Run after windows_msix.ps1.
#
# The package's name, publisher, version and architecture are read from
# the MSIX's own AppxManifest.xml, so they always match what Windows
# checks. There are no UpdateSettings: Windows never checks on its own;
# only DevVault asks, when the user says so.
#
#   windows_appinstaller.ps1 -Msix devvault-windows-x64.msix
#     [-FeedUri <where this file is served>] [-PackageUri <the .msix>]
#
# By default the file describes itself at the latest release's download
# URL and the MSIX at this version's tag, as `release.yml` publishes them.
param(
  [Parameter(Mandatory = $true)] [string] $Msix,
  [string] $FeedUri = 'https://github.com/kmrifat/devvault/releases/latest/download/DevVault.appinstaller',
  [string] $PackageUri,
  [string] $Out = 'DevVault.appinstaller'
)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $Msix).Path)
try {
  $entry = $zip.GetEntry('AppxManifest.xml')
  if (-not $entry) { throw "$Msix has no AppxManifest.xml" }
  $reader = New-Object IO.StreamReader($entry.Open())
  try { [xml] $manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally {
  $zip.Dispose()
}
$id = $manifest.Package.Identity
if (-not ($id.Version -match '^(\d+)\.(\d+)\.(\d+)\.0$')) {
  throw "Unexpected package version '$($id.Version)'"
}
$version = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
if (-not $id.ProcessorArchitecture) { throw "$Msix names no processor architecture" }
if (-not $PackageUri) {
  $PackageUri = "https://github.com/kmrifat/devvault/releases/download/v$version/devvault-windows-x64.msix"
}

function Escape([string] $text) { [Security.SecurityElement]::Escape($text) }

$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
  Version="$(Escape $id.Version)"
  Uri="$(Escape $FeedUri)">
  <MainPackage
    Name="$(Escape $id.Name)"
    Publisher="$(Escape $id.Publisher)"
    Version="$(Escape $id.Version)"
    ProcessorArchitecture="$(Escape $id.ProcessorArchitecture)"
    Uri="$(Escape $PackageUri)" />
</AppInstaller>
"@
[xml] $xml | Out-Null  # well-formed
$path = if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
[IO.File]::WriteAllText($path, $xml, (New-Object Text.UTF8Encoding($false)))
Write-Host "Wrote $Out for $($id.Name) $($id.Version) ($($id.Publisher))"
