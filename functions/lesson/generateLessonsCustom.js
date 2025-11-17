//const admin = require("firebase-admin");
//const { onRequest } = require("firebase-functions/v2/https");
//const db = admin.firestore();
//
//const generateLessonsCustom = onRequest(async (req, res) => {
//  const studentId = "STU_250408164";
//  const teacherId = "TCH_250313460";
//  const duration = 30;
//  const code = "0";
//  const semesterId = "2025-07";
//  const baseCode = "SA1700";
//
//  const dates = [
//    new Date("2025-07-05T17:00:00+09:00"),
//    new Date("2025-07-12T17:00:00+09:00"),
//    new Date("2025-07-19T17:00:00+09:00")
//  ];
//
//  let count = 2; // 시작 suffix 002
//  let created = 0;
//
//  for (const date of dates) {
//    const idSuffix = String(count).padStart(3, '0');
//    const lessonId = `${studentId}_${semesterId}_${baseCode}${idSuffix}`;
//    count++;
//
//    const lessonRef = db.collection("lessons").doc(lessonId);
//    const exists = await lessonRef.get();
//    if (exists.exists) {
//      console.log(`❌ 이미 존재: ${lessonId}`);
//      continue;
//    }
//
//    const lessonData = {
//      code,
//      date,
//      duration,
//      isRescheduled: false,
//      status: "confirmed",
//      studentId,
//      teacherId,
//      createdAt: admin.firestore.FieldValue.serverTimestamp(),
//      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
//    };
//
//    const batch = db.batch();
//    batch.set(lessonRef, lessonData);
//    batch.set(db.collection("users").doc(studentId).collection("lessons").doc(lessonId), lessonData);
//    batch.set(db.collection("availableSlots").doc(teacherId), {
//      bookedSlots: {
//        [lessonId]: {
//          date,
//          duration,
//          isRescheduled: false,
//          status: "confirmed",
//          studentId
//        }
//      }
//    }, { merge: true });
//
//    await batch.commit();
//    console.log(`✅ 생성 완료: ${lessonId}`);
//    created++;
//  }
//
//  res.send(`📅 생성 완료: ${created}개 수업`);
//});
//
//module.exports = { generateLessonsCustom };

const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const db = admin.firestore();

const generateLessonsCustom = onRequest(async (req, res) => {
  const startDate = new Date("2025-08-24T00:00:00+09:00");
  const endDate = new Date("2025-08-30T23:59:59+09:00");

  const studentsSnap = await db.collection("users")
    .where("role", "==", "student").get();

  for (const doc of studentsSnap.docs) {
    const studentId = doc.id;
    const student = doc.data();
    const teacherId = student.teacherId;
    const schedule = student.weeklySchedule;
    if (!schedule || schedule.length === 0) continue;

    const semesterSnap = await db.collection("semesters")
      .where("startDate", "<=", endDate)
      .where("endDate", ">=", startDate)
      .get();
    if (semesterSnap.empty) continue;

    const semester = semesterSnap.docs[0];
    const semesterId = semester.id;

    for (const sched of schedule) {
      const { day, startTime, duration, code } = sched;
      const baseCode = `${day}${startTime.replace(":", "")}`;
      const firstTargetDate = getFirstDateMatchingDay(startDate, day);

      const date = firstTargetDate;
      const [hour, minute] = startTime.split(":").map(Number);
      date.setHours(hour, minute, 0, 0);

      if (date > endDate) continue;

      // 중복 방지: 이미 같은 날짜+시간에 수업 있는지 확인
      const existingLessons = await db.collection("lessons")
        .where("studentId", "==", studentId)
        .where("date", ">=", new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0))
        .where("date", "<=", new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59))
        .get();

      const count = existingLessons.docs.filter(doc => {
        const d = doc.data();
        return d.code === code && d.date.toDate().getHours() === date.getHours();
      }).length + 1;

      const idSuffix = String(count).padStart(3, '0');
      const lessonId = `${studentId}_${semesterId}_${baseCode}${idSuffix}`;

      const exists = await db.collection("lessons").doc(lessonId).get();
      if (exists.exists) continue;

      const lessonData = {
        code,
        date,
        duration,
        isRescheduled: false,
        status: "confirmed",
        studentId,
        teacherId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      };

      const batch = db.batch();
      batch.set(db.collection("lessons").doc(lessonId), lessonData);
      batch.set(db.collection("users").doc(studentId)
        .collection("lessons").doc(lessonId), lessonData);
      batch.set(db.collection("availableSlots").doc(teacherId), {
        bookedSlots: {
          [lessonId]: {
            date,
            duration,
            isRescheduled: false,
            status: "confirmed",
            studentId
          }
        }
      }, { merge: true });
      await batch.commit();

      console.log(`✅ 생성 완료: ${lessonId}`);
    }
  }

  res.send("📅 8월 24~30일 수업 생성 완료!");
});

const dayMap = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };
function getFirstDateMatchingDay(startDate, dayCode) {
  const targetDay = dayMap[dayCode];
  const date = new Date(startDate);
  while (date.getDay() !== targetDay) {
    date.setDate(date.getDate() + 1);
  }
  return date;
}

module.exports = { generateLessonsCustom };