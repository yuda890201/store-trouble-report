# 現場トラブル・不具合クイック報告

店舗現場のトラブル・不具合を、スマートフォンの片手操作で手早く報告するための単一ページアプリです。

- 起動時に店舗共通PINで認証（照合は Firebase Authentication のサーバー側）
- 対象区分 → カテゴリ → 症状 → 詳細の4ステップ。症状を選ぶとコメントが自動で埋まるので、最短4タップで送信できます
- 写真はカメラ起動またはアルバムから選び、ブラウザ側で圧縮してプレビュー
- 送信内容は Firestore の `trouble_reports` コレクションに保存し、直近20件をリアルタイムで一覧表示
- ホーム画面に追加できる PWA（`manifest.json` / `icon-192.png` / `icon-512.png`）

## ファイル

| ファイル | 内容 |
| --- | --- |
| `index.html` | アプリ本体。UI・ロジック・スタイルをすべて含みます |
| `manifest.json` | PWA マニフェスト |
| `icon-192.png` / `icon-512.png` | PWA アイコン（`any` / `maskable` 兼用） |
| `apple-touch-icon.png` | iOS ホーム画面用アイコン |
| `favicon-32.png` | ブラウザタブ用アイコン |

## セットアップ

### 1. Firebase プロジェクトを用意する

1. [Firebase コンソール](https://console.firebase.google.com/) でプロジェクトを作成します。
2. **Authentication** を開き、ログイン方法で「メール / パスワード」を有効にします。
3. **Firestore Database** を作成します（本番モードで構いません。ルールは後述）。

### 2. 店舗共通アカウントを作る

Authentication の「ユーザーを追加」から、店舗共通アカウントを1件作成します。

- メールアドレス: 任意（例 `store@example.com`）
- パスワード: `store-pin-` + **PIN**

PIN が `8902` なら、パスワードは `store-pin-8902` です。

> Firebase のパスワードは6文字以上が必須のため、PIN をそのままパスワードにはできません。
> `index.html` の `PIN_PREFIX` を前置して6文字以上にしています。
> **PIN 自体はコードのどこにも書きません。** 画面で入力された PIN から組み立てたパスワードを
> Firebase に送り、合っているかどうかの判定は Firebase のサーバー側だけで行われます。

### 3. `index.html` に設定値を入れる

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
| `HISTORY_LIMIT` | `20` | 履歴に表示する件数 |
| `PHOTO_MAX_CHARS` | `700000` | 写真データの上限。Firestore の1ドキュメント上限に対する安全圏 |

### 4. Firestore セキュリティルール

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
                    && request.resource.data.comment.size() < 2000;
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
| `photo_data` | string | 圧縮済み写真の Base64 データURL。未添付なら空文字 |
| `comment` | string | トラブル詳細（必須） |
| `report_time` | string | 発生・報告日時（必須、`datetime-local` の値） |
| `webhook_endpoint` | string | 設定画面で登録した通知先URL |
| `status` | string | 対応状況。作成時は `未対応` |
| `reporter_uid` | string | 送信した端末の Firebase Auth UID |
| `created_at` | timestamp | サーバー時刻 |

履歴カードのステータスバッジは `status` を表示します。`未対応` / `対応中` / `完了` に色が付きます。
値の変更はアプリからは行わないので、Firebase コンソールか別の管理画面から更新してください。

## 通知先 Webhook について

設定画面（ヘッダー右上の歯車）で登録した URL は、この端末の `localStorage` に保存され、
報告ごとに `webhook_endpoint` として一緒に記録されます。
送信成功後にその URL へ直接 POST も試みますが、**これはブラウザからのリクエストなので
通知先が CORS を許可している場合しか届きません**（Discord の Webhook は届き、Slack は届きません）。

確実に通知したい場合は、`trouble_reports` への書き込みをトリガーにした Cloud Functions から
`webhook_endpoint` 宛に送るようにしてください。アプリ側の直接 POST は失敗しても
報告の保存には影響しません。

## 動作環境

iOS Safari / Android Chrome の最新版を想定しています。
Tailwind CSS と Font Awesome を CDN から読み込むため、初回表示にはネットワーク接続が必要です。
