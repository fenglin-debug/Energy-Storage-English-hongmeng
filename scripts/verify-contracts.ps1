[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $projectRoot

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "CONTRACT_CHECK_FAILED: $Message" }
}

$app = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot 'AppScope\app.json5') | ConvertFrom-Json
$buildProfile = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot 'build-profile.json5') | ConvertFrom-Json
$moduleText = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot 'entry\src\main\module.json5')
$databaseText = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot 'entry\src\main\ets\data\DatabaseService.ets')
$backupText = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot 'entry\src\main\ets\data\LearningBackupCodec.ets')
$allEts = (Get-ChildItem (Join-Path $projectRoot 'entry\src\main\ets') -Recurse -Filter *.ets |
  ForEach-Object { Get-Content -Raw -Encoding UTF8 -LiteralPath $_.FullName }) -join "`n"

Assert-True ($app.app.bundleName -eq 'com.bess.salestrainer') 'bundleName must stay permanent'
Assert-True ($app.app.versionCode -eq 5) 'versionCode must be 5 for v0.4.1'
Assert-True ($app.app.versionName -eq '0.4.1') 'versionName must be 0.4.1'
Assert-True ($buildProfile.app.products[0].compatibleSdkVersion -eq '6.0.0(20)') 'compatible SDK must be HarmonyOS 6 API 20'
Assert-True ($buildProfile.app.products[0].targetSdkVersion -eq '6.0.0(20)') 'target SDK must be HarmonyOS 6 API 20'
Assert-True ($moduleText -notmatch 'ohos.permission.INTERNET') 'offline app must not request INTERNET'
Assert-True ($moduleText -notmatch 'ohos.permission.MICROPHONE') 'offline player must not request MICROPHONE'
Assert-True ($moduleText -match 'ohos.permission.KEEP_BACKGROUND_RUNNING') 'background audio permission is required'
Assert-True ($moduleText -match '"audioPlayback"') 'audioPlayback background mode is required'
Assert-True ($moduleText -match '"deviceTypes"\s*:\s*\["phone"\]') 'only phone device type is supported'
Assert-True ($allEts -notmatch '\bWebView\s*\(') 'WebView is forbidden'
Assert-True ($allEts -notmatch 'constructor\([^\r\n]*(private|public|protected|readonly)') 'ArkTS constructor parameter properties are forbidden'
Assert-True ($allEts -notmatch '@State[^\r\n]*\|\s*(null|undefined)') '@State must not use null/undefined union types'
Assert-True ($allEts -notmatch '(replace|split)\(/') 'ArkTS RegExp literals are forbidden; use RegExp constructor'

$tables = @('word_memory_states','review_logs','vocabulary_session_checkpoints','review_action_keys',
  'scenario_sessions','scenario_turn_progress','study_tasks','item_memory_states','article_progress')
foreach ($table in $tables) { Assert-True ($databaseText.Contains($table)) "missing learning table $table" }
foreach ($field in @('wordMemoryStates','reviewLogs','vocabularyCheckpoints','reviewActionKeys','scenarioSessions',
  'scenarioTurnProgress','studyTasks','itemMemoryStates','articleProgress')) {
  Assert-True ($backupText.Contains($field)) "missing backup field $field"
}
Assert-True ($backupText.Contains('600_000')) 'PBKDF2 work factor must be 600,000'
Assert-True ($backupText.Contains('AES_256_GCM_PBKDF2_HMAC_SHA256')) 'backup encryption identifier changed'
Assert-True ($backupText.Contains("manifest.json")) 'backup manifest entry changed'
Assert-True ($backupText.Contains("learning-data.bin")) 'backup payload entry changed'

$lock = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot 'assets.lock.json') | ConvertFrom-Json
foreach ($asset in $lock.assets) {
  $source = [IO.Path]::GetFullPath((Join-Path $projectRoot $asset.source))
  $destination = [IO.Path]::GetFullPath((Join-Path $projectRoot $asset.destination))
  Assert-True (Test-Path -LiteralPath $source -PathType Leaf) "canonical asset missing: $source"
  $actual = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
  Assert-True ($actual -eq $asset.sha256.ToLowerInvariant()) "asset hash changed: $($asset.source)"
  Assert-True (Test-Path -LiteralPath $destination -PathType Leaf) "bundled asset missing: $destination"
  $copied = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
  Assert-True ($copied -eq $actual) "bundled asset differs from canonical source: $($asset.destination)"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Get-ArticleCount([string]$Path) {
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entry = $archive.GetEntry('manifest.json')
    Assert-True ($null -ne $entry) "article manifest missing: $Path"
    $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8)
    try { return (($reader.ReadToEnd() | ConvertFrom-Json).articles | Measure-Object).Count }
    finally { $reader.Dispose() }
  } finally { $archive.Dispose() }
}
$articleCount = Get-ArticleCount (Join-Path $projectRoot 'entry\src\main\resources\rawfile\bundled.bessarticle')
$articleCount += Get-ArticleCount (Join-Path $projectRoot 'entry\src\main\resources\rawfile\youtube-bess.bessarticle')
Assert-True ($articleCount -eq 22) 'the two bundled article packages must contain exactly 22 articles'

$modelsText = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot 'entry\src\main\ets\domain\Models.ets')
$vocabularyText = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot 'entry\src\main\ets\data\VocabularyRepositoryImpl.ets')
$audioText = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot 'entry\src\main\ets\data\AudioPlaybackRepositoryImpl.ets')
$scenarioPageText = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot 'entry\src\main\ets\features\scenario\ScenarioPage.ets')
Assert-True ($modelsText -match 'autoPlayNextArticle:\s*true') 'automatic next article must default to enabled'
Assert-True ($vocabularyText -match 'vocabulary_aliases') 'vocabulary search must include aliases'
Assert-True ($vocabularyText -notmatch 'return QuestionMode\.TRANSFER') 'new reviews must never allocate TRANSFER'
Assert-True ($vocabularyText -match 'review_action_keys') 'review advance must remain idempotent'
Assert-True ($audioText -match 'setAVQueueItems') 'AVSession queue must be published'
Assert-True ($audioText -match "session\.on\('playNext'") 'AVSession next event must be handled'
Assert-True ($audioText -match "session\.on\('playPrevious'") 'AVSession previous event must be handled'
Assert-True ($scenarioPageText -match 'customerTextZh') 'scenario reveal must include customer Chinese text'

$scanRoots = @('AppScope', 'entry\src', 'docs', 'scripts') | ForEach-Object { Join-Path $projectRoot $_ }
$forbidden = @(
  Get-ChildItem $projectRoot -File -Include *.p12,*.p7b,*.cer,*.profile,signing-config.json5
  foreach ($root in $scanRoots) {
    Get-ChildItem $root -Recurse -File -Include *.p12,*.p7b,*.cer,*.profile,signing-config.json5
  }
)
Assert-True ($forbidden.Count -eq 0) 'signing certificate, profile, or private material must not be committed'

Write-Host 'HarmonyOS contract checks passed.' -ForegroundColor Green
