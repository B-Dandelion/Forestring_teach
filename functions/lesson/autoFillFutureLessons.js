const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const db = admin.firestore();

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

// 요일 코드 → 숫자 매핑 ("MO" → 1)
const dayMap = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

// KST 기준 요일(0=일..6=토)
function getKstDay(date) {
  return new Date(date.getTime() + KST_OFFSET_MS).getUTCDay();
}

// KST 기준으로 startDate 이후 "요일"이 dayCode인 첫 날짜(‘KST 날짜’만 맞춘 기준점) 반환
function getFirstDateMatchingDayKST(startDate, dayCode) {
  const targetDay = dayMap[dayCode];
  const d = new Date(startDate.getTime());
  while (getKstDay(d) !== targetDay) {
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return d;
}

// 기준점 Date에서 “KST의 연/월/일”만 뽑기
function getKstYmd(date) {
  const k = new Date(date.getTime() + KST_OFFSET_MS);
  return {
    y: k.getUTCFullYear(),
    m: k.getUTCMonth(), // 0-based
    d: k.getUTCDate(),
  };
}

// KST (y,m,d + HH:mm)을 “정확한 UTC instant Date”로 생성
function makeDateFromKst(y, m0, d, startTime) {
  const [hhRaw, mmRaw] = String(startTime).split(":");
  const hh = Number(hhRaw);
  const mm = Number(mmRaw);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) {
    throw new Error(`invalid startTime: ${startTime}`);
  }
  // KST = UTC+9 → UTC 시간은 hh-9
  return new Date(Date.UTC(y, m0, d, hh - 9, mm, 0, 0));
}

// 휴일 여부 확인 (end exclusive)
function isHoliday(date, holidays) {
  return holidays.some(h => date >= h.start && date < h.end);
}

// 날짜 더하기(UTC day 기준)
function addDaysUTC(date, days) {
  const d = new Date(date.getTime());
  d.setUTCDate(d.getUTCDate() + days);
  return d;
}

