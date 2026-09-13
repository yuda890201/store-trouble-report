import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs } from 'firebase/firestore';

const env = await initializeTestEnvironment({
  projectId: 'demo-rules',
  firestore: { host: '127.0.0.1', port: 8181, rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
});

const ok = [], bad = [];
const check = async (name, fn) => { try { await fn(); ok.push(name); } catch (e) { bad.push(name + ' :: ' + e.message.slice(0, 120)); } };

// 店舗アカウントと、コミュニケーションアプリ用の閲覧アカウント
const store  = env.authenticatedContext('u_store',  { email: 'fm0001@fm.example.com' }).firestore();
const store2 = env.authenticatedContext('u_store2', { email: 'fm12345678@fm.example.com' }).firestore();
const viewer = env.authenticatedContext('u_view',   { email: 'viewer@view.example.com' }).firestore();
const spoof  = env.authenticatedContext('u_spoof',  { email: 'fm0001@fm.example.com.evil.com' }).firestore();
const anon   = env.unauthenticatedContext().firestore();

const REPORT = {
  target_type: '自作・業務アプリ', category: '勤怠・シフト', quick_trouble_preset: '保存できない',
  comment: '保存ボタンを押しても戻りません', reporter: 'ゆだ', store_name: 'みなと店',
  photo_data: '', report_time: '2026-09-13T10:30', webhook_endpoint: '',
  status: '未対応', reporter_uid: 'u_store',
};

// 既存データを1件仕込む（ルールを迂回して書く）
await env.withSecurityRulesDisabled(async (c) => {
  await setDoc(doc(c.firestore(), 'trouble_reports/seed'), REPORT);
  await setDoc(doc(c.firestore(), 'secret_stuff/x'), { a: 1 });
});

// --- 店舗アカウントは今までどおり使える ---
await check('店舗は報告を作れる', () => assertSucceeds(setDoc(doc(store, 'trouble_reports/n1'), REPORT)));
await check('8桁の店舗コードも作れる', () => assertSucceeds(setDoc(doc(store2, 'trouble_reports/n2'), REPORT)));
await check('店舗は報告を読める', () => assertSucceeds(getDocs(collection(store, 'trouble_reports'))));
await check('店舗はステータスを変えられる', () => assertSucceeds(
  updateDoc(doc(store, 'trouble_reports/seed'), { status: '対応中', status_updated_at: 'x', status_updated_by: 'ゆだ' })));

// --- 店舗アカウントでも通らないもの ---
await check('本文が空なら作れない', () => assertFails(setDoc(doc(store, 'trouble_reports/n3'), { ...REPORT, comment: '' })));
await check('報告者が空なら作れない', () => assertFails(setDoc(doc(store, 'trouble_reports/n4'), { ...REPORT, reporter: '' })));
await check('本文が長すぎると作れない', () => assertFails(setDoc(doc(store, 'trouble_reports/n5'), { ...REPORT, comment: 'あ'.repeat(2100) })));
await check('本文は書き換えられない', () => assertFails(updateDoc(doc(store, 'trouble_reports/seed'), { comment: '改ざん' })));
await check('知らないステータスにはできない', () => assertFails(updateDoc(doc(store, 'trouble_reports/seed'), { status: '放置' })));
await check('店舗でも削除はできない', () => assertFails(deleteDoc(doc(store, 'trouble_reports/seed'))));
await check('他のコレクションは触れない', () => assertFails(getDoc(doc(store, 'secret_stuff/x'))));

// --- 閲覧アカウント: 読めるが書けない ---
await check('閲覧は一覧を読める',   () => assertSucceeds(getDocs(collection(viewer, 'trouble_reports'))));
await check('閲覧は1件を読める',     () => assertSucceeds(getDoc(doc(viewer, 'trouble_reports/seed'))));
await check('閲覧は報告を作れない', () => assertFails(setDoc(doc(viewer, 'trouble_reports/v1'), REPORT)));
await check('閲覧はステータスを変えられない', () => assertFails(
  updateDoc(doc(viewer, 'trouble_reports/seed'), { status: '完了', status_updated_at: 'x', status_updated_by: 'v' })));
await check('閲覧は削除できない',   () => assertFails(deleteDoc(doc(viewer, 'trouble_reports/seed'))));
await check('閲覧も他のコレクションは触れない', () => assertFails(getDoc(doc(viewer, 'secret_stuff/x'))));

// --- なりすまし・未ログイン ---
await check('似たアドレスでは書けない', () => assertFails(setDoc(doc(spoof, 'trouble_reports/s1'), REPORT)));
await check('未ログインは読めない',     () => assertFails(getDoc(doc(anon, 'trouble_reports/seed'))));
await check('未ログインは書けない',     () => assertFails(setDoc(doc(anon, 'trouble_reports/a1'), REPORT)));

await env.cleanup();
console.log('PASS ' + ok.length);
if (bad.length) { console.log('FAIL ' + bad.length); bad.forEach(b => console.log('  ✗ ' + b)); process.exit(1); }
console.log('ALL GREEN');
