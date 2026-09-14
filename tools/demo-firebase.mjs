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

// 「写真を見る」を試せるように 1 枚だけ用意しておく（レシートの紙詰まりの写真のつもり）
const DEMO_PHOTO = "data:image/jpeg;base64,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AEIUy0/49IP+ua/yq1sZktFFFMAooooAKKKKACiiigAqt4e/48X/AOuh/kKs1W8Pf8eL/wDXQ/yFHQDVoooqRhRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAUdZ/5Bc3/Af/AEIUy0/49IP+ua/yp+s/8gub/gP/AKEKZaf8ekH/AFzX+VNbCJaKKKYBRRRQAUUUUAFFFFABWZb22o2sZSGeJVJyRjPP4itOigCjjVv+fqL/AL5H/wATRjVv+fqL/vkf/E1eooAo41b/AJ+ov++R/wDE0Y1b/n6i/wC+R/8AE1eooAo41b/n6i/75H/xNGNW/wCfqL/vkf8AxNXqKAKONW/5+ov++R/8TRjVv+fqL/vkf/E1eooAo41b/n6i/wC+R/8AE0Y1b/n6i/75H/xNXqKAKONW/wCfqL/vkf8AxNGNW/5+ov8Avkf/ABNXqKAKONW/5+ov++R/8TRjVv8An6i/75H/AMTV6igCjjVv+fqL/vkf/E0Y1b/n6i/75H/xNXqKAKONW/5+ov8Avkf/ABNGNW/5+ov++R/8TV6igCjjVv8An6i/75H/AMTRjVv+fqL/AL5H/wATV6igCjjVv+fqL/vkf/E0Y1b/AJ+ov++R/wDE1eooAo41b/n6i/75H/xNGNW/5+ov++R/8TV6igCjjVv+fqL/AL5H/wATRjVv+fqL/vkf/E1eooAo41b/AJ+ov++R/wDE0Y1b/n6i/wC+R/8AE1eooAo41b/n6i/75H/xNGNW/wCfqL/vkf8AxNXqKAKONW/5+ov++R/8TRjVv+fqL/vkf/E1eooAo41b/n6i/wC+R/8AE0Y1b/n6i/75H/xNXqKAKONW/wCfqL/vkf8AxNGNW/5+ov8Avkf/ABNXqKAKONW/5+ov++R/8TRjVv8An6i/75H/AMTV6igCjjVv+fqL/vkf/E0Y1b/n6i/75H/xNXqKAKONW/5+ov8Avkf/ABNGNW/5+ov++R/8TV6igCjjVv8An6i/75H/AMTRjVv+fqL/AL5H/wATV6igCjjVv+fqL/vkf/E0Y1b/AJ+ov++R/wDE1eooAo41b/n6i/75H/xNGNW/5+ov++R/8TV6igDOmg1KeJo5biJkbqMY/pV6BDHBGhxlVAOPpT6KACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA/9k=";

const store = [
  {
    __id: newId(),
    target_type: "自作・業務アプリ", category: "入力・保存",
    quick_trouble_preset: "保存できない",
    reporter: "田中", store_name: "みなと店", has_photo: false,
    comment: "保存できません。\n営業に支障あり\n今も続いている",
    report_time: localValue(38), webhook_endpoint: "",
    status: "対応中", reporter_uid: "demo", created_at: minutesAgo(36),
  },
  {
    __id: newId(),
    target_type: "自作・業務アプリ", category: "動作・その他",
    quick_trouble_preset: "固まる",
    reporter: "佐藤", store_name: "みなと店", has_photo: false,
    comment: "画面が固まって操作できません。\n毎回起きる",
    report_time: localValue(190), webhook_endpoint: "",
    status: "未対応", reporter_uid: "demo", created_at: minutesAgo(188),
  },
  {
    __id: newId(),
    target_type: "店舗設備・什器", category: "店舗設備・什器",
    quick_trouble_preset: "",
    reporter: "田中", store_name: "みなと店", has_photo: true,
    comment: "3番レジのレシートが詰まって出力できません。\n業者へ連絡済み",
    report_time: localValue(1500), webhook_endpoint: "",
    status: "完了", reporter_uid: "demo", created_at: minutesAgo(1495),
  },
];

// 写真の置き場。本物と同じく、報告の ID をそのまま文書 ID に使う。
const photos = new Map([
  ["demo-3", { photo_data: DEMO_PHOTO }],
]);

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
export const collection = (_db, name) => ({ __collection: name });
// doc(collection(db, "x")) は「書く前に ID だけ決める」呼び方。
// doc(db, "x", id) は既存の 1 件を指す呼び方。
export const doc = (dbOrCollection, name, id) =>
  (name === undefined)
    ? { id: newId(), __collection: dbOrCollection.__collection }
    : { id, __collection: name };
export const query = () => ({});
export const orderBy = () => ({});
export const limit = () => ({});
export const serverTimestamp = () => minutesAgo(0);
export const setDoc = async (ref, data) => {
  if (ref.__collection === "trouble_report_photos") { photos.set(ref.id, data); return; }
  store.unshift({ __id: ref.id, ...data });
  emit();
};
export const getDoc = async (ref) => {
  const found = (ref.__collection === "trouble_report_photos")
    ? photos.get(ref.id)
    : store.find((d) => d.__id === ref.id);
  return { exists: () => Boolean(found), data: () => found };
};
export const updateDoc = async (ref, patch) => {
  const target = store.find((d) => d.__id === ref.id);
  if (target) Object.assign(target, patch);
  emit();
};
export const onSnapshot = (_q, next) => { listener = next; emit(); return () => { listener = null; }; };
