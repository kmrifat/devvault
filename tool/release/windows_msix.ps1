# Packages the Windows release build as an MSIX (P2-13), with the `msix`
# package. Run after `flutter build windows --release` (and after
# windows_sign.ps1 when signing), on a Windows runner.
#
# With WINDOWS_CERT_PFX_BASE64 and WINDOWS_CERT_PASSWORD (docs/release.md)
# the package is signed with that certificate, whose subject becomes the
# MSIX publisher. Without them it is built unsigned and named so.
$ErrorActionPreference = 'Stop'

$release = 'build/windows/x64/runner/Release'
$msixArgs = @('run', 'msix:create', '--build-windows', 'false',
  '--install-certificate', 'false')
$pfx = $null

try {
  if ($env:SIGN_WINDOWS -eq 'true') {
    $pfx = Join-Path $env:RUNNER_TEMP 'devvault-msix.pfx'
    [IO.File]::WriteAllBytes($pfx, [Convert]::FromBase64String($env:WINDOWS_CERT_PFX_BASE64))
    $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2(
      $pfx, $env:WINDOWS_CERT_PASSWORD)
    $msixArgs += @('--certificate-path', $pfx,
      '--certificate-password', $env:WINDOWS_CERT_PASSWORD,
      '--publisher', $cert.Subject)
    $name = 'devvault-windows-x64.msix'
  } else {
    $msixArgs += @('--sign-msix', 'false')
    $name = 'devvault-windows-x64-unsigned.msix'
  }

  & dart @msixArgs
  if ($LASTEXITCODE -ne 0) { throw "msix:create failed ($LASTEXITCODE)" }
}
finally {
  if ($pfx) { Remove-Item $pfx -ErrorAction SilentlyContinue }
}

$built = Get-ChildItem $release -Filter *.msix | Select-Object -First 1
if (-not $built) { throw 'msix:create wrote no .msix' }
Move-Item $built.FullName $name
Write-Host "Wrote $name"
