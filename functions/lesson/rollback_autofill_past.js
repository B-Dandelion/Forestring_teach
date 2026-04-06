/**
 * rollback_autofill_past.js
 * - 특정 autoFill 실행(runId 또는 날짜 prefix)로 만들어진 레슨 중
 *   cutoff(KST) 이전(date 기준)의 것들을 싹 삭제
 *
 * 삭제 대상:
 *  1) lessons/{lessonId}
 *  2) users/{studentId}/lessons/{lessonId}
 *  3) availableSlots/{teacherId} 의 bookedSlots.{lessonId} 필드 삭제
 */

const admin = require("firebase-admin");
// 로컬 실행이면 service account 사용
// admin.initializeApp({ credential: admin.credential.cert(require("./serviceAccountKey.json")) });
// Cloud Functions 환경이면 그냥:
admin.initializeApp({
  credential: admin.credential.cert(require("../serviceAccountKey.json")),
});
const db = admin.firestore();

/** ===== 설정 ===== */
// 1) 정확한 runId로 지우는 게 가장 안전함
const RUN_ID_EXACT = "autoFill_2026-01-12_1768206011550";

// 2) 같은 날 여러 번 돌렸을 수 있으면 날짜 prefix로 지우기
const RUN_DAY_PREFIX = "2026-01-12";
// => "autoFill_2026-01-12_" 로 시작하는 runId 전부 스캔

// cutoff: KST 기준 2026-01-12 00:00 이전(date < cutoff)이면 삭제
const CUTOFF_KST_YMD = "2026-01-12";

// 안전장치: 먼저 DRY_RUN=true로 돌려서 확인
const DRY_RUN = false;

// 한 번에 처리할 레슨 수(배치 write 500 제한 고려)
// lesson 1개당 (main delete 1 + sub delete 1) = 2 writes
// teacher bookedSlots 삭제는 teacher별 1 update로 묶을 거라 여유 있음
const CHUNK_SIZE = 180;
/** ===== 설정 끝 ===== */

function kstMidnightToUtcDate(ymd) {
  // ymd: "YYYY-MM-DD" 의 KST 00:00 => UTC 전날 15:00
  const [Y, M, D] = ymd.split("-").map(Number);
  return new Date(Date.UTC(Y, M - 1, D, 0 - 9, 0, 0, 0)); // hh-9
}

async function fetchLessonDocsByRunId() {
  if (RUN_ID_EXACT) {
    const snap = await db.collection("lessons")
      .where("autoFillRunId", "==", RUN_ID_EXACT)
      .get();
    return snap.docs;
  }

  // prefix 스캔(범위 쿼리) + 페이지네이션
  const prefix = `autoFill_${RUN_DAY_PREFIX}_`;
  const end = prefix + "\uf8ff";

  let all = [];
  let last = null;

  while (true) {
    let q = db.collection("lessons")
      .orderBy("autoFillRunId")
      .startAt(prefix)
      .endAt(end)
      .limit(1000);

    if (last) q = q.startAfter(last);

    const snap = await q.get();
    if (snap.empty) break;

    all.push(...snap.docs);
    last = snap.docs[snap.docs.length - 1];
  }
  return all;
}

async function commitChunk(toDelete) {
  // teacher 업데이트는 teacher별로 묶어서 1번만
  const byTeacher = new Map(); // teacherId -> { "bookedSlots.xxx": delete, ... }

  // teacher doc 존재 확인용
  const teacherIds = new Set();

  for (const item of toDelete) {
    teacherIds.add(item.teacherId);
    if (!byTeacher.has(item.teacherId)) byTeacher.set(item.teacherId, {});
    byTeacher.get(item.teacherId)[`bookedSlots.${item.lessonId}`] =
      admin.firestore.FieldValue.delete();
  }

  // teacher docs 존재 체크(없으면 업데이트 제외 -> 배치 실패 방지)
  const teacherExists = new Map();
  await Promise.all([...teacherIds].map(async (tid) => {
    const ref = db.collection("availableSlots").doc(tid);
    const snap = await ref.get();
    teacherExists.set(tid, snap.exists);
  }));

  const batch = db.batch();

  for (const item of toDelete) {
    const mainRef = db.collection("lessons").doc(item.lessonId);
    const subRef = db.collection("users").doc(item.studentId).collection("lessons").doc(item.lessonId);

    batch.delete(mainRef);
    batch.delete(subRef);
  }

  for (const [teacherId, updateObj] of byTeacher.entries()) {
    if (!teacherExists.get(teacherId)) continue; // 없는 doc이면 스킵
    const teacherRef = db.collection("availableSlots").doc(teacherId);
    batch.update(teacherRef, updateObj);
  }

  if (DRY_RUN) return;

  await batch.commit();
}

async function main() {
  const cutoff = kstMidnightToUtcDate(CUTOFF_KST_YMD);

  console.log(`[rollback] DRY_RUN=${DRY_RUN}`);
  console.log(`[rollback] cutoff(KST ${CUTOFF_KST_YMD} 00:00) = ${cutoff.toISOString()}`);

  const docs = await fetchLessonDocsByRunId();
  console.log(`[rollback] fetched by runId/prefix: ${docs.length}`);

  // date 기준으로 과거만 필터
  const victims = [];
  for (const d of docs) {
    const data = d.data();
    const dateTs = data.date;
    if (!dateTs || typeof dateTs.toDate !== "function") continue;

    const lessonDate = dateTs.toDate();
    if (lessonDate < cutoff) {
      victims.push({
        lessonId: d.id,
        studentId: data.studentId,
        teacherId: data.teacherId,
        date: lessonDate,
        runId: data.autoFillRunId,
      });
    }
  }

  victims.sort((a, b) => a.date - b.date);

  console.log(`[rollback] will delete (date < cutoff): ${victims.length}`);
  console.log(`[rollback] sample(10):`);
  victims.slice(0, 10).forEach(v => {
    console.log(` - ${v.lessonId} | date=${v.date.toISOString()} | runId=${v.runId}`);
  });

  // CHUNK 처리
  for (let i = 0; i < victims.length; i += CHUNK_SIZE) {
    const chunk = victims.slice(i, i + CHUNK_SIZE);
    console.log(`[rollback] chunk ${i}~${i + chunk.length - 1} (${chunk.length})`);
    await commitChunk(chunk);
  }

  console.log(`[rollback] done.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
