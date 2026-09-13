/*
 * デモ用のダミーバックエンド。
 * 本物の Firebase SDK と同じ名前だけを揃えたブラウザ内の置き換えで、
 * 外部にはいっさい通信しない。demo.html からのみ読み込まれる。
 */
const minutesAgo = (m) => ({ toDate: () => new Date(Date.now() - m * 60000) });
const localValue = (m) => {
  const d = new Date(Date.now() - m * 60000 - new Date().getTimezoneOffset() * 60000);
  return d.toISOString().slice(0, 16);
};

const store = [
  {
    target_type: "店舗設備・什器", category: "フライヤー・厨房",
    quick_trouble_preset: "油温が上がらない", photo_data: "",
    comment: "2番フライヤーの油温が160℃までしか上がりません。\n営業に支障あり\n使用停止中",
    report_time: localValue(38), webhook_endpoint: "",
    status: "対応中", reporter_uid: "demo", created_at: minutesAgo(36),
  },
  {
    target_type: "自作・業務アプリ", category: "アプリ不具合",
    quick_trouble_preset: "画面フリーズ・操作不能", photo_data: "",
    comment: "発注アプリの一覧画面がフリーズし、操作を受け付けません。\n再現性あり",
    report_time: localValue(190), webhook_endpoint: "",
    status: "未対応", reporter_uid: "demo", created_at: minutesAgo(188),
  },
  {
    target_type: "店舗設備・什器", category: "レジ・POS",
    quick_trouble_preset: "ラベル・レシート詰まり", photo_data: "",
    comment: "3番レジのレシートが詰まって出力できません。\n応急処置で継続中",
    report_time: localValue(1500), webhook_endpoint: "",
    status: "完了", reporter_uid: "demo", created_at: minutesAgo(1495),
  },
];

let listener = null, user = null, authCb = null;

export const initializeApp = () => ({});
export const getAuth = () => ({ get currentUser() { return user; } });
export const browserLocalPersistence = "local";
export const setPersistence = async () => {};
export const signInWithEmailAndPassword = async (_a, email) => {
  // デモなので PIN は何でも通す
  user = { uid: "demo-uid", email };
  if (authCb) authCb(user);
};
export const signOut = async () => { user = null; if (authCb) authCb(null); };
export const onAuthStateChanged = (_a, cb) => { authCb = cb; cb(user); return () => { authCb = null; }; };

export const getFirestore = () => ({});
export const collection = () => ({});
export const query = () => ({});
export const orderBy = () => ({});
export const limit = () => ({});
export const serverTimestamp = () => minutesAgo(0);

export const addDoc = async (_c, data) => { store.unshift(data); emit(); return { id: String(store.length) }; };
export const onSnapshot = (_q, next) => { listener = next; emit(); return () => { listener = null; }; };

function emit() {
  if (listener) listener({ docs: store.map((d) => ({ data: () => d })) });
}