const autoFillFutureLessons = onSchedule(
  { schedule: "0 4 1 * *", timeZone: "Asia/Seoul", timeoutSeconds: 300 },
  async () => {
    const now = new Date();
    const runId = `autoFill_${now.toISOString().slice(0, 10)}_${Date.now()}`;
    console.log(`[autoFill] runId=${runId} start`);

    const threeMonthsLater = new Date(now.getFullYear(), now.getMonth() + 3, now.getDate());

    const studentsSnap = await db.collection("users").where("role", "==", "student").get();

    const semesterSnap = await db.collection("semesters").orderBy("startDate").get();
    const allSemesters = semesterSnap.docs.map(d => ({ id: d.id, ...d.data() }));

    for (const doc of studentsSnap.docs) {
      const studentId = doc.id;
      const student = doc.data();

      const teacherId = student.teacherId;
      const schedule = student.weeklySchedule;

      if (!teacherId) {
        console.warn(`[autoFill][${runId}] teacherId 없음: ${studentId}`);
        continue;
      }
      if (!Array.isArray(schedule) || schedule.length === 0) {
        console.warn(`[autoFill][${runId}] 스케줄 없음: ${studentId}`);
        continue;
      }

      const lessonSnap = await db.collection(`users/${studentId}/lessons`).get();

      let latestDate = null;
      const existingTimeKeys = new Set();

      for (const l of lessonSnap.docs) {
        const raw = l.data().date;
        if (!raw || typeof raw.toDate !== "function") continue;

        const d = raw.toDate();
        if (!latestDate || d > latestDate) latestDate = d;

        existingTimeKeys.add(Math.floor(d.getTime() / 60000));
      }

      if (latestDate && latestDate > threeMonthsLater) {
        console.log(`[autoFill][${runId}] 수업 충분: ${studentId} latest=${latestDate.toISOString()}`);
        continue;
      }

      const lessonBase = latestDate || now;

      const futureSemesters = allSemesters
        .filter(s => {
          const end = s.endDate?.toDate ? s.endDate.toDate() : null;
          return end && end > lessonBase;
        })
        .slice(0, 3);

      if (futureSemesters.length === 0) {
        console.warn(`[autoFill][${runId}] 생성할 학기 없음: ${studentId} base=${lessonBase.toISOString()}`);
        continue;
      }

      const createdLessonIds = [];
      const skippedByExistingTime = [];
      const skippedByExistingId = [];
      const skippedByHoliday = [];

      const batch = db.batch();

      for (const semester of futureSemesters) {
        const semesterId = semester.id;

        const start = semester.startDate.toDate();
        const end = semester.endDate.toDate(); // exclusive

        const holidays = (semester.holidayPeriods || []).map(h => ({
          start: h.startDate.toDate(),
          end: h.endDate.toDate(), // exclusive
        }));

        for (const sched of schedule) {
          const { day, startTime, duration, code } = sched || {};

          if (!Object.prototype.hasOwnProperty.call(dayMap, day) || typeof startTime !== "string") {
            console.warn(`[autoFill][${runId}] 잘못된 weeklySchedule: student=${studentId} sched=${JSON.stringify(sched)}`);
            continue;
          }

          const dur = Number(duration) || 0;
          const baseCode = `${day}${startTime.replace(":", "")}`;

          // 1) “KST 요일”에 맞는 첫 날짜(기준점)
          const first = getFirstDateMatchingDayKST(start, day);

          // 2) 그 날짜의 KST 연/월/일을 뽑아서, startTime으로 새 Date 생성 (setUTCHours 금지)
          const { y, m, d } = getKstYmd(first);
          let lessonDate = makeDateFromKst(y, m, d, startTime);

          let count = 1;

          while (lessonDate < end && count <= 4) {
            if (isHoliday(lessonDate, holidays)) {
              skippedByHoliday.push(lessonDate.toISOString());
              lessonDate = addDaysUTC(lessonDate, 7);
              continue;
            }

            const timeKey = Math.floor(lessonDate.getTime() / 60000);
            if (existingTimeKeys.has(timeKey)) {
              skippedByExistingTime.push(lessonDate.toISOString());
              count++;
              lessonDate = addDaysUTC(lessonDate, 7);
              continue;
            }

            const idSuffix = String(count).padStart(3, "0");
            const lessonId = `${studentId}_${semesterId}_${baseCode}${idSuffix}`;

            const lessonRef = db.collection("lessons").doc(lessonId);
            const exists = await lessonRef.get();

            if (!exists.exists) {
              const lessonData = {
                code,
                date: lessonDate,
                duration: dur,
                isRescheduled: false,
                status: "confirmed",
                studentId,
                teacherId,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                autoFillRunId: runId,
              };

              batch.set(lessonRef, lessonData);

              const studentRef = db.collection("users").doc(studentId).collection("lessons").doc(lessonId);
              batch.set(studentRef, lessonData);

              // 구버전: availableSlots/{teacherId}.bookedSlots[lessonId]
              const teacherDocRef = db.collection("availableSlots").doc(teacherId);
              batch.set(
                teacherDocRef,
                {
                  bookedSlots: {
                    [lessonId]: {
                      date: lessonDate,
                      duration: dur,
                      isRescheduled: false,
                      status: "confirmed",
                      studentId,
                      lessonId,
                      teacherId,
                    },
                  },
                },
                { merge: true }
              );

              createdLessonIds.push(lessonId);
              existingTimeKeys.add(timeKey);

              count++;
            } else {
              skippedByExistingId.push(lessonId);
              count++;
            }

            lessonDate = addDaysUTC(lessonDate, 7);
          }
        }
      }

      await batch.commit();

      console.log(
        `[autoFill][${runId}] ${studentId} → created=${createdLessonIds.length}, skipTime=${skippedByExistingTime.length}, skipId=${skippedByExistingId.length}, skipHoliday=${skippedByHoliday.length}`
      );

      await db
        .collection("adminLogs")
        .doc("autoFillFutureLessons")
        .collection("runs")
        .doc(runId)
        .collection("students")
        .doc(studentId)
        .set(
          {
            studentId,
            teacherId,
            createdLessonIds,
            skippedByExistingTime,
            skippedByExistingId,
            skippedByHoliday,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
    }

    console.log(`[autoFill] runId=${runId} end`);
  }
);

module.exports = { autoFillFutureLessons };
