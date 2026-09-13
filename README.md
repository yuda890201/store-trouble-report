# 現場トラブル・不具合クイック報告

店舗現場のトラブル・不具合を、スマートフォンの片手操作で手早く報告するための単一ページアプリです。

- 起動時に店舗共通PINで認証（照合は Firebase Authentication のサーバー側）
- 対象区分 → カテゴリ → 症状 → 詳細の4ステップ。症状を選ぶとコメントが自動で埋まります
- 緊急度（至急 / 要対応 / 通常）と報告者を記録。報告者名は端末に覚えて、次回からボタンで選べます
- 写真はカメラ起動またはアルバムから最大4枚。ブラウザ側で圧縮して Cloud Storage に保存します
- 送信内容は Firestore の `trouble_reports` コレクションに保存し、直近50件をリアルタイムで一覧表示
- 履歴のステータスバッジをタップすると 未対応 → 対応中 → 完了 と進みます。ステータス・カテゴリ・緊急度で絞り込めます
- ホーム画面に追加できる PWA（`manifest.json` / `icon-192.png` / `icon-512.png`）

## ファイル

| ファイル | 内容 |
| --- | --- |
| `index.html` | アプリ本体。UI・ロジック・スタイルをすべて含みます |
| `manifest.json` | PWA マニフェスト |
| `icon-192.png` / `icon-512.png` | PWA アイコン（`any` / `maskable` 兼用） |
| `apple-touch-icon.png` | iOS ホーム画面用アイコン |
| `firebase.json` / `firestore.rules` / `storage.rules` | セキュリティルール。`firebase deploy` で適用します |
| `tools/setup.ps1` | Windows 向けの一括セットアップスクリプト |
| `favicon-32.png` | ブラウザタブ用アイコン |

## セットアップ

### かんたんセットアップ（Windows / PowerShell）

`tools/setup.ps1` が下の手順をまとめて実行します。

```powershell
cd path\to\store-trouble-report
powershell -ExecutionPolicy Bypass -File tools\setup.ps1
```

やってくれること:

1. Node.js / Git / Firebase CLI の確認と、足りなければインストール
2. Firebase へのログイン
3. プロジェクトの選択（または新規作成）
4. ウェブアプリの登録と設定値の取得
5. `index.html` への設定値の書き込み
6. Firestore の作成とリージョンの確認、ルールの適用
7. Storage のルールの適用
8. 店舗共通アカウントの作成（PIN はその場で入力します）
9. コミットして push（`main` なら GitHub Pages へ自動デプロイ）

何度実行しても問題ありません。済んでいる手順は飛ばします。
コンソールでの操作が必要になった場合は、その場所の URL を出して止まります。

**Firestore のリージョンは後から変更できません。** スクリプトは作成時に
`asia-northeast1`（東京）を指定し、既にある場合は実際のリージョンを確認します。
想定と違っていた場合は、作り直すかどうかを聞きます（作り直すとデータは失われます）。
別のリージョンにしたい場合は `-Location` で指定してください。

**Storage の作成だけは自動化できません。** Google が課金の同意を人に求めるためです。
2024年以降に作られたプロジェクトでは Storage に Blaze プランが必要で、
スクリプトはコンソールの URL を出して止まります。1回だけの作業です。

**PIN はスクリプトにもリポジトリにも保存されません。** 入力された PIN から
組み立てたパスワードを Firebase に送るだけです。

以下は、スクリプトが何をしているかの説明と、手作業で行う場合の手順です。

### 手作業で行う場合

#### 1. Firebase プロジェクトを用意する

1. [Firebase コンソール](https://console.firebase.google.com/) でプロジェクトを作成します。
2. **Authentication** を開き、ログイン方法で「メール / パスワード」を有効にします。
3. **Firestore Database** を作成します（本番モードで構いません。ルールは後述）。
4. **Storage** を作成します（写真の保存先。ルールは後述）。

#### 2. 店舗共通アカウントを作る

Authentication の「ユーザーを追加」から、店舗共通アカウントを1件作成します。

- メールアドレス: 任意（例 `store@example.com`）
- パスワード: `store-pin-` + **PIN**

PIN が `8902` なら、パスワードは `store-pin-8902` です。

> Firebase のパスワードは6文字以上が必須のため、PIN をそのままパスワードにはできません。
> `index.html` の `PIN_PREFIX` を前置して6文字以上にしています。
> **PIN 自体はコードのどこにも書きません。** 画面で入力された PIN から組み立てたパスワードを
> Firebase に送り、合っているかどうかの判定は Firebase のサーバー側だけで行われます。

#### 3. `index.html` に設定値を入れる

`index.html` の `<script type="module">` 冒頭にある設定ブロックを埋めます。

```js
const FIREBASE_CONFIG = {
  apiKey:            "...",
  authDomain:        "your-project.firebaseapp.com",
  projectId:         "your-project",
  storageBucket:     "your-project.appspot.com",
  messagingSenderId: "...",
  appId:             "..."
};

const STORE_ACCOUNT_EMAIL = "store@example.com";
```

値は Firebase コンソールの「プロジェクトの設定 → マイアプリ → ウェブアプリ」で確認できます。
未設定のまま開くと、認証画面に設定が必要である旨の案内が表示されます。

あわせて変更できる定数:

| 定数 | 既定値 | 意味 |
| --- | --- | --- |
| `PIN_PREFIX` | `store-pin-` | PIN に前置してパスワードにする文字列 |
| `PIN_LENGTH` | `4` | PIN の桁数。この桁数に達すると自動で認証します |
| `HISTORY_LIMIT` | `50` | 履歴に読み込む件数。絞り込みはこの範囲に対して行われます |
| `MAX_PHOTOS` | `4` | 1件の報告に添付できる写真の枚数 |
| `PHOTO_MAX_BYTES` | `1200000` | 圧縮後の1枚あたりの上限 |
| `STORAGE_PREFIX` | `trouble_reports` | Cloud Storage 上の保存先フォルダ |

#### 4. Firestore セキュリティルール

ログイン済みの端末だけが読み書きできるようにします。

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /trouble_reports/{docId} {
      allow read:   if request.auth != null;
      allow create: if request.auth != null
                    && request.resource.data.comment is string
                    && request.resource.data.comment.size() > 0
                    && request.resource.data.comment.size() < 2000
                    && request.resource.data.reporter is string
                    && request.resource.data.reporter.size() > 0
                    && request.resource.data.urgency in ['至急', '要対応', '通常'];

      // 履歴からのステータス変更だけを許可する。本文は書き換えさせない。
      allow update: if request.auth != null
                    && request.resource.data.diff(resource.data).affectedKeys()
                         .hasOnly(['status', 'status_updated_at', 'status_updated_by'])
                    && request.resource.data.status in ['未対応', '対応中', '完了'];

      allow delete: if false;
    }
  }
}
```

#### 5. Storage セキュリティルール

写真の保存先です。Firebase コンソールの Storage → Rules に設定します。

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /trouble_reports/{fileName} {
      allow read:   if request.auth != null;
      allow create: if request.auth != null
                    && request.resource.size < 2 * 1024 * 1024
                    && request.resource.contentType.matches('image/.*');
      allow update, delete: if false;
    }
  }
}
```

