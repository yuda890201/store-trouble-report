<#
.SYNOPSIS
  「現場トラブル・不具合クイック報告」の Firebase まわりを一括で設定します。

.DESCRIPTION
  次の作業をまとめて行います。途中で人の操作が要るところは、
  その場で案内を出して止まります。

    1. 必要なツール（Node.js / Git / Firebase CLI）の確認とインストール
    2. Firebase へのログイン
    3. 使用するプロジェクトの選択（または新規作成）
    4. ウェブアプリの登録と設定値の取得
    5. index.html への設定値の書き込み
    6. Firestore の作成とリージョンの確認、ルールの適用
    7. 店舗のアカウントの作成（店舗コードを入力します）
    8. コミットして push（GitHub Pages へ自動デプロイ）

  何度実行しても問題ありません。すでに済んでいる手順は飛ばします。

.PARAMETER ProjectId
  使用する Firebase プロジェクトの ID。省略すると一覧から選べます。

.PARAMETER Location
  Firestore を作成するリージョン。既定は asia-northeast1（東京）です。

.PARAMETER SkipPush
  指定すると、コミットと push を行いません。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\setup.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\setup.ps1 -ProjectId my-project

.NOTES
  店舗コードはこのスクリプトにもリポジトリにも保存されません。
  入力された内容を Firebase に送るだけです。
#>
[CmdletBinding()]
param(
  [string]$ProjectId,
  [string]$Location = "asia-northeast1",
  [switch]$SkipPush
)

# native コマンド（firebase / git / npm）は進捗表示を stderr に出す。
# $ErrorActionPreference = "Stop" のままそれをリダイレクトすると、PowerShell は
# その出力を NativeCommandError という致命的エラーに変えてしまう。
# ここでは各コマンドの終了コードを自分で見ているので Continue にしておく。
$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
# PowerShell 5.1 の既定は TLS 1.0 のことがあり、そのままでは Google の API に繋がらない
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# ------------------------------------------------------------------ 表示 --
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

function Stop-WithGuide {
  param([string]$Title, [string[]]$Lines)
  Write-Host ""
  Write-Host "── ここから先は手作業が必要です ──────────────" -ForegroundColor Yellow
  Write-Host $Title -ForegroundColor Yellow
  foreach ($l in $Lines) { Write-Host "  $l" }
  Write-Host ""
  Write-Host "終わったら、このスクリプトをもう一度実行してください。" -ForegroundColor Yellow
  Write-Host "すでに終わった手順は自動で飛ばします。" -ForegroundColor Yellow
  exit 1
}

# ------------------------------------------------------------ ヘルパー --
function Test-Command {
  param([string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Sync-Path {
  # winget / npm -g の直後は PATH が古いままなので取り直す
  $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $user    = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = @($machine, $user, "$env:APPDATA\npm") -join ";"
}

function Show-FirebaseDebugLog {
  # firebase-debug.log はカレントディレクトリに書かれる
  $candidates = @((Join-Path (Get-Location) "firebase-debug.log"),
                  (Join-Path $RepoRoot "firebase-debug.log"))
  $log = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $log) { return }
  $tail = Get-Content $log -Tail 60
  $messages = @()
  foreach ($line in $tail) {
    foreach ($m in [Regex]::Matches($line, '"message"\s*:\s*"((?:[^"\\]|\\.)*)"')) {
      $messages += $m.Groups[1].Value
    }
  }
  if ($messages.Count -gt 0) {
    Write-Host "    Firebase からのエラー内容:" -ForegroundColor Yellow
    foreach ($msg in ($messages | Select-Object -Unique)) {
      Write-Host ("      " + $msg) -ForegroundColor Yellow
    }
  }
  Write-Host ("    詳しくは " + $log) -ForegroundColor DarkGray
}

function Invoke-FirebaseJson {
  param([string[]]$FbArgs)
  $raw = & firebase @FbArgs --json 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  $text = ($raw | Out-String).Trim()
  if (-not $text) { return $null }
  # CLI が JSON の前に案内文を出すことがあるので、最初の { から読む
  $at = $text.IndexOf("{")
  if ($at -lt 0) { return $null }
  try { return ($text.Substring($at) | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Get-IdentityToolkitError {
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

# ------------------------------------------------------------ リポジトリ --
$RepoRoot = Split-Path -Parent $PSScriptRoot
$IndexPath = Join-Path $RepoRoot "index.html"
if (-not (Test-Path $IndexPath)) {
  Write-Fail "index.html が見つかりません: $IndexPath"
  Write-Info "このスクリプトはリポジトリ内の tools\setup.ps1 として実行してください。"
  exit 1
}

Write-Host ""
Write-Host "現場トラブル・不具合クイック報告 — セットアップ" -ForegroundColor White
Write-Host "リポジトリ: $RepoRoot" -ForegroundColor Gray

# =========================================================== 1. ツール --
Write-Step "必要なツールを確認します"

if (-not (Test-Command "node")) {
  Write-Warn2 "Node.js が見つかりません。インストールします。"
  if (Test-Command "winget") {
    winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-source-agreements --accept-package-agreements
    Sync-Path
  }
  if (-not (Test-Command "node")) {
    Stop-WithGuide "Node.js を入れてください。" @(
      "https://nodejs.org/ja/download から LTS 版を入れてください。",
      "インストール後は PowerShell を開き直してください。"
    )
  }
}
Write-Ok ("Node.js {0}" -f (node --version))

if (-not (Test-Command "git")) {
  Write-Warn2 "Git が見つかりません。インストールします。"
  if (Test-Command "winget") {
    winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
    Sync-Path
  }
  if (-not (Test-Command "git")) {
    Stop-WithGuide "Git を入れてください。" @(
      "https://git-scm.com/download/win からインストールしてください。",
      "インストール後は PowerShell を開き直してください。"
    )
  }
}
Write-Ok ("Git {0}" -f ((git --version) -replace '^git version ', ''))

if (-not (Test-Command "firebase")) {
  Write-Info "Firebase CLI を入れます（少し時間がかかります）…"
  npm install -g firebase-tools
  Sync-Path
  if (-not (Test-Command "firebase")) {
    Stop-WithGuide "Firebase CLI を入れてください。" @(
      "PowerShell で次を実行してください:",
      "    npm install -g firebase-tools",
      "終わったら PowerShell を開き直してください。"
    )
  }
}
Write-Ok ("Firebase CLI {0}" -f ((firebase --version) | Select-Object -First 1))

# =========================================================== 2. ログイン --
Write-Step "Firebase にログインします"
$who = (& firebase login:list 2>$null | Out-String)
if (-not $who -or $who -match "No authorized accounts|ログインしていません") {
  Write-Info "ブラウザが開きます。Google アカウントで許可してください。"
  firebase login
  if ($LASTEXITCODE -ne 0) { Write-Fail "ログインに失敗しました。"; exit 1 }
}
Write-Ok "ログイン済みです"

# ======================================================== 3. プロジェクト --
Write-Step "Firebase プロジェクトを決めます"
# Google Cloud のプロジェクト表示名は ASCII しか受け付けない
# （英数字・ハイフン・スペース・アポストロフィ・感嘆符のみ）。日本語は 400 で弾かれる。
$DISPLAY_NAME = "Store Trouble Report"

function New-FirebaseProject {
  param([string]$NewId)
  if ($NewId -notmatch '^[a-z][a-z0-9-]{4,28}[a-z0-9]$') {
    Write-Fail "プロジェクトIDの形式が正しくありません: $NewId"
    Write-Info "英小文字で始まり、英小文字・数字・ハイフンのみ、6〜30文字で、末尾はハイフン以外です。"
    return $false
  }
  firebase projects:create $NewId --display-name $DISPLAY_NAME
  if ($LASTEXITCODE -ne 0) {
    Write-Fail "プロジェクトを作成できませんでした。"
    Show-FirebaseDebugLog
    Write-Info "ID が他の人に使われている場合は、別の ID でやり直してください。"
    Write-Info "コンソールから作ることもできます: https://console.firebase.google.com/"
    return $false
  }
  return $true
}

$usingExisting = [bool]$ProjectId     # -ProjectId で渡された場合も既存とみなす

if (-not $ProjectId) {
  $list = Invoke-FirebaseJson @("projects:list")
  $projects = @()
  if ($list -and $list.result) { $projects = @($list.result) }

  if ($projects.Count -gt 0) {
    Write-Host "    使えるプロジェクト:"
    for ($i = 0; $i -lt $projects.Count; $i++) {
      Write-Host ("      {0}) {1}  ({2})" -f ($i + 1), $projects[$i].projectId, $projects[$i].displayName)
    }
    Write-Host ("      n) 新しく作る（推奨）")
    $pick = Read-Host "    番号を入力してください"
    if ($pick -eq "n") {
      $newId = Read-Host "    新しいプロジェクトID（英小文字・数字・ハイフン、6〜30文字）"
      if (-not (New-FirebaseProject $newId)) { exit 1 }
      $ProjectId = $newId
    } else {
      $idx = 0
      if (-not [int]::TryParse($pick, [ref]$idx) -or $idx -lt 1 -or $idx -gt $projects.Count) {
        Write-Fail "番号が正しくありません。"; exit 1
      }
      $ProjectId = $projects[$idx - 1].projectId
      $usingExisting = $true
    }
  } else {
    $newId = Read-Host "    プロジェクトが1つもありません。新しいID（英小文字・数字・ハイフン、6〜30文字）"
    if (-not (New-FirebaseProject $newId)) { exit 1 }
    $ProjectId = $newId
  }
}

# 既存プロジェクトに入れると、そこで動いている別アプリを壊しうる
if ($usingExisting) {
  Write-Host ""
  Write-Warn2 "既存のプロジェクト「$ProjectId」を選びました。"
  Write-Info "このあと Firestore のルールを、このリポジトリの内容で置き換えます。"
  Write-Info "trouble_reports 以外へのアクセスを拒否する設定が入っているため、同じプロジェクトで"
  Write-Info "動いている別のアプリがあると、そのアプリがデータを読み書きできなくなります。"
  $answer = Read-Host "    それでも続けますか？ 続ける場合は yes と入力してください"
  if ($answer -ne "yes") {
    Write-Info "中止しました。新しいプロジェクトを作る場合は、もう一度実行して n を選んでください。"
    exit 1
  }
}
Write-Ok "プロジェクト: $ProjectId"

# .firebaserc を書いておくと、以降 --project を省ける
$firebaserc = Join-Path $RepoRoot ".firebaserc"
$rcJson = @{ projects = @{ default = $ProjectId } } | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText($firebaserc, $rcJson, (New-Object Text.UTF8Encoding($false)))
Write-Info ".firebaserc を書きました"

# ========================================================= 4. ウェブアプリ --
Write-Step "ウェブアプリを登録して設定値を取り出します"
function Get-WebApps {
  param([string]$Project)
  $res = Invoke-FirebaseJson @("apps:list", "WEB", "--project", $Project)
  if (-not $res -or -not $res.result) { return @() }
  # 古い CLI は platform を返さないことがあるので、あるときだけ絞る
  return @($res.result | Where-Object { -not $_.platform -or $_.platform -eq "WEB" })
}

$webApps = Get-WebApps $ProjectId
if ($webApps.Count -eq 0) {
  Write-Info "ウェブアプリがないので作ります…"
  firebase apps:create WEB $DISPLAY_NAME --project $ProjectId
  if ($LASTEXITCODE -ne 0) {
    Write-Fail "ウェブアプリを作成できませんでした。"
    Show-FirebaseDebugLog
    exit 1
  }
  $webApps = Get-WebApps $ProjectId
}
if ($webApps.Count -eq 0) { Write-Fail "ウェブアプリを取得できませんでした。"; exit 1 }
$appId = $webApps[0].appId
Write-Ok "ウェブアプリ: $appId"

$sdk = Invoke-FirebaseJson @("apps:sdkconfig", "WEB", $appId, "--project", $ProjectId)
$cfg = $null
if ($sdk -and $sdk.result) {
  if ($sdk.result.sdkConfig) { $cfg = $sdk.result.sdkConfig }   # 新しい CLI
  elseif ($sdk.result.apiKey) { $cfg = $sdk.result }            # 古い CLI
}
if (-not $cfg -or -not $cfg.apiKey) {
  Write-Fail "設定値を取得できませんでした。"
  Write-Info "次を手で実行して、出てきた値を index.html に貼ってください:"
  Write-Info "    firebase apps:sdkconfig WEB $appId --project $ProjectId"
  exit 1
}
Write-Ok "設定値を取得しました（projectId: $($cfg.projectId)）"

# ============================================== 5. index.html に書き込む --
Write-Step "index.html に設定値を書き込みます"

$storageBucket = $cfg.storageBucket
if (-not $storageBucket) { $storageBucket = "$ProjectId.firebasestorage.app" }

$block = @"
/* === FIREBASE_CONFIG_START === */
const FIREBASE_CONFIG = {
  apiKey:            "$($cfg.apiKey)",
  authDomain:        "$($cfg.authDomain)",
  projectId:         "$($cfg.projectId)",
  storageBucket:     "$storageBucket",
  messagingSenderId: "$($cfg.messagingSenderId)",
  appId:             "$($cfg.appId)"
};
/* === FIREBASE_CONFIG_END === */

// アカウントは店舗ごとに Firebase Authentication へ登録する。
// メールアドレスもパスワードもこのコードには持たない。照合は Firebase 側で行われる。
"@

$html = [IO.File]::ReadAllText($IndexPath)
$startMark = "/* === FIREBASE_CONFIG_START === */"
$endMark   = "/* === FIREBASE_CONFIG_END === */"
$from = $html.IndexOf($startMark)
$to   = $html.IndexOf($endMark)
if ($from -lt 0 -or $to -lt 0 -or $to -lt $from) {
  Write-Fail "index.html に設定ブロックのマーカーが見つかりません。"
  Write-Info "FIREBASE_CONFIG_START / FIREBASE_CONFIG_END のコメント行を消していないか確認してください。"
  exit 1
}
$html = $html.Substring(0, $from) + $block.TrimEnd() + $html.Substring($to + $endMark.Length)
[IO.File]::WriteAllText($IndexPath, $html, (New-Object Text.UTF8Encoding($false)))
Write-Ok "index.html を更新しました"
Write-Info "apiKey は公開されても問題ない値です。実際の防御は次のルールです。"

# ========================================================== 6. Firestore --
Write-Step "Firestore を用意します"

function Get-FirestoreRegion {
  param([string]$Project)
  $res = Invoke-FirebaseJson @("firestore:databases:list", "--project", $Project)
  if (-not $res -or -not $res.result) { return $null }
  foreach ($d in @($res.result)) {
    $name = [string]$d.name
    if ($name -and ($name -like "*/(default)")) {
      if ($d.locationId) { return [string]$d.locationId }
      if ($d.location)   { return [string]$d.location }
    }
  }
  return $null
}

function New-FirestoreDatabase {
  param([string]$Project, [string]$Region)
  Write-Info "Firestore のデータベースを $Region に作ります…"
  firebase firestore:databases:create "(default)" --location $Region --project $Project
  return ($LASTEXITCODE -eq 0)
}

$region = Get-FirestoreRegion $ProjectId

if (-not $region) {
  # 先に自分で作る。firebase deploy に任せると、リージョンを選べないまま既定値で作られる。
  if (-not (New-FirestoreDatabase $ProjectId $Location)) {
    Write-Warn2 "CLI からデータベースを作成できませんでした。"
    Show-FirebaseDebugLog
    Stop-WithGuide "Firestore をコンソールで作ってください。" @(
      "    https://console.firebase.google.com/project/$ProjectId/firestore",
      "",
      "  「データベースの作成」→ 本番環境モード → ロケーション $Location",
      "",
      "  ロケーションは後から変更できません。ここで $Location を選んでください。"
    )
  }
  $region = Get-FirestoreRegion $ProjectId
}

if (-not $region) {
  Write-Warn2 "リージョンを確認できませんでした（CLI が対応していない可能性があります）"
  Write-Info "コンソールで確認してください: https://console.firebase.google.com/project/$ProjectId/firestore"
} elseif ($region -eq $Location) {
  Write-Ok "Firestore リージョン: $region"
} else {
  Write-Host ""
  Write-Warn2 "Firestore のリージョンが $region です（想定は $Location）。"
  Write-Info "日本から使うアプリなので、$Location でないと毎回の読み書きに往復の遅延が乗ります。"
  Write-Info "リージョンは後から変更できません。変えるにはデータベースを作り直すしかなく、"
  Write-Info "そのとき入っているデータはすべて失われます。"
  $answer = Read-Host "    $Location で作り直しますか？ 作り直す場合は recreate と入力（このまま使う場合は Enter）"
  if ($answer -eq "recreate") {
    Write-Info "いまのデータベースを削除します…"
    firebase firestore:databases:delete "(default)" --project $ProjectId --force
    if ($LASTEXITCODE -ne 0) {
      Write-Warn2 "削除できませんでした。"
      Show-FirebaseDebugLog
      Stop-WithGuide "コンソールから作り直してください。" @(
        "    https://console.firebase.google.com/project/$ProjectId/firestore",
        "",
        "  データベースを削除してから、ロケーション $Location で作り直してください。"
      )
    }
    if (-not (New-FirestoreDatabase $ProjectId $Location)) {
      Write-Fail "作り直せませんでした。"
      Show-FirebaseDebugLog
      exit 1
    }
    $region = Get-FirestoreRegion $ProjectId
    Write-Ok "Firestore リージョン: $region"
  } else {
    Write-Info "$region のまま進みます。"
  }
}

firebase deploy --only firestore:rules --project $ProjectId
if ($LASTEXITCODE -eq 0) {
  Write-Ok "Firestore ルールを適用しました"
} else {
  Write-Fail "Firestore ルールを適用できませんでした"
  Show-FirebaseDebugLog
  exit 1
}

# ==================================================== 7. 店舗アカウント --
Write-Step "店舗のアカウントを用意します"
Write-Info "店舗コード（fm + 数字）を1つ登録します。店舗の数だけ繰り返し実行してください。"
Write-Info "コンソールからでも追加できます:"
Write-Info "  https://console.firebase.google.com/project/$ProjectId/authentication/users"

$digits = (Read-Host "    店舗コードの数字（3〜8桁。例 0001）").Trim()
if ($digits -notmatch '^[0-9]{3,8}$') {
  Write-Fail "3〜8桁の数字で入力してください: $digits"
  exit 1
}

# アプリと同じ組み立て方。画面では fm+数字 だけを入力させる。
$storeCode  = "fm$digits"
$loginEmail = "$storeCode@fm.example.com"

Write-Info "登録する内容: $loginEmail（パスワードは店舗コードと同じ）"

$signUpUri = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$($cfg.apiKey)"
$signInUri = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$($cfg.apiKey)"
$payload = @{ email = $loginEmail; password = $storeCode; returnSecureToken = $true } | ConvertTo-Json -Compress

try {
  Invoke-RestMethod -Method Post -Uri $signUpUri -ContentType "application/json; charset=utf-8" -Body $payload -ErrorAction Stop | Out-Null
  Write-Ok "店舗コード $storeCode を登録しました"
} catch {
  $reason = Get-IdentityToolkitError $_
  if ($reason -like "EMAIL_EXISTS*") {
    try {
      Invoke-RestMethod -Method Post -Uri $signInUri -ContentType "application/json; charset=utf-8" -Body $payload -ErrorAction Stop | Out-Null
      Write-Ok "店舗コード $storeCode は既に登録済みです"
    } catch {
      Stop-WithGuide "同じアドレスのアカウントがありますが、パスワードが一致しません。" @(
        "コンソールで $loginEmail のパスワードを $storeCode に変更してください。",
        "",
        "    https://console.firebase.google.com/project/$ProjectId/authentication/users"
      )
    }
  } elseif ($reason -like "OPERATION_NOT_ALLOWED*" -or $reason -like "*ADMIN_ONLY_OPERATION*") {
    Stop-WithGuide "メール／パスワードのログイン方法が有効になっていません。" @(
      "次のページで有効にしてください。",
      "",
      "    https://console.firebase.google.com/project/$ProjectId/authentication/providers",
      "",
      "  「メール / パスワード」を選び、上のトグルを有効にして保存してください。",
      "  （下の「メールリンク」は無効のままで構いません）"
    )
  } else {
    Write-Fail "登録できませんでした: $reason"
    exit 1
  }
}

# ================================================== 8. コミットして push --
if ($SkipPush) {
  Write-Step "コミットと push は -SkipPush が指定されたので行いません"
} else {
  Write-Step "変更をコミットして push します"
  Push-Location $RepoRoot
  try {
    $changed = & git status --porcelain
    if ([string]::IsNullOrWhiteSpace(($changed | Out-String))) {
      Write-Ok "変更はありません（既に反映済みです）"
    } else {
      git add index.html .firebaserc
      git commit -m "Firebase の設定値を追加"
      if ($LASTEXITCODE -ne 0) { Write-Warn2 "コミットするものがありませんでした" }
      $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
      git push origin $branch
      if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "push に失敗しました。手動で 'git push origin $branch' を実行してください。"
      } else {
        Write-Ok "push しました（branch: $branch）"
        if ($branch -eq "main") {
          Write-Info "GitHub Actions が GitHub Pages へ自動デプロイします（1〜2分）。"
        } else {
          Write-Info "main 以外のブランチです。公開するには main にマージしてください。"
        }
      }
    }
  } finally {
    Pop-Location
  }
}

# ------------------------------------------------------------------ 完了 --
Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host " セットアップが完了しました" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host ""
Write-Host " アプリ    : https://yuda890201.github.io/store-trouble-report/"
Write-Host " デモ版    : https://yuda890201.github.io/store-trouble-report/demo.html"
Write-Host " コンソール: https://console.firebase.google.com/project/$ProjectId/overview"
Write-Host ""
Write-Host " ログインは、登録した店舗コード（fm + 数字）で行います。" -ForegroundColor Gray
Write-Host " 店舗コードはこのリポジトリにもスクリプトにも保存されていません。" -ForegroundColor Gray
Write-Host ""
