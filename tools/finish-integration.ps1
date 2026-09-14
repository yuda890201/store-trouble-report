<#
.SYNOPSIS
  店舗コミュニケーションアプリとの連動を、一括で仕上げます。

.DESCRIPTION
  次を順番に行います。途中で失敗したら、その場で理由を出して止まります。

    1. 最新のコードを取り込む（git pull）
    2. firestore.rules に写真のブロックがあるか確認する
    3. 連動先に渡す「閲覧専用アカウント」を作る
    4. そのアカウントで本番の Firestore を実際に叩いて、
       読めること・書けないことを確かめる
    5. パスワードを埋めた回答書を作って開く

  何度実行しても問題ありません。すでに済んでいる手順は飛ばします。

  4 が肝心です。エミュレータでルールを検証してありますが、
  コンソールに貼ったものが効いているかは実際に叩かないと分かりません。

.PARAMETER Email
  閲覧アカウントのアドレス。既定は viewer@view.example.com です。
  fm.example.com のアドレスは書き込みができてしまうため指定できません。

.PARAMETER Password
  パスワード。省略すると自動生成します。すでにアカウントがある場合は、
  そのときのパスワードを指定してください。

.PARAMETER OutPath
  回答書の出力先。既定はデスクトップです。
  パスワードが入るので、リポジトリの中には置かないでください。

.PARAMETER SkipPull
  指定すると git pull を行いません。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\finish-integration.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\finish-integration.ps1 -Password "前に作ったときのパスワード"

.NOTES
  パスワードはリポジトリには保存されません。画面と、デスクトップの回答書にだけ出ます。
#>
[CmdletBinding()]
param(
  [string]$Email = "viewer@view.example.com",
  [string]$Password,
  [string]$OutPath,
  [switch]$SkipPull
)

# native コマンド（git）は進捗を stderr に出す。Stop のままだとそれが致命的エラーになる。
$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
# PowerShell 5.1 の既定は TLS 1.0 のことがあり、そのままでは Google の API に繋がらない
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$script:StepNo = 0
function Write-Step {
  param([string]$Text)
  $script:StepNo++
  Write-Host ""
  Write-Host ("[{0}] {1}" -f $script:StepNo, $Text) -ForegroundColor Cyan
}
function Write-Ok    { param([string]$T) Write-Host "    OK   $T" -ForegroundColor Green }
function Write-Info  { param([string]$T) Write-Host "         $T" -ForegroundColor Gray }
function Write-Warn2 { param([string]$T) Write-Host "    !    $T" -ForegroundColor Yellow }
function Write-Fail  { param([string]$T) Write-Host "    NG   $T" -ForegroundColor Red }

function Get-ErrorReason {
  # setup.ps1 と同じ読み取り方。PowerShell 5.1 では ErrorDetails に入ることが多いが、
  # 入っていない環境ではレスポンス本文を自分で読む必要がある。
  param($ErrorRecord)
  try {
    $detail = $ErrorRecord.ErrorDetails.Message
    if (-not $detail) {
      $stream = $ErrorRecord.Exception.Response.GetResponseStream()
      $detail = (New-Object IO.StreamReader($stream)).ReadToEnd()
    }
    return (($detail | ConvertFrom-Json).error.message)
  } catch {
    return $ErrorRecord.Exception.Message
  }
}

function Get-StatusCode {
  param($ErrorRecord)
  try { return [int]$ErrorRecord.Exception.Response.StatusCode } catch { return 0 }
}

$RepoRoot = Split-Path -Parent $PSScriptRoot

# ============================================ 1. 最新のコードを取り込む --
Write-Step "最新のコードを取り込みます"
if ($SkipPull) {
  Write-Info "-SkipPull が指定されているので飛ばします"
} elseif (-not (Test-Path (Join-Path $RepoRoot ".git"))) {
  Write-Warn2 "git のリポジトリではないので飛ばします: $RepoRoot"
} else {
  Push-Location $RepoRoot
  & git fetch origin main 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Fail "git fetch に失敗しました。ネットワークを確認してください。"
    exit 1
  }
  & git merge --ff-only origin/main 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Warn2 "手元に独自の変更があるため、そのままでは取り込めません。"
    Write-Info "次で状態を確認してください:  git status"
  } else {
    Write-Ok "最新になりました"
  }
  Pop-Location
}

# ============================================== 2. ルールの中身を確認 --
Write-Step "firestore.rules を確認します"
$RulesPath = Join-Path $RepoRoot "firestore.rules"
if (-not (Test-Path $RulesPath)) {
  Write-Fail "firestore.rules が見つかりません: $RulesPath"
  exit 1
}
$rules = Get-Content $RulesPath -Raw -Encoding UTF8
$needPhotos = $rules -match "trouble_report_photos"
$needStore  = $rules -match "isStoreAccount"
if ($needPhotos -and $needStore) {
  Write-Ok "手元のルールは最新です（店舗アカウント限定 + 写真のコレクション）"
  Write-Info "このあと 4 で、コンソールに貼ったものが効いているか実際に確かめます。"
} else {
  Write-Fail "手元の firestore.rules が古いようです。git pull が済んでいるか確認してください。"
  exit 1
}

