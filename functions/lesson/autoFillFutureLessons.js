const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const db = admin.firestore();

const autoFillFutureLessons = onSchedule(
  { schedule: "0 4 1 * *", timeZone: "Asia/Seoul", timeoutSeconds: 300},
  async () => {
    const now = new Date();
    const threeMonthsLater = new Date(now.getFullYear(), now.getMonth() + 3, now.getDate());

    // 1. 모든 학생 불러오기
    const studentsSnap = await db.collection("users")
      .where("role", "==", "student").get();

    for (const doc of studentsSnap.docs) {
      const studentId = doc.id;
      const student = doc.data();
      const teacherId = student.teacherId;
      const schedule = student.weeklySchedule;

      if (!schedule || schedule.length === 0) {
        console.warn(`스케줄 없음: ${studentId}`);
        continue;
      }

      // 2. 가장 미래 수업 날짜 확인
      const lessonSnap = await db.collection(`users/${studentId}/lessons`).get();
      let latestDate = null;
      for (const l of lessonSnap.docs) {
        const date = l.data().date.toDate();
        if (!latestDate || date > latestDate) latestDate = date;
      }

      if (latestDate && latestDate > threeMonthsLater) {
        console.log(`수업 충분: ${studentId}`);
        continue;
      }
      // 3. 생성 대상: 이후 3개 학기만큼 수업 생성
      const lessonBase = latestDate || now;
      const semesterSnap = await db.collection("semesters").orderBy("startDate").get();

      // 3-1. 마지막 수업 학기 이후 학기 3개 추출
      const futureSemesters = semesterSnap.docs.filter(doc => doc.data().startDate.toDate() > lessonBase).slice(0, 3);

      if (futureSemesters.length === 0) {
        console.warn(`생성할 학기 없음: ${studentId}`);
        continue;
      }

      const batch = db.batch();

      for (const semester of futureSemesters) {
        const semesterId = semester.id;
        const { startDate, endDate, holidayPeriods } = semester.data();
        const start = startDate.toDate();
        const end = endDate.toDate();
        const holidays = (holidayPeriods || []).map(h => ({
          start: h.startDate.toDate(),
          end: h.endDate.toDate(),
        }));

        for (const sched of schedule) {
          const { day, startTime, duration, code } = sched;
          const baseCode = `${day}${startTime.replace(":", "")}`;

          let lessonDate = getFirstDateMatchingDay(start, day);
          let count = 1;

          while (lessonDate <= end && count <= 4) {
            if (!isHoliday(lessonDate, holidays)) {
              const idSuffix = String(count).padStart(3, '0');
              const lessonId = `${studentId}_${semesterId}_${baseCode}${idSuffix}`;

              const lessonRef = db.collection("lessons").doc(lessonId);
              const exists = await lessonRef.get();
              if (!exists.exists) {
                const lessonData = {
                  code,
                  date: lessonDate,
                  duration,
                  isRescheduled: false,
                  status: "confirmed",
                  studentId,
                  teacherId,
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                  updatedAt: admin.firestore.FieldValue.serverTimestamp()
                };

                // 저장: lessons
                batch.set(lessonRef, lessonData);

                // 저장: users/{studentId}/lessons
                const studentRef = db.collection("users").doc(studentId)
                  .collection("lessons").doc(lessonId);
                batch.set(studentRef, lessonData);

                // 저장: availableSlots/{teacherId}/bookedSlots.{lessonId}
                const teacherSlotRef = db.collection("availableSlots").doc(teacherId);
                batch.set(teacherSlotRef, {
                  bookedSlots: {
                    [lessonId]: {
                      date: lessonDate,
                      duration,
                      isRescheduled: false,
                      status: "confirmed",
                      studentId
                    }
                  }
                }, { merge: true });

                count++;
              } else {
                console.log(`이미 존재하는 수업: ${lessonId}`);
                lessonDate = lessonDate.addDays(7);
              }
            } else {
              console.log(`⛱ 휴일로 건너뜀: ${lessonDate}`);
            }
            lessonDate = lessonDate.addDays(7);
          }
        }
      }

      await batch.commit();
      console.log(`${studentId} → 미래 수업 생성 완료`);
    }
    console.log("수업 자동 생성 함수 종료");
  }
);

// 요일 코드 → 숫자 매핑 ("MO" → 1)
const dayMap = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

// 주어진 요일부터 시작하는 날짜 반환
function getFirstDateMatchingDay(startDate, dayCode) {
  const targetDay = dayMap[dayCode];
  const date = new Date(startDate);
  while (date.getDay() !== targetDay) {
    date.setDate(date.getDate() + 1);
  }
  return date;
}

// 휴일 여부 확인 함수
function isHoliday(date, holidays) {
  return holidays.some(h => date >= h.start && date <= h.end);
}

// 날짜 더하기 함수
Date.prototype.addDays = function(days) {
  const date = new Date(this.valueOf());
  date.setDate(date.getDate() + days);
  return date;
};

module.exports = { autoFillFutureLessons };
