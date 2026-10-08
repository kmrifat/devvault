# Signs DevVault.exe and the DLLs next to it with an Authenticode
# certificate and an RFC 3161 timestamp (P4-09). Run after
# `flutter build windows --release`, on a Windows runner.
#
# Needs (see docs/release.md):
#   WINDOWS_CERT_PFX_BASE64   code-signing certificate + key, .pfx, base64
#   WINDOWS_CERT_PASSWORD     its password
$ErrorActionPreference = 'Stop'

$release = 'build/windows/x64/runner/Release'
$pfx = Join-Path $env:RUNNER_TEMP 'devvault-cert.pfx'
[IO.File]::WriteAllBytes($pfx, [Convert]::FromBase64String($env:WINDOWS_CERT_PFX_BASE64))

try {
  # signtool ships with the Windows SDK on GitHub's runners.
  $signtool = Get-ChildItem 'C:/Program Files (x86)/Windows Kits/10/bin' `
    -Recurse -Filter signtool.exe |
    Where-Object { $_.FullName -match '\\x64\\' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
  if (-not $signtool) { throw 'signtool.exe not found' }

  $files = Get-ChildItem $release -Recurse -Include *.exe, *.dll
  & $signtool.FullName sign /f $pfx /p $env:WINDOWS_CERT_PASSWORD `
    /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
    $files.FullName
  if ($LASTEXITCODE -ne 0) { throw "signtool sign failed ($LASTEXITCODE)" }

  & $signtool.FullName verify /pa /v (Join-Path $release 'DevVault.exe')
  if ($LASTEXITCODE -ne 0) { throw "signtool verify failed ($LASTEXITCODE)" }
}
finally {
  Remove-Item $pfx -ErrorAction SilentlyContinue
}