# ======================================== 3. 設定を index.html から読む --
Write-Step "Firebase の設定を読み取ります"
$IndexPath = Join-Path $RepoRoot "index.html"
if (-not (Test-Path $IndexPath)) {
  Write-Fail "index.html が見つかりません: $IndexPath"
  exit 1
}
$index = Get-Content $IndexPath -Raw -Encoding UTF8
$mKey = [Regex]::Match($index, 'apiKey:\s*"([^"]+)"')
$mPid = [Regex]::Match($index, 'projectId:\s*"([^"]+)"')
if (-not $mKey.Success -or -not $mPid.Success) {
  Write-Fail "index.html から設定を読み取れませんでした。先に tools\setup.ps1 を実行してください。"
  exit 1
}
$apiKey    = $mKey.Groups[1].Value
$projectId = $mPid.Groups[1].Value
Write-Ok "プロジェクト: $projectId"

# ============================================== 4. 閲覧アカウントを作る --
Write-Step "閲覧専用アカウントを用意します"

if ($Email -match '@fm\.example\.com$') {
  Write-Fail "fm.example.com のアドレスは店舗アカウント用です。書き込みができてしまいます。"
  exit 1
}
if ($Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
  Write-Fail "アドレスの形式が正しくありません: $Email"
  exit 1
}

$generated = $false
if (-not $Password) {
  # 紛らわしい文字（0/O/1/l/I）を避けた 20 文字
  $chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  $buf = New-Object byte[] 20
  $rng.GetBytes($buf)
  $Password = -join ($buf | ForEach-Object { $chars[$_ % $chars.Length] })
  $generated = $true
}
if ($Password.Length -lt 6) {
  Write-Fail "パスワードは 6 文字以上にしてください。"
  exit 1
}

Write-Info "アドレス: $Email"

$signUpUri = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey"
$signInUri = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey"
$payload   = @{ email = $Email; password = $Password; returnSecureToken = $true } | ConvertTo-Json -Compress

$idToken = $null
try {
  $res = Invoke-RestMethod -Method Post -Uri $signUpUri -ContentType "application/json; charset=utf-8" -Body $payload -ErrorAction Stop
  $idToken = $res.idToken
  Write-Ok "新しく登録しました"
} catch {
  $reason = Get-ErrorReason $_
  if ($reason -like "EMAIL_EXISTS*") {
    try {
      $res = Invoke-RestMethod -Method Post -Uri $signInUri -ContentType "application/json; charset=utf-8" -Body $payload -ErrorAction Stop
      $idToken = $res.idToken
      Write-Ok "すでに登録済みで、このパスワードでログインできました"
      $generated = $false
    } catch {
      Write-Fail "同じアドレスのアカウントがありますが、パスワードが一致しません。"
      Write-Info "前に作ったときのパスワードを -Password で指定してください。"
      Write-Info "分からない場合はコンソールで変更できます:"
      Write-Info "  https://console.firebase.google.com/project/$projectId/authentication/users"
      exit 1
    }
  } elseif ($reason -like "OPERATION_NOT_ALLOWED*" -or $reason -like "*ADMIN_ONLY_OPERATION*") {
    Write-Fail "メール／パスワードのログイン方法が有効になっていません。"
    Write-Info "  https://console.firebase.google.com/project/$projectId/authentication/providers"
    exit 1
  } else {
    Write-Fail "登録できませんでした: $reason"
    exit 1
  }
}

# ============================== 5. 本番のルールが効いているか実際に確かめる --
Write-Step "本番の Firestore を実際に叩いて確かめます"
Write-Info "コンソールに貼ったルールが効いているかは、叩いてみないと分かりません。"

$base    = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents"
$headers = @{ Authorization = "Bearer $idToken" }

# 書き込みの確認には「ルールの中身の検査は通るが、アカウントの条件だけで落ちる」
# 形の文書を使う。probe のような雑な文書だと、古いルールでも本文チェックで
# 落ちてしまい、「書けなかった＝安全」と誤判定してしまう。
$MARK = "finish-integration.ps1 の確認用（消してください）"
$probeBody = @{
  "trouble_reports" = @{ fields = @{
      comment  = @{ stringValue = $MARK }
      reporter = @{ stringValue = $MARK }
  } } | ConvertTo-Json -Compress -Depth 5
  "trouble_report_photos" = @{ fields = @{
      photo_data = @{ stringValue = "data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==" }
  } } | ConvertTo-Json -Compress -Depth 5
}

$checks = @()
$leaked = @()
function Add-Check { param([string]$Name, [bool]$Pass, [string]$Note) $script:checks += [pscustomobject]@{ Name = $Name; Pass = $Pass; Note = $Note } }

# 読めること
foreach ($c in @("trouble_reports", "trouble_report_photos")) {
  try {
    $readUri = $base + "/" + $c + "?pageSize=1"
    Invoke-RestMethod -Method Get -Uri $readUri -Headers $headers -ErrorAction Stop | Out-Null
    Add-Check "$c を読める" $true ""
  } catch {
    $code = Get-StatusCode $_
    Add-Check "$c を読める" $false "HTTP $code : $(Get-ErrorReason $_)"
  }
}

