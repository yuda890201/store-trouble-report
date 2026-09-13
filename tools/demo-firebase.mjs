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

let nextId = 1;
const newId = () => "demo-" + nextId++;

const store = [
  {
    __id: newId(),
    target_type: "自作・業務アプリ", category: "入力・保存",
    quick_trouble_preset: "保存できない",
    reporter: "田中", store_name: "みなと店", photo_data: "",
    comment: "保存できません。\n営業に支障あり\n今も続いている",
    report_time: localValue(38), webhook_endpoint: "",
    status: "対応中", reporter_uid: "demo", created_at: minutesAgo(36),
  },
  {
    __id: newId(),
    target_type: "自作・業務アプリ", category: "動作・その他",
    quick_trouble_preset: "固まる",
    reporter: "佐藤", store_name: "みなと店", photo_data: "",
    comment: "画面が固まって操作できません。\n毎回起きる",
    report_time: localValue(190), webhook_endpoint: "",
    status: "未対応", reporter_uid: "demo", created_at: minutesAgo(188),
  },
  {
    __id: newId(),
    target_type: "店舗設備・什器", category: "店舗設備・什器",
    quick_trouble_preset: "",
    reporter: "田中", store_name: "みなと店", photo_data: "",
    comment: "3番レジのレシートが詰まって出力できません。\n業者へ連絡済み",
    report_time: localValue(1500), webhook_endpoint: "",
    status: "完了", reporter_uid: "demo", created_at: minutesAgo(1495),
  },
];

let listener = null, user = null, authCb = null;

function emit() {
  if (!listener) return;
  listener({
    docs: store.map((d) => ({
      id: d.__id,
      data: () => { const { __id, ...rest } = d; return rest; },
    })),
  });
}

/* ---- Authentication ---- */
export const initializeApp = () => ({});
export const getAuth = () => ({ get currentUser() { return user; } });
export const browserLocalPersistence = "local";
export const setPersistence = async () => {};
export const signInWithEmailAndPassword = async (_a, email) => {
  user = { uid: "demo-uid", email };          // デモなので PIN は何でも通す
  if (authCb) authCb(user);
};
export const signOut = async () => { user = null; if (authCb) authCb(null); };
export const onAuthStateChanged = (_a, cb) => { authCb = cb; cb(user); return () => { authCb = null; }; };

/* ---- Firestore ---- */
export const getFirestore = () => ({});
export const collection = () => ({});
export const doc = (_db, _collection, id) => ({ id });
export const query = () => ({});
export const orderBy = () => ({});
export const limit = () => ({});
export const serverTimestamp = () => minutesAgo(0);
export const addDoc = async (_c, data) => {
  const id = newId();
  store.unshift({ __id: id, ...data });
  emit();
  return { id };
};
export const updateDoc = async (ref, patch) => {
  const target = store.find((d) => d.__id === ref.id);
  if (target) Object.assign(target, patch);
  emit();
};
export const onSnapshot = (_q, next) => { listener = next; emit(); return () => { listener = null; }; };
