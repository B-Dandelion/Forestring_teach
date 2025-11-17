const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");

const db = admin.firestore();

const fixLessonTimes = onRequest(async (req, res) => {
  // 한국시간 6월 26일 15:00 ~ 17:00 → UTC로 변환
  const targetStart = new Date("2025-06-26T06:00:00Z"); // 15:00 KST
  const targetEnd = new Date("2025-06-26T08:00:00Z");   // 17:00 KST

  const lessonSnap = await db.collection("lessons")
    .where("createdAt", ">=", targetStart)
    .where("createdAt", "<=", targetEnd)
    .get();

  if (lessonSnap.empty) {
    return res.send("📭 해당하는 수업 없음");
  }

  let fixed = 0;

  for (const doc of lessonSnap.docs) {
    const lessonId = doc.id;
    const lesson = doc.data();
    const originalDate = lesson.date.toDate();

    const correctedDate = new Date(originalDate.getTime() - 9 * 60 * 60 * 1000); // -9시간

    const batch = db.batch();

    // 1. 메인 컬렉션 업데이트
    batch.update(db.collection("lessons").doc(lessonId), { date: correctedDate });

    // 2. 학생 개인 lessons
    batch.update(db.collection("users").doc(lesson.studentId)
      .collection("lessons").doc(lessonId), { date: correctedDate });

    // 3. 선생님 availableSlots 내 bookedSlot
    batch.update(db.collection("availableSlots").doc(lesson.teacherId), {
      [`bookedSlots.${lessonId}.date`]: correctedDate
    });

    await batch.commit();
    fixed++;
    console.log(`🛠️ 시간 보정 완료: ${lessonId} → ${correctedDate.toISOString()}`);
  }

  res.send(`✅ 보정 완료된 수업 수: ${fixed}`);
});

module.exports = { fixLessonTimes };