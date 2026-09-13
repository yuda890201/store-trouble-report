/*
 * GitHub Pages 用の公開ファイルを _site に組み立てる。
 * demo.html は index.html から生成するので、UI の変更は index.html だけ直せばよい。
 */
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from "node:fs";

const OUT = "_site";
const ASSETS = [
  "index.html", "manifest.json",
  "icon-192.png", "icon-512.png", "apple-touch-icon.png", "favicon-32.png",
];

mkdirSync(OUT, { recursive: true });
for (const file of ASSETS) copyFileSync(file, `${OUT}/${file}`);
copyFileSync("tools/demo-firebase.mjs", `${OUT}/demo-firebase.mjs`);
writeFileSync(`${OUT}/.nojekyll`, "");

let html = readFileSync("index.html", "utf8");

// 置換漏れに気づかず壊れたデモを公開しないよう、1件でも当たらなければビルドを落とす
function swap(from, to, label) {
  const count = typeof from === "string"
    ? html.split(from).length - 1
    : (html.match(from) || []).length;
  if (count === 0) throw new Error(`build-demo: 置換対象が見つかりません (${label})`);
  html = typeof from === "string" ? html.split(from).join(to) : html.replace(from, to);
}

// 1) Firebase SDK をブラウザ内のダミーに差し替える
swap(
  /https:\/\/www\.gstatic\.com\/firebasejs\/[\d.]+\/firebase-(?:app|auth|firestore)\.js/g,
  "./demo-firebase.mjs",
  "firebase sdk",
);

// 2) 設定済み扱いにして認証画面を通す
// 本番の値が入っていても、デモでは必ずダミーに差し替える
swap(/apiKey:\s+"[^"]*"/,    'apiKey:            "demo"', "apiKey");
swap(/projectId:\s+"[^"]*"/, 'projectId:         "demo"', "projectId");

// 3) デモであることを画面上で分かるようにする
swap(
  "<title>現場トラブル・不具合クイック報告</title>",
  "<title>【デモ】現場トラブル・不具合クイック報告</title>",
  "title",
);
// 案内文は i18n の辞書から出るので、マークアップではなく辞書側を差し替える
swap('login_lead: "店舗コードを入力してください",',
     'login_lead: "デモ版です。数字を3〜8桁入れれば誰でも入れます。内容はどこにも保存されません",',
     "auth hint ja");
swap('login_lead: "Enter your store code",',
     'login_lead: "Demo. Any 3-8 digits will let you in. Nothing is saved anywhere.",',
     "auth hint en");
swap('login_lead: "पसल कोड हाल्नुहोस्",',
     'login_lead: "डेमो। ३-८ अंक हाले पुग्छ। केही पनि सुरक्षित हुँदैन।",',
     "auth hint ne");
swap(
  '<h1 class="flex-1 font-bold text-[15px] text-white leading-tight" data-i18n="app_title">現場トラブル・不具合報告</h1>',
  '<h1 class="flex-1 font-bold text-[15px] text-white leading-tight" data-i18n="app_title">現場トラブル・不具合報告</h1>' +
  '<span class="text-[10px] font-bold bg-black/35 text-white px-2 py-0.5 rounded-full tracking-wide">DEMO</span>',
  "header badge",
);
// デモ版はホーム画面に追加されると紛らわしいので PWA 登録から外す
swap('<link rel="manifest" href="manifest.json">', "", "manifest link");

writeFileSync(`${OUT}/demo.html`, html);
console.log(`built ${OUT}/ (index.html, demo.html, ${ASSETS.length - 1} assets)`);