## 保存されるデータ

`trouble_reports` の1ドキュメントは次の形です。

| フィールド | 型 | 内容 |
| --- | --- | --- |
| `target_type` | string | 対象区分（必須） |
| `category` | string | カテゴリ（必須） |
| `quick_trouble_preset` | string | 選んだ症状。未選択なら `直接入力` |
| `urgency` | string | 緊急度（必須）。`至急` / `要対応` / `通常` |
| `reporter` | string | 報告者名（必須） |
| `store_name` | string | 設定画面で登録した店舗名 |
| `photos` | array | 添付写真。`{ url, path }` の配列。未添付なら空配列 |
| `comment` | string | トラブル詳細（必須） |
| `report_time` | string | 発生・報告日時（必須、`datetime-local` の値） |
| `webhook_endpoint` | string | 設定画面で登録した通知先URL |
| `status` | string | 対応状況。作成時は `未対応` |
| `status_updated_at` | timestamp | ステータスを最後に変更した時刻 |
| `status_updated_by` | string | ステータスを変更した端末の Firebase Auth UID |
| `reporter_uid` | string | 送信した端末の Firebase Auth UID |
| `created_at` | timestamp | サーバー時刻 |

`reporter_uid` は店舗共通アカウントの UID なので、全員が同じ値になります。
誰が報告したかは `reporter` で判断してください。

履歴カードのステータスバッジをタップすると `未対応` → `対応中` → `完了` の順に変わります。
変更できるのは `status` と付随する2フィールドだけで、報告の本文は書き換えられません（上記ルールで制限しています）。

以前のバージョンは写真を `photo_data` に Base64 で直接持っていました。
その形式の報告も履歴にそのまま表示されます。

## 通知先 Webhook について

設定画面（ヘッダー右上の歯車）で登録した URL は、この端末の `localStorage` に保存され、
報告ごとに `webhook_endpoint` として一緒に記録されます。
送信成功後にその URL へ直接 POST も試みますが、**これはブラウザからのリクエストなので
通知先が CORS を許可している場合しか届きません**（Discord の Webhook は届き、Slack は届きません）。

確実に通知したい場合は、`trouble_reports` への書き込みをトリガーにした Cloud Functions から
`webhook_endpoint` 宛に送るようにしてください。アプリ側の直接 POST は失敗しても
報告の保存には影響しません。

## デプロイ

`main` に push すると GitHub Actions が GitHub Pages に公開します
（`.github/workflows/pages.yml`）。公開されるのは次の2つです。

| URL | 内容 |
| --- | --- |
| `index.html` | 本番版。Firebase の設定値が必要です |
| `demo.html` | デモ版。保存先をブラウザ内のダミーに差し替えたもの |

デモ版は `tools/build-demo.mjs` が `index.html` から生成します。UI を直すときは
`index.html` だけを編集してください。デモ版はファイルとして持っていません。

デモ版は任意の4桁の数字でログインでき、入力内容はブラウザを閉じると消えます。
外部への通信は行いません。ホーム画面に追加されると本番版と紛らわしいため、
マニフェストの link タグは生成時に外しています。

`github-pages` 環境はデフォルトブランチからのデプロイのみを許可しているため、
作業ブランチではビルドの検証だけを行い、公開は `main` に入ったときだけ実行します。
作業ブランチの内容を先に公開したい場合は、リポジトリの Settings → Environments →
`github-pages` で対象ブランチを追加してください。

## 動作環境

iOS Safari / Android Chrome の最新版を想定しています。
Tailwind CSS と Font Awesome を CDN から読み込むため、初回表示にはネットワーク接続が必要です。
