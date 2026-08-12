[CmdletBinding()]
param(
  [string]$Version = '0.2.2'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $projectRoot "artifacts\v$Version"

if ($env:BESS_HARMONY_RELEASE_READY -ne 'YES') {
  throw 'Release signing is not confirmed. Configure the AGC certificate/Profile in DevEco Studio, then set BESS_HARMONY_RELEASE_READY=YES for this PowerShell session.'
}
if (Test-Path -LiteralPath $artifactRoot) {
  throw "Artifact directory already exists; refusing to overwrite: $artifactRoot"
}

& (Join-Path $PSScriptRoot 'verify-contracts.ps1')
$hvigor = Get-Command hvigorw.bat -ErrorAction SilentlyContinue
if ($null -eq $hvigor) { $hvigor = Get-Command hvigorw -ErrorAction SilentlyContinue }
if ($null -eq $hvigor) { throw 'hvigorw was not found. Open a DevEco Studio 6.0.0 terminal or add its Hvigor wrapper to PATH.' }

Push-Location $projectRoot
try {
  & $hvigor.Source --no-daemon --mode project -p product=default -p buildMode=release clean
  if ($LASTEXITCODE -ne 0) { throw "Hvigor clean failed with exit code $LASTEXITCODE" }
  $entryBuild = [IO.Path]::GetFullPath((Join-Path $projectRoot 'entry\build'))
  $projectPrefix = [IO.Path]::GetFullPath($projectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $entryBuild.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean build output outside the project: $entryBuild"
  }
  if (Test-Path -LiteralPath $entryBuild) { Remove-Item -LiteralPath $entryBuild -Recurse -Force }
  $buildStartedAt = Get-Date
  & $hvigor.Source --no-daemon --mode project -p product=default -p buildMode=release prepareBessAssets
  if ($LASTEXITCODE -ne 0) { throw "Hvigor asset preparation failed with exit code $LASTEXITCODE" }
  & $hvigor.Source --no-daemon --mode project -p product=default -p buildMode=release assembleApp
  if ($LASTEXITCODE -ne 0) { throw "Hvigor release build failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }

$freshnessFloor = $buildStartedAt.AddSeconds(-5)
$app = Get-ChildItem $projectRoot -Recurse -File -Filter *.app |
  Where-Object { $_.FullName -Match '\\build\\' -and $_.LastWriteTime -ge $freshnessFloor } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
$hap = Get-ChildItem $projectRoot -Recurse -File -Filter *.hap |
  Where-Object { $_.FullName -Match '\\build\\' -and $_.Name -Match 'signed' -and $_.LastWriteTime -ge $freshnessFloor } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if ($null -eq $app -or $null -eq $hap) { throw 'Signed APP/HAP artifacts were not found. Check DevEco signing configuration and the build log.' }

if ([string]::IsNullOrWhiteSpace($env:DEVECO_SDK_HOME)) {
  throw 'DEVECO_SDK_HOME is not set; the release cannot be verified with the SDK signing tool.'
}
$signTool = Join-Path $env:DEVECO_SDK_HOME 'default\openharmony\toolchains\lib\hap-sign-tool.jar'
$studioRoot = Split-Path -Parent $env:DEVECO_SDK_HOME
$java = Join-Path $studioRoot 'jbr\bin\java.exe'
if (-not (Test-Path -LiteralPath $signTool)) { throw "HarmonyOS signing verifier not found: $signTool" }
if (-not (Test-Path -LiteralPath $java)) { throw "DevEco JBR not found: $java" }

$verifyRoot = Join-Path ([IO.Path]::GetTempPath()) ("bess-sign-verify-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $verifyRoot | Out-Null
try {
  foreach ($candidate in @($hap, $app)) {
    $safeName = [IO.Path]::GetFileNameWithoutExtension($candidate.Name)
    & $java -jar $signTool verify-app `
      -inFile $candidate.FullName `
      -outCertChain (Join-Path $verifyRoot "$safeName-cert-chain.cer") `
      -outProfile (Join-Path $verifyRoot "$safeName-profile.p7b")
    if ($LASTEXITCODE -ne 0) {
      throw "Signature verification failed for $($candidate.FullName) with exit code $LASTEXITCODE"
    }
  }
} finally {
  Remove-Item -LiteralPath $verifyRoot -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $artifactRoot | Out-Null
$appTarget = Join-Path $artifactRoot "BESS-HarmonyOS-v$Version.app"
$hapTarget = Join-Path $artifactRoot "BESS-HarmonyOS-v$Version-signed.hap"
Copy-Item -LiteralPath $app.FullName -Destination $appTarget
Copy-Item -LiteralPath $hap.FullName -Destination $hapTarget
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\RELEASE_NOTES_0.2.1.md') -Destination $artifactRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\UPGRADE_0.2.1.md') -Destination $artifactRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\INSTALL_AND_UPGRADE.md') -Destination $artifactRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\OFFLINE_PRIVACY.md') -Destination $artifactRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\SIGNING_FINGERPRINT_0.2.1.txt') -Destination $artifactRoot

$sumLines = foreach ($file in Get-ChildItem $artifactRoot -File | Where-Object Extension -In '.app','.hap') {
  $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  "$hash  $($file.Name)"
}
Set-Content -LiteralPath (Join-Path $artifactRoot 'SHA256SUMS.txt') -Value $sumLines -Encoding UTF8
Write-Host "Release artifacts created at $artifactRoot" -ForegroundColor Green
