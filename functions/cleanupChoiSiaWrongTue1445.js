const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

const DRY_RUN = false;
const TARGET = {
  studentId: 'STU_250415757',
  teacherId: 'TCH_250313460',
  weekday: 2, // JS 기준: 일0 월1 화2
  hour: 14,
  minute: 45,
};

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

function getMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

function pickTimestamp(data) {
  return data?.date || data?.startTime || data?.start || data?.slotTime || null;
}

function toKstParts(ms) {
  const d = new Date(ms + KST_OFFSET_MS);
  return {
    weekday: d.getUTCDay(),
    hour: d.getUTCHours(),
    minute: d.getUTCMinutes(),
    label: d.toISOString().replace('T', ' ').slice(0, 16),
  };
}

function isTargetWrongLesson(data) {
  const code = data?.code;
  const isRegularCode = code === '0' || code === 0;
  if (!isRegularCode) return false;
  if (data?.isRescheduled === true) return false;

  const ms = getMillis(pickTimestamp(data));
  if (ms == null) return false;

  const kst = toKstParts(ms);
  return (
    kst.weekday === TARGET.weekday &&
    kst.hour === TARGET.hour &&
    kst.minute === TARGET.minute
  );
}

function sameMillis(a, b) {
  const am = getMillis(a);
  const bm = getMillis(b);
  return am != null && bm != null && am === bm;
}

async function main() {
  console.log('--- cleanup start ---');
  console.log('DRY_RUN:', DRY_RUN);

  // 1) 메인 lessons 에서 후보 찾기
  const mainSnap = await db
    .collection('lessons')
    .where('studentId', '==', TARGET.studentId)
    .where('teacherId', '==', TARGET.teacherId)
    .get();

  const candidates = [];
  mainSnap.forEach((doc) => {
    const data = doc.data();
    if (isTargetWrongLesson(data)) {
      candidates.push({
        id: doc.id,
        ref: doc.ref,
        data,
      });
    }
  });

  console.log(`candidate lessons found: ${candidates.length}`);
  candidates.forEach((lesson) => {
    const ms = getMillis(pickTimestamp(lesson.data));
    const kst = ms != null ? toKstParts(ms).label : 'no-date';
    console.log(`- lessons/${lesson.id} | ${kst} KST`);
  });

  if (candidates.length === 0) {
    console.log('No candidate lessons found. stop.');
    return;
  }

  // 2) 학생 lessons 전체 조회
  const studentLessonsSnap = await db
    .collection('users')
    .doc(TARGET.studentId)
    .collection('lessons')
    .get();

  const studentLessonDocs = studentLessonsSnap.docs;

  // 3) teacher bookedSlots 전체 조회
  const bookedSlotsSnap = await db
    .collection('availableSlots')
    .doc(TARGET.teacherId)
    .collection('bookedSlots')
    .get();

  const bookedSlotDocs = bookedSlotsSnap.docs;

  const refsToDelete = new Map();

  function addRef(ref, reason) {
    if (!refsToDelete.has(ref.path)) {
      refsToDelete.set(ref.path, { ref, reason });
    }
  }

  for (const lesson of candidates) {
    addRef(lesson.ref, `main lesson ${lesson.id}`);

    // 학생 subcollection 문서 찾기
    for (const doc of studentLessonDocs) {
      const data = doc.data();

      const matchById = doc.id === lesson.id;
      const matchByTime =
        data?.teacherId === TARGET.teacherId &&
        sameMillis(pickTimestamp(data), pickTimestamp(lesson.data));

      if (matchById || matchByTime) {
        addRef(doc.ref, `student lesson match for ${lesson.id}`);
      }
    }

    // teacher bookedSlots 문서 찾기
    for (const doc of bookedSlotDocs) {
      const data = doc.data();

      const matchByLessonId = data?.lessonId === lesson.id;
      const matchByTime =
        data?.studentId === TARGET.studentId &&
        sameMillis(pickTimestamp(data), pickTimestamp(lesson.data));

      if (matchByLessonId || matchByTime) {
        addRef(doc.ref, `bookedSlot match for ${lesson.id}`);
      }
    }
  }

  console.log('\n--- refs to delete ---');
  for (const [path, info] of refsToDelete.entries()) {
    console.log(`${path}  <-- ${info.reason}`);
  }
  console.log(`\nTOTAL DELETE COUNT: ${refsToDelete.size}`);

  if (DRY_RUN) {
    console.log('\nDRY_RUN=true 이므로 실제 삭제는 안 했음.');
    return;
  }

  // 실제 삭제
  for (const { ref } of refsToDelete.values()) {
    await ref.delete();
    console.log(`deleted: ${ref.path}`);
  }

  console.log('--- cleanup done ---');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });