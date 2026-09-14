<#
.SYNOPSIS
  店舗コミュニケーションアプリ用の「閲覧専用アカウント」を作ります。

.DESCRIPTION
  不具合報告アプリの Firestore を、店舗コミュニケーションアプリ側から
  読むためのアカウントを 1 つ登録します。

  このアカウントは読むことしかできません。報告の作成もステータスの変更も
  firestore.rules の側で弾かれます（書けるのは fm+数字 の店舗アカウントだけ）。

  パスワードを省略すると、その場で強いものを自動生成して表示します。
  表示された内容をコミュニケーションアプリ側に渡してください。

.PARAMETER Email
  登録するアドレス。既定は viewer@view.example.com です。
  fm.example.com のアドレスは書き込みができてしまうため指定できません。

.PARAMETER Password
  パスワード。省略すると自動生成します。6 文字以上が必要です。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\add-viewer.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\add-viewer.ps1 -Password "好きな文字列"

.NOTES
  何度実行しても問題ありません。すでにある場合はその旨を表示します。
  パスワードはリポジトリには保存されません。画面に出るだけです。
#>
[CmdletBinding()]
param(
  [string]$Email = "viewer@view.example.com",
  [string]$Password
)

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

function Write-Ok    { param([string]$T) Write-Host "    OK   $T" -ForegroundColor Green }
function Write-Info  { param([string]$T) Write-Host "         $T" -ForegroundColor Gray }
function Write-Fail  { param([string]$T) Write-Host "    NG   $T" -ForegroundColor Red }

# ---------------------------------------------------------------- 入力確認 --
if ($Email -match '@fm\.example\.com$') {
  Write-Fail "fm.example.com のアドレスは店舗アカウント用です。閲覧用には別のドメインを使ってください。"
  exit 1
}
if ($Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
  Write-Fail "アドレスの形式が正しくありません: $Email"
  exit 1
}

if (-not $Password) {
  # 紛らわしい文字（0/O/1/l/I）を避けた 20 文字
  $chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  $buf = New-Object byte[] 20
  $rng.GetBytes($buf)
  $Password = -join ($buf | ForEach-Object { $chars[$_ % $chars.Length] })
}
if ($Password.Length -lt 6) {
  Write-Fail "パスワードは 6 文字以上にしてください。"
  exit 1
}

# ------------------------------------------------------- apiKey を読み取る --
$RepoRoot  = Split-Path -Parent $PSScriptRoot
$IndexPath = Join-Path $RepoRoot "index.html"
if (-not (Test-Path $IndexPath)) {
  Write-Fail "index.html が見つかりません: $IndexPath"
  exit 1
}
$index = Get-Content $IndexPath -Raw -Encoding UTF8
$m = [Regex]::Match($index, 'apiKey:\s*"([^"]+)"')
if (-not $m.Success) {
  Write-Fail "index.html から apiKey を読み取れませんでした。先に tools\setup.ps1 を実行してください。"
  exit 1
}
$apiKey = $m.Groups[1].Value

$p = [Regex]::Match($index, 'projectId:\s*"([^"]+)"')
$projectId = if ($p.Success) { $p.Groups[1].Value } else { "(不明)" }

Write-Host ""
Write-Host "閲覧専用アカウントを登録します" -ForegroundColor Cyan
Write-Info "プロジェクト: $projectId"
Write-Info "アドレス    : $Email"

# ------------------------------------------------------------------ 登録 --
$signUpUri = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey"
$signInUri = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey"
$payload   = @{ email = $Email; password = $Password; returnSecureToken = $true } | ConvertTo-Json -Compress

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

$created = $false
try {
  Invoke-RestMethod -Method Post -Uri $signUpUri -ContentType "application/json; charset=utf-8" -Body $payload -ErrorAction Stop | Out-Null
  $created = $true
  Write-Ok "登録しました"
} catch {
  $reason = Get-ErrorReason $_
  if ($reason -like "EMAIL_EXISTS*") {
    try {
      Invoke-RestMethod -Method Post -Uri $signInUri -ContentType "application/json; charset=utf-8" -Body $payload -ErrorAction Stop | Out-Null
      Write-Ok "すでに登録済みで、このパスワードでログインできました"
    } catch {
      Write-Fail "同じアドレスのアカウントがありますが、パスワードが一致しません。"
      Write-Info "コンソールでパスワードを変更するか、別のアドレスを -Email で指定してください。"
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

# ------------------------------------------------------------ 結果の表示 --
Write-Host ""
Write-Host "── ここから下をコミュニケーションアプリ側に渡してください ──" -ForegroundColor Yellow
Write-Host ""
Write-Host "  アドレス   : $Email"
Write-Host "  パスワード : $Password"
Write-Host ""
Write-Host "── ここまで ──────────────────────────────" -ForegroundColor Yellow
Write-Host ""
if ($created) {
  Write-Info "パスワードはここにしか表示されません。控えておいてください。"
  Write-Info "忘れた場合は -Password で指定して、コンソールから変更してください。"
}
Write-Info "このアカウントは読むことしかできません。"
Write-Info "書き込みは firestore.rules で店舗アカウント（fm+数字）だけに限定しています。"
Write-Host ""
