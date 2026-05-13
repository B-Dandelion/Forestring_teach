const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

const APPLY = true;
const TARGET = {
  teacherId: 'TCH_250313460',
  studentId: 'STU_250415757',
  weekday: 2, // KST 기준 화요일 (일0 월1 화2)
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

function toKstParts(ms) {
  const d = new Date(ms + KST_OFFSET_MS);
  return {
    weekday: d.getUTCDay(),
    hour: d.getUTCHours(),
    minute: d.getUTCMinutes(),
    label: d.toISOString().replace('T', ' ').slice(0, 16),
  };
}

function isPlainObject(value) {
  return (
    value !== null &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    typeof value.toMillis !== 'function' &&
    !(value instanceof Date)
  );
}

function isTargetLessonMap(obj) {
  if (!isPlainObject(obj)) return false;

  if (obj.studentId !== TARGET.studentId) return false;
  if (obj.isRescheduled !== false) return false;
  if (obj.status !== 'confirmed') return false;

  const ms = getMillis(obj.date || obj.startTime || obj.start || obj.slotTime);
  if (ms == null) return false;

  const kst = toKstParts(ms);

  return (
    kst.weekday === TARGET.weekday &&
    kst.hour === TARGET.hour &&
    kst.minute === TARGET.minute
  );
}

function collectMatches(current, path = [], matches = []) {
  if (!isPlainObject(current)) return matches;

  if (isTargetLessonMap(current)) {
    matches.push({
      path: [...path],
      data: current,
    });
    return matches;
  }

  for (const [key, value] of Object.entries(current)) {
    if (isPlainObject(value)) {
      collectMatches(value, [...path, key], matches);
    }
  }

  return matches;
}

async function main() {
  const ref = db.collection('availableSlots').doc(TARGET.teacherId);
  const snap = await ref.get();

  if (!snap.exists) {
    throw new Error(`availableSlots/${TARGET.teacherId} 문서가 없음`);
  }

  const data = snap.data() || {};
  const topKeys = Object.keys(data);

  console.log('--- availableSlots inspect start ---');
  console.log('teacherId:', TARGET.teacherId);
  console.log('top-level key count:', topKeys.length);
  console.log('top-level key sample:', topKeys.slice(0, 15));

  const matches = collectMatches(data);

  console.log('\nmatched target lesson maps:', matches.length);
  for (const match of matches) {
    const ms = getMillis(
      match.data.date || match.data.startTime || match.data.start || match.data.slotTime
    );
    const kst = ms != null ? toKstParts(ms).label : 'no-date';
    console.log(`- path: ${match.path.join('.')} | ${kst} KST`);
  }

  if (!APPLY) {
    console.log('\nAPPLY=false 이므로 실제 삭제는 안 했음.');
    return;
  }

  if (matches.length === 0) {
    console.log('삭제할 availableSlots 필드를 찾지 못함.');
    return;
  }

  for (const match of matches) {
    await ref.update(
      new admin.firestore.FieldPath(...match.path),
      admin.firestore.FieldValue.delete()
    );
    console.log(`deleted field path: ${match.path.join('.')}`);
  }

  console.log('--- availableSlots cleanup done ---');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });