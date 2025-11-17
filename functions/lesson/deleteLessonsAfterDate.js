const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const db = admin.firestore();

const deleteLessonsAfterDate = onRequest(async (req, res) => {
  const target = new Date("2025-08-24T00:00:00+09:00"); // KST 자정 기준

  const snap = await db.collection("lessons")
    .where("date", ">=", target)
    .where("code", "!=", "-1") // 보강 수업 제외
    .get();

  let count = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const lessonId = doc.id;
    const studentId = data.studentId;
    const teacherId = data.teacherId;

    const batch = db.batch();
    batch.delete(db.collection("lessons").doc(lessonId));
    batch.delete(db.collection("users").doc(studentId).collection("lessons").doc(lessonId));
    batch.update(db.collection("availableSlots").doc(teacherId), {
      [`bookedSlots.${lessonId}`]: admin.firestore.FieldValue.delete(),
    });

    await batch.commit();
    count++;
    console.log(`🗑️ 삭제 완료: ${lessonId}`);
  }

  res.send(`✅ 삭제 완료: ${count}개 수업`);
});

module.exports = { deleteLessonsAfterDate };