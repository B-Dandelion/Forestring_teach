const functions = require('firebase-functions');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// ★ 하드코딩: 학생 ID
const TARGET_STUDENT_ID = 'STU_250520860';

// ★ 하드코딩: 기준 시각 (2025-11-02 00:00:00 UTC+9)
//   = 2025-11-01T15:00:00.000Z
const CUTOFF_ISO_UTC = '2025-11-01T15:00:00.000Z';

// ★ 1차는 DRY RUN. 실제 삭제할 때 false 로 바꾸고 다시 배포.
const DRY_RUN = false;

exports.cleanupStudentLessons = functions.https.onRequest(async (req, res) => {
  console.log('=== cleanupStudentLessons START ===');
  console.log(
    `TARGET_STUDENT_ID=${TARGET_STUDENT_ID}, DRY_RUN=${DRY_RUN}, CUTOFF_ISO_UTC=${CUTOFF_ISO_UTC}`
  );

  try {
    const cutoffDate = new Date(CUTOFF_ISO_UTC);
    const cutoffTs = admin.firestore.Timestamp.fromDate(cutoffDate);

    console.log(
      `[cleanup] cutoff (UTC) = ${cutoffDate.toISOString()} / (KST 기준 2025-11-02 00:00 예상)`
    );

    // 1. lessons 컬렉션에서 대상 레슨 찾기 (date 필드 기준)
    const lessonsSnap = await db
      .collection('lessons')
      .where('studentId', '==', TARGET_STUDENT_ID)
      .where('date', '>=', cutoffTs) // 'date' 필드명 다르면 여기 바꾸면 됨
      .get();

    const lessonIds = [];
    const teacherIdsSet = new Set();
    const lessonDataById = new Map();

    lessonsSnap.forEach((doc) => {
      const data = doc.data();
      lessonIds.push(doc.id);
      lessonDataById.set(doc.id, data);
      if (data.teacherId) teacherIdsSet.add(data.teacherId);

      let d = null;
      if (data.date instanceof admin.firestore.Timestamp) {
        d = data.date.toDate().toISOString();
      } else if (data.date && data.date._seconds !== undefined) {
        d = new admin.firestore.Timestamp(
          data.date._seconds,
          data.date._nanoseconds
        )
          .toDate()
          .toISOString();
      }

      console.log(
        `[cleanup] LESSON target: id=${doc.id}, teacher=${data.teacherId}, date=${d}`
      );
    });

    const teacherIds = Array.from(teacherIdsSet);
    console.log(`[cleanup] lessons to handle = ${lessonIds.length}`);
    console.log(`[cleanup] teachers involved = ${JSON.stringify(teacherIds)}`);

    // 2. availableSlots 에서 bookedSlots 중 삭제 대상 찾기
    const slotsToDeleteByTeacher = {}; // { teacherId: [slotId, ...] }

    for (const teacherId of teacherIds) {
      const availRef = db.collection('availableSlots').doc(teacherId);
      const availSnap = await availRef.get();

      if (!availSnap.exists) {
        console.log(
          `[cleanup] availableSlots doc not found for teacher=${teacherId}`
        );
        continue;
      }

      const availData = availSnap.data() || {};
      const bookedSlots = availData.bookedSlots || {};
      const deleteSlotIds = [];

      for (const [slotId, slotValue] of Object.entries(bookedSlots)) {
        const slotStudentId = slotValue.studentId;

        let slotDate = null;
        const v = slotValue.date;
        if (v instanceof admin.firestore.Timestamp) {
          slotDate = v.toDate();
        } else if (v && typeof v === 'object' && v._seconds !== undefined) {
          slotDate = new admin.firestore.Timestamp(
            v._seconds,
            v._nanoseconds
          ).toDate();
        }

        if (!slotDate) continue;

        if (
          slotStudentId === TARGET_STUDENT_ID &&
          slotDate >= cutoffDate
        ) {
          deleteSlotIds.push(slotId);
        }
      }

      if (deleteSlotIds.length > 0) {
        slotsToDeleteByTeacher[teacherId] = deleteSlotIds;
        console.log(
          `[cleanup] TEACHER ${teacherId} bookedSlots to delete = ${deleteSlotIds.join(
            ', '
          )}`
        );
      }
    }

    console.log(
      `[cleanup] slotsToDeleteByTeacher = ${JSON.stringify(
        slotsToDeleteByTeacher
      )}`
    );

    // ★ DRY RUN: 여기서는 아무것도 안지우고 요약만 반환
    if (DRY_RUN) {
      console.log('=== cleanupStudentLessons DRY RUN ===');
      return res.json({
        dryRun: true,
        studentId: TARGET_STUDENT_ID,
        cutoff: cutoffDate.toISOString(),
        lessonCount: lessonIds.length,
        lessonIds,
        teacherIds,
        slotsToDeleteByTeacher,
      });
    }

    // 3. 실제 삭제 (DRY_RUN=false 로 바꾼 뒤에만 실행됨)
    console.log('=== cleanupStudentLessons REAL DELETE START ===');

    let batch = db.batch();
    let opCount = 0;

    const commitIfNeeded = async () => {
      if (opCount >= 450) {
        await batch.commit();
        console.log('[cleanup] batch committed (chunk)');
        batch = db.batch();
        opCount = 0;
      }
    };

    // 3-1. lessons → archivedLessons 로 복사 + lessons / users 서브컬렉션 삭제
    for (const lessonId of lessonIds) {
      const lessonData = lessonDataById.get(lessonId) || {};

      const lessonRef = db.collection('lessons').doc(lessonId);
      const archivedRef = db
        .collection('archivedLessons')
        .doc(TARGET_STUDENT_ID)
        .collection('lessons')
        .doc(lessonId);
      const userLessonRef = db
        .collection('users')
        .doc(TARGET_STUDENT_ID)
        .collection('lessons')
        .doc(lessonId);

      batch.set(archivedRef, {
        ...lessonData,
        archivedAt: admin.firestore.FieldValue.serverTimestamp(),
        archiveReason: 'manual_cleanup_STU_250520860',
        originalPath: lessonRef.path,
      });
      opCount++;

      batch.delete(lessonRef);
      opCount++;

      batch.delete(userLessonRef);
      opCount++;

      await commitIfNeeded();
    }

    // 3-2. availableSlots.bookedSlots.* 삭제
    for (const [teacherId, slotIds] of Object.entries(
      slotsToDeleteByTeacher
    )) {
      const availRef = db.collection('availableSlots').doc(teacherId);
      const updates = {};

      for (const slotId of slotIds) {
        updates[`bookedSlots.${slotId}`] =
          admin.firestore.FieldValue.delete();
      }

      batch.update(availRef, updates);
      opCount++;

      await commitIfNeeded();
    }

    if (opCount > 0) {
      await batch.commit();
      console.log('[cleanup] final batch committed');
    }

    console.log('=== cleanupStudentLessons REAL DELETE DONE ===');

    return res.json({
      dryRun: false,
      studentId: TARGET_STUDENT_ID,
      cutoff: cutoffDate.toISOString(),
      lessonCount: lessonIds.length,
      lessonIds,
      teacherIds,
      slotsToDeleteByTeacher,
    });
  } catch (e) {
    console.error('cleanupStudentLessons ERROR', e);
    return res.status(500).json({ error: e.message || String(e) });
  }
});