# 書けないこと
foreach ($c in @("trouble_reports", "trouble_report_photos")) {
  $created = $null
  try {
    $created = Invoke-RestMethod -Method Post -Uri "$base/$c" -Headers $headers -ContentType "application/json; charset=utf-8" -Body $probeBody[$c] -ErrorAction Stop
  } catch {
    $code = Get-StatusCode $_
    if ($code -eq 403) { Add-Check "$c に書けない" $true "" }
    else { Add-Check "$c に書けない" $false "拒否はされたが理由が違う（HTTP $code）: $(Get-ErrorReason $_)" }
  }
  if ($created) {
    Add-Check "$c に書けない" $false "書けてしまいました。ルールがコンソールに反映されていません。"
    $script:leaked += $created.name
  }
}

Write-Host ""
$failed = 0
foreach ($c in $checks) {
  if ($c.Pass) { Write-Ok $c.Name }
  else { $failed++; Write-Fail ("{0} — {1}" -f $c.Name, $c.Note) }
}

if ($failed -gt 0) {
  Write-Host ""
  Write-Host "── ルールがまだ反映されていません ─────────────" -ForegroundColor Red
  Write-Host "  firestore.rules の中身をコンソールに貼って「公開」してください。" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "    https://console.firebase.google.com/project/$projectId/firestore/rules" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "  貼るファイル: $RulesPath" -ForegroundColor Yellow
  Write-Host ""
  if ($leaked.Count -gt 0) {
    Write-Host "  書けてしまったため、確認用のドキュメントが残っています。" -ForegroundColor Yellow
    Write-Host "  ルールを直したあと、コンソールのデータ画面から消してください" -ForegroundColor Yellow
    Write-Host "  （アプリからは消せません。ルールで削除を禁じているためです）。" -ForegroundColor Yellow
    Write-Host ""
    foreach ($n in $leaked) { Write-Host ("    " + ($n -replace '^.*/documents/', '')) -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "    https://console.firebase.google.com/project/$projectId/firestore/data" -ForegroundColor Yellow
    Write-Host ""
  }
  Write-Host "  直したら、このスクリプトをもう一度実行してください。" -ForegroundColor Yellow
  exit 1
}

Write-Host ""
Write-Ok "閲覧アカウントは、読めるが書けない状態になっています"

# ================================================== 6. 回答書を組み立てる --
Write-Step "連動先に渡す回答書を作ります"

$TemplatePath = Join-Path $RepoRoot "docs\integration-reply.md"
if (-not (Test-Path $TemplatePath)) {
  Write-Fail "回答書のもとが見つかりません: $TemplatePath"
  exit 1
}
$reply = Get-Content $TemplatePath -Raw -Encoding UTF8
$placeholder = "（別途お伝えします）"
if ($reply -notlike "*$placeholder*") {
  Write-Warn2 "差し込み位置が見つかりませんでした。もとのまま出力します。"
} else {
  $reply = $reply.Replace($placeholder, $Password)
}
$reply = $reply.Replace("viewer@view.example.com", $Email)

if (-not $OutPath) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  if (-not $desktop) { $desktop = $env:USERPROFILE }
  $OutPath = Join-Path $desktop "連動の回答（コミュニケーションアプリ用）.md"
}
if (-not [IO.Path]::IsPathRooted($OutPath)) {
  $OutPath = Join-Path (Get-Location).Path $OutPath
}
if ($OutPath.StartsWith($RepoRoot, [StringComparison]::OrdinalIgnoreCase)) {
  Write-Fail "パスワードが入るため、リポジトリの中には出力できません: $OutPath"
  Write-Info "-OutPath でリポジトリの外を指定してください。"
  exit 1
}

# BOM 付き UTF-8。メモ帳で開いても日本語が化けない。
[IO.File]::WriteAllText($OutPath, $reply, (New-Object Text.UTF8Encoding($true)))
Write-Ok "作りました: $OutPath"

# ======================================================== 7. まとめ --
Write-Host ""
Write-Host "── 完了 ──────────────────────────────────" -ForegroundColor Green
Write-Host ""
Write-Host "  閲覧アカウント" -ForegroundColor White
Write-Host "    アドレス   : $Email"
Write-Host "    パスワード : $Password"
Write-Host ""
if ($generated) {
  Write-Info "パスワードは自動生成しました。回答書にも入っています。"
}
Write-Host "  次にやること" -ForegroundColor White
Write-Host "    1. デスクトップにできた回答書を、コミュニケーションアプリのチャットに貼る"
Write-Host "    2. アプリから写真つきで 1 件送ってみる（写真の保存先が変わったため）"
Write-Host ""
Write-Warn2 "回答書にはパスワードが入っています。リポジトリに入れないでください。"
Write-Host ""

try { Start-Process $OutPath } catch { Write-Info "回答書を自動で開けませんでした。手で開いてください。" }
