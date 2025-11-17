const functions = require("firebase-functions/v2");
const admin = require("firebase-admin");
const db = admin.firestore();

exports.cleanupLeftoverLessons = functions.https.onRequest(async (req, res) => {
  try {
    const archivedSnap = await db.collection("archivedUsers").get();

    for (const userDoc of archivedSnap.docs) {
      const studentId = userDoc.id;
      const userData = userDoc.data();
      const teacherId = userData.teacherId;
      const withdrawalDate = userData.withdrawalDate?.toDate?.(); // Timestamp → Date 변환

      if (!withdrawalDate) {
        console.log(`❎ ${studentId} : 탈퇴일 없음`);
        continue;
      }

      // 1. 전체 lessons 컬렉션에서 해당 학생의 수업 찾기
      const lessonsQuery = await db.collection("lessons")
        .where("studentId", "==", studentId)
        .get();

      if (lessonsQuery.empty) {
        console.log(`❎ ${studentId} 관련 수업 없음`);
        continue;
      }

      const batch = db.batch();
      const teacherSlotRef = db.collection("availableSlots").doc(teacherId);

      for (const lesson of lessonsQuery.docs) {
        const lessonData = lesson.data();
        const lessonDate = lessonData.date.toDate();

        // 탈퇴일 이후 수업만 삭제
        if (lessonDate > withdrawalDate) {
          const lessonId = lesson.id;

          // ① lessons 컬렉션 삭제
          batch.delete(lesson.ref);

          // ② availableSlots에서 예약 제거
          batch.update(teacherSlotRef, {
            [`bookedSlots.${lessonId}`]: admin.firestore.FieldValue.delete(),
          });

          console.log(`🧹 ${studentId} - ${lessonId} 삭제 예정`);
        }
      }

      await batch.commit();
      console.log(`✅ ${studentId} 관련 수업 정리 완료`);
    }

    res.status(200).send("🎯 탈퇴 후 수업 정리 완료!");
  } catch (e) {
    console.error("❌ 정리 중 오류:", e);
    res.status(500).send("정리 중 오류 발생");
  }
});
