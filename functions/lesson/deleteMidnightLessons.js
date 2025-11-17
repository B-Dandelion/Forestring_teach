const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const db = admin.firestore();

const deleteMidnightLessons = onRequest(async (req, res) => {
  const lessonSnap = await db.collection("lessons")
    .where("code", "!=", "-1")
    .get();

  let deleteCount = 0;

  for (const doc of lessonSnap.docs) {
    const lesson = doc.data();
    const lessonId = doc.id;
    const lessonDate = lesson.date.toDate();

    // 한국 시간 기준으로 변환
    const koreaTime = new Date(lessonDate.toLocaleString("en-US", { timeZone: "Asia/Seoul" }));

    console.log(`점검1 수업 시간 확인: ${lessonId} → ${koreaTime.toISOString()}`);

    if (koreaTime.getHours() !== 0) continue; // 오전 12시 수업만 삭제

    const studentId = lesson.studentId;
    const teacherId = lesson.teacherId;

    const batch = db.batch();

    // 1. 메인 컬렉션 삭제
    batch.delete(db.collection("lessons").doc(lessonId));

    // 2. 학생 문서 내부 삭제
    batch.delete(db.collection("users").doc(studentId).collection("lessons").doc(lessonId));

    // 3. 선생님 bookedSlots 내 삭제
    batch.update(db.collection("availableSlots").doc(teacherId), {
      [`bookedSlots.${lessonId}`]: admin.firestore.FieldValue.delete(),
    });

    await batch.commit();
    deleteCount++;
    console.log(`🗑️ 삭제 완료: ${lessonId}`);
  }

  res.send(`✅ 삭제된 수업 수: ${deleteCount}`);
});

module.exports = { deleteMidnightLessons };

//const admin = require("firebase-admin");
//const { onRequest } = require("firebase-functions/v2/https");
//const db = admin.firestore();
//
//const deleteMidnightLessons = onRequest(async (req, res) => {
//  const lessonSnap = await db.collection("lessons")
//    .where("code", "!=", "-1")
//    .get();
//
//  let deleteCount = 0;
//
//  for (const doc of lessonSnap.docs) {
//    const lesson = doc.data();
//    const lessonId = doc.id;
//    const lessonDate = lesson.date.toDate();
//    console.log(`수업 시간 확인: ${lessonId} → ${lessonDate.toISOString()}`);
//    if (lessonDate.getHours() !== 0) continue; // 오전 12시 수업만 삭제
//
//    const studentId = lesson.studentId;
//    const teacherId = lesson.teacherId;
//
//    const batch = db.batch();
//
//    // 1. 메인 컬렉션 삭제
//    batch.delete(db.collection("lessons").doc(lessonId));
//
//    // 2. 학생 문서 내부 삭제
//    batch.delete(db.collection("users").doc(studentId).collection("lessons").doc(lessonId));
//
//    // 3. 선생님 bookedSlots 내 삭제
////    batch.update(db.collection("availableSlots").doc(teacherId), {
////      [`bookedSlots.${lessonId}`]: admin.firestore.FieldValue.delete(),
////    });
//
//    batch.set(db.collection("availableSlots").doc(teacherId), {
//      bookedSlots: {
//        [lessonId]: admin.firestore.FieldValue.delete()
//      }
//    }, { merge: true });
//
//
//    await batch.commit();
//    deleteCount++;
//    console.log(`🗑️ 삭제 완료: ${lessonId}`);
//  }
//
//  res.send(`✅ 삭제된 수업 수: ${deleteCount}`);
//});
//
//module.exports = { deleteMidnightLessons };
