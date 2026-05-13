const functions = require("firebase-functions/v2");
const admin = require("firebase-admin");

const db = admin.firestore();

const removeLessonsInHolidayRange = functions.https.onRequest(async (req, res) => {
  try {
    const dryRun = req.query.dryRun !== "false";

    const start = new Date("2026-05-01T00:00:00+09:00");
    const end = new Date("2026-05-08T00:00:00+09:00");

    const snapshot = await db.collection("lessons")
      .where("date", ">=", start)
      .where("date", "<", end)
      .get();

    if (snapshot.empty) {
      res.send("❎ 삭제할 수업 없음");
      return;
    }

    let targetCount = 0;
    let skippedMakeupCount = 0;

    let batch = db.batch();
    let opCount = 0;

    async function commitIfNeeded(force = false) {
      if (dryRun) return;

      if (opCount >= 450 || (force && opCount > 0)) {
        await batch.commit();
        batch = db.batch();
        opCount = 0;
      }
    }

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const lessonId = doc.id;
      const { code, studentId, teacherId, date } = data;

      if (code === -1) {
        skippedMakeupCount++;
        console.log(`↪️ 보강 제외: ${lessonId}`, date?.toDate?.());
        continue;
      }

      if (!studentId || !teacherId) {
        console.log(`⚠️ studentId/teacherId 없음, skip: ${lessonId}`);
        continue;
      }

      targetCount++;

      console.log(`🧹 삭제 대상: ${lessonId}`, {
        studentId,
        teacherId,
        date: date?.toDate?.(),
      });

      if (!dryRun) {
        batch.delete(doc.ref);
        opCount++;

        batch.delete(
          db.collection("users")
            .doc(studentId)
            .collection("lessons")
            .doc(lessonId)
        );
        opCount++;

        batch.update(
          db.collection("availableSlots").doc(teacherId),
          {
            [`bookedSlots.${lessonId}`]: admin.firestore.FieldValue.delete(),
          }
        );
        opCount++;

        await commitIfNeeded();
      }
    }

    await commitIfNeeded(true);

    res.send(
      dryRun
        ? `✅ DRY RUN 완료. 삭제 대상 ${targetCount}개, 보강 제외 ${skippedMakeupCount}개`
        : `✅ 실제 삭제 완료. 삭제 ${targetCount}개, 보강 제외 ${skippedMakeupCount}개`
    );
  } catch (e) {
    console.error("❌ 오류 발생:", e);
    res.status(500).send(`삭제 중 오류 발생: ${e.message}`);
  }
});

module.exports = {
  removeLessonsInHolidayRange,
};