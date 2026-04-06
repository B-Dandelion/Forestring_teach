/* shift_lessons_20260213_14.js
 * - /lessons: date +7
 * - /users/{studentId}/lessons: date +7
 * - /availableSlots/{teacherId}.bookedSlots[lessonId].date +7
 */

const admin = require("firebase-admin");

// (A) 로컬 실행이면 보통 서비스계정 키가 필요함.
admin.initializeApp({ credential: admin.credential.cert(require("../serviceAccountKey.json")) });

// (B) 이미 gcloud ADC 되어있으면(Cloud Shell / gcloud auth application-default login) 아래만으로도 됨.
//admin.initializeApp();

const db = admin.firestore();

const DAY_MS = 24 * 60 * 60 * 1000;

function utcFromKst(y, m1, d, hh = 0, mm = 0) {
  // KST(UTC+9) → UTC = hh-9
  return new Date(Date.UTC(y, m1 - 1, d, hh - 9, mm, 0, 0));
}

function toJsDate(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v.toDate === "function") return v.toDate(); // Timestamp
  return null;
}

async function main() {
  const dryRun = process.argv.includes("--dryRun");

  // 2/13 00:00(KST) ~ 2/15 00:00(KST)  => 2/13, 2/14 포함
  const start = utcFromKst(2026, 2, 13, 0, 0);
  const end = utcFromKst(2026, 2, 15, 0, 0);

  console.log(`[shift] range KST: 2026-02-13 00:00 ~ 2026-02-15 00:00 (end exclusive)`);
  console.log(`[shift] range UTC: ${start.toISOString()} ~ ${end.toISOString()}`);
  console.log(`[shift] dryRun=${dryRun}`);

  const snap = await db
    .collection("lessons")
    .where("date", ">=", start)
    .where("date", "<", end)
    .get();

  console.log(`[shift] matched lessons: ${snap.size}`);

  if (snap.empty) return;

  // teacher별 bookedSlots patch 합치기(한 teacher 문서에 한 번만 set)
  const teacherPatches = new Map(); // teacherId -> { bookedSlots: { [lessonId]: { date } } }

  const batch = db.batch();

  for (const doc of snap.docs) {
    const lessonId = doc.id;
    const data = doc.data();

    const studentId = data.studentId;
    const teacherId = data.teacherId;

    const oldDate = toJsDate(data.date);
    if (!oldDate || !studentId || !teacherId) {
      console.warn(`[skip] ${lessonId} missing fields (date/studentId/teacherId)`);
      continue;
    }

    const newDate = new Date(oldDate.getTime() + 7 * DAY_MS);

    console.log(`[plan] ${lessonId} : ${oldDate.toISOString()} -> ${newDate.toISOString()}`);

    if (dryRun) continue;

    // 1) root lessons
    batch.update(doc.ref, {
      date: newDate,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      // 필요하면 이유 기록
      // movedBy: "admin",
      // moveReason: "holiday_change",
    });

    // 2) users/{studentId}/lessons/{lessonId}  (없어도 터지지 않게 set+merge)
    const userLessonRef = db.collection("users").doc(studentId).collection("lessons").doc(lessonId);
    batch.set(
      userLessonRef,
      {
        date: newDate,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // 3) availableSlots/{teacherId}.bookedSlots[lessonId].date
    const patch = teacherPatches.get(teacherId) ?? { bookedSlots: {} };
    patch.bookedSlots[lessonId] = { date: newDate };
    teacherPatches.set(teacherId, patch);
  }

  if (!dryRun) {
    for (const [teacherId, patch] of teacherPatches.entries()) {
      const teacherRef = db.collection("availableSlots").doc(teacherId);
      batch.set(teacherRef, patch, { merge: true });
    }

    await batch.commit();
    console.log(`[shift] committed. teachersTouched=${teacherPatches.size}`);
  } else {
    console.log(`[shift] dryRun only. no writes.`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
