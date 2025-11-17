const functions = require("firebase-functions/v2");
const admin = require("firebase-admin");
const db = admin.firestore();

exports.removeLessonsInHolidayRange = functions.https.onRequest(async (req, res) => {
  try {
    const start = new Date("2025-05-01T00:00:00+09:00");
    const end = new Date("2025-05-08T00:00:00+09:00"); // 🔥 endDate 하루 더함

    const snapshot = await db.collection("lessons")
      .where("date", ">=", start)
      .where("date", "<", end)
      .get();

    if (snapshot.empty) {
      res.send("❎ 삭제할 수업 없음");
      return;
    }

    const batch = db.batch();
    let count = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const lessonId = doc.id;
      const { code, studentId, teacherId } = data;

      // 보강 수업은 제외
      if (code === -1) continue;

      // 1. lessons/{lessonId}
      batch.delete(doc.ref);

      // 2. users/{studentId}/lessons/{lessonId}
      batch.delete(
        db.collection("users").doc(studentId).collection("lessons").doc(lessonId)
      );

      // 3. availableSlots/{teacherId}/bookedSlots.{lessonId}
      batch.update(
        db.collection("availableSlots").doc(teacherId),
        { [`bookedSlots.${lessonId}`]: admin.firestore.FieldValue.delete() }
      );

      count++;
      console.log(`🧹 삭제 대상: ${lessonId}`);
    }

    await batch.commit();
    res.send(`✅ 삭제 완료 (${count}개 수업)`);
  } catch (e) {
    console.error("❌ 오류 발생:", e);
    res.status(500).send("삭제 중 오류 발생");
  }
});
