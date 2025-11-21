const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");

const db = admin.firestore();

const DRY_RUN = false;

// 💾 예성 / 예나 공통 설정 + 개별 스케줄
const manualLessonConfigs = [
  {
    // 허예성
    studentId: "STU_250408148",
    teacherId: "TCH_250313460",
    duration: 15,
    items: [
      // 2025-11 보충
      { semesterId: "2025-11", day: "MO", startTime: "18:00", code: 0, index: 4, localDate: "2025-11-24" },
      { semesterId: "2025-11", day: "WE", startTime: "18:00", code: 1, index: 4, localDate: "2025-11-26" },

      // 2025-12 (월/수 18:00, 각 4개)
      { semesterId: "2025-12", day: "MO", startTime: "18:00", code: 0, index: 1, localDate: "2025-12-01" },
      { semesterId: "2025-12", day: "MO", startTime: "18:00", code: 0, index: 2, localDate: "2025-12-08" },
      { semesterId: "2025-12", day: "MO", startTime: "18:00", code: 0, index: 3, localDate: "2025-12-15" },
      { semesterId: "2025-12", day: "MO", startTime: "18:00", code: 0, index: 4, localDate: "2025-12-22" },

      { semesterId: "2025-12", day: "WE", startTime: "18:00", code: 1, index: 1, localDate: "2025-12-03" },
      { semesterId: "2025-12", day: "WE", startTime: "18:00", code: 1, index: 2, localDate: "2025-12-10" },
      { semesterId: "2025-12", day: "WE", startTime: "18:00", code: 1, index: 3, localDate: "2025-12-17" },
      { semesterId: "2025-12", day: "WE", startTime: "18:00", code: 1, index: 4, localDate: "2025-12-24" },

      // 2026-01 (월/수 18:00, 각 4개)
      { semesterId: "2026-01", day: "MO", startTime: "18:00", code: 0, index: 1, localDate: "2025-12-29" },
      { semesterId: "2026-01", day: "MO", startTime: "18:00", code: 0, index: 2, localDate: "2026-01-05" },
      { semesterId: "2026-01", day: "MO", startTime: "18:00", code: 0, index: 3, localDate: "2026-01-12" },
      { semesterId: "2026-01", day: "MO", startTime: "18:00", code: 0, index: 4, localDate: "2026-01-19" },

      { semesterId: "2026-01", day: "WE", startTime: "18:00", code: 1, index: 1, localDate: "2025-12-31" },
      { semesterId: "2026-01", day: "WE", startTime: "18:00", code: 1, index: 2, localDate: "2026-01-07" },
      { semesterId: "2026-01", day: "WE", startTime: "18:00", code: 1, index: 3, localDate: "2026-01-14" },
      { semesterId: "2026-01", day: "WE", startTime: "18:00", code: 1, index: 4, localDate: "2026-01-21" },

      // 2026-02 (월/수 18:00, 휴원(2/15~2/20) 제외하고 4개)
      { semesterId: "2026-02", day: "MO", startTime: "18:00", code: 0, index: 1, localDate: "2026-02-02" },
      { semesterId: "2026-02", day: "MO", startTime: "18:00", code: 0, index: 2, localDate: "2026-02-09" },
      { semesterId: "2026-02", day: "MO", startTime: "18:00", code: 0, index: 3, localDate: "2026-02-23" },
      { semesterId: "2026-02", day: "MO", startTime: "18:00", code: 0, index: 4, localDate: "2026-03-02" },

      { semesterId: "2026-02", day: "WE", startTime: "18:00", code: 1, index: 1, localDate: "2026-02-04" },
      { semesterId: "2026-02", day: "WE", startTime: "18:00", code: 1, index: 2, localDate: "2026-02-11" },
      { semesterId: "2026-02", day: "WE", startTime: "18:00", code: 1, index: 3, localDate: "2026-02-25" },
      { semesterId: "2026-02", day: "WE", startTime: "18:00", code: 1, index: 4, localDate: "2026-03-04" },
    ],
  },
  {
    // 허예나
    studentId: "STU_250424503",
    teacherId: "TCH_250313460",
    duration: 15,
    items: [
      // 2025-11 보충
      { semesterId: "2025-11", day: "TU", startTime: "17:00", code: 0, index: 4, localDate: "2025-11-25" },
      { semesterId: "2025-11", day: "FR", startTime: "19:00", code: 1, index: 4, localDate: "2025-11-28" },

      // 2025-12 (화 17:00, 금 19:00 각 4개)
      { semesterId: "2025-12", day: "TU", startTime: "17:00", code: 0, index: 1, localDate: "2025-12-02" },
      { semesterId: "2025-12", day: "TU", startTime: "17:00", code: 0, index: 2, localDate: "2025-12-09" },
      { semesterId: "2025-12", day: "TU", startTime: "17:00", code: 0, index: 3, localDate: "2025-12-16" },
      { semesterId: "2025-12", day: "TU", startTime: "17:00", code: 0, index: 4, localDate: "2025-12-23" },

      { semesterId: "2025-12", day: "FR", startTime: "19:00", code: 1, index: 1, localDate: "2025-12-05" },
      { semesterId: "2025-12", day: "FR", startTime: "19:00", code: 1, index: 2, localDate: "2025-12-12" },
      { semesterId: "2025-12", day: "FR", startTime: "19:00", code: 1, index: 3, localDate: "2025-12-19" },
      { semesterId: "2025-12", day: "FR", startTime: "19:00", code: 1, index: 4, localDate: "2025-12-26" },

      // 2026-01
      { semesterId: "2026-01", day: "TU", startTime: "17:00", code: 0, index: 1, localDate: "2025-12-30" },
      { semesterId: "2026-01", day: "TU", startTime: "17:00", code: 0, index: 2, localDate: "2026-01-06" },
      { semesterId: "2026-01", day: "TU", startTime: "17:00", code: 0, index: 3, localDate: "2026-01-13" },
      { semesterId: "2026-01", day: "TU", startTime: "17:00", code: 0, index: 4, localDate: "2026-01-20" },

      { semesterId: "2026-01", day: "FR", startTime: "19:00", code: 1, index: 1, localDate: "2026-01-02" },
      { semesterId: "2026-01", day: "FR", startTime: "19:00", code: 1, index: 2, localDate: "2026-01-09" },
      { semesterId: "2026-01", day: "FR", startTime: "19:00", code: 1, index: 3, localDate: "2026-01-16" },
      { semesterId: "2026-01", day: "FR", startTime: "19:00", code: 1, index: 4, localDate: "2026-01-23" },

      // 2026-02 (휴원(2/15~2/20) 제외)
      { semesterId: "2026-02", day: "TU", startTime: "17:00", code: 0, index: 1, localDate: "2026-02-03" },
      { semesterId: "2026-02", day: "TU", startTime: "17:00", code: 0, index: 2, localDate: "2026-02-10" },
      { semesterId: "2026-02", day: "TU", startTime: "17:00", code: 0, index: 3, localDate: "2026-02-24" },
      { semesterId: "2026-02", day: "TU", startTime: "17:00", code: 0, index: 4, localDate: "2026-03-03" },

      { semesterId: "2026-02", day: "FR", startTime: "19:00", code: 1, index: 1, localDate: "2026-02-06" },
      { semesterId: "2026-02", day: "FR", startTime: "19:00", code: 1, index: 2, localDate: "2026-02-13" },
      { semesterId: "2026-02", day: "FR", startTime: "19:00", code: 1, index: 3, localDate: "2026-02-27" },
      { semesterId: "2026-02", day: "FR", startTime: "19:00", code: 1, index: 4, localDate: "2026-03-06" },
    ],
  },
];

// KST(UTC+9) 로컬 날짜 + 시간 → UTC Date 객체로 변환
function kstToUtcDate(localDate, startTime) {
  const [year, month, day] = localDate.split("-").map(Number);
  const [hour, minute] = startTime.split(":").map(Number);

  // Date.UTC(year, monthIndex, day, hour, minute)
  // KST → UTC로 9시간 빼기
  return new Date(Date.UTC(year, month - 1, day, hour - 9, minute, 0, 0));
}

const manualCreateRestoredLessons = onRequest(async (req, res) => {
  const batch = db.batch();
  const created = [];
  const planned = []; // DRY RUN에서 어떤 걸 만들 예정이었는지

  function buildLessonsToCreate() {
    const lessons = [];

    for (const cfg of manualLessonConfigs) {
      const { studentId, teacherId, duration, items } = cfg;

      for (const item of items) {
        const { semesterId, day, startTime, code, index, localDate } = item;

        // lessonId 패턴: STU_xxx_YYYY-MM_{DAY}{HHMM}{NNN}
        const baseCode = `${day}${startTime.replace(":", "")}`; // 예: "MO1800"
        const suffix = String(index).padStart(3, "0");          // "001" ~ "004"
        const lessonId = `${studentId}_${semesterId}_${baseCode}${suffix}`;

        lessons.push({
          lessonId,
          studentId,
          teacherId,
          code,
          duration,
          localDate,  // "2025-12-01"
          startTime,  // "18:00"
        });
      }
    }

    return lessons;
  }

  const lessonsToCreate = buildLessonsToCreate();

  for (const lesson of lessonsToCreate) {
    const lessonRef = db.collection("lessons").doc(lesson.lessonId);
    const snapshot = await lessonRef.get();

    if (snapshot.exists) {
      console.log(`이미 존재하는 수업: ${lesson.lessonId}`);
      continue;
    }

    const date = kstToUtcDate(lesson.localDate, lesson.startTime);

    const lessonData = {
      code: lesson.code,
      date,
      duration: lesson.duration,
      isRescheduled: false,
      status: "confirmed", // autoFillFutureLessons와 동일
      studentId: lesson.studentId,
      teacherId: lesson.teacherId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // DRY RUN이면 그냥 로그만 찍고, 배치에는 안 넣고 넘어감
    planned.push({
      ...lesson,
      date: date.toISOString(),
    });

    if (DRY_RUN) {
      console.log(
        `[DRY_RUN] would create lesson ${lesson.lessonId} at ${date.toISOString()} for ${lesson.studentId}`
      );
      continue;
    }

    // === 실제 쓰기 (DRY_RUN=false일 때만 실행) ===

    // 1) lessons 컬렉션
    batch.set(lessonRef, lessonData);

    // 2) users/{studentId}/lessons 서브컬렉션
    const studentLessonRef = db
      .collection("users")
      .doc(lesson.studentId)
      .collection("lessons")
      .doc(lesson.lessonId);

    batch.set(studentLessonRef, lessonData);

    // 3) availableSlots/{teacherId} 의 bookedSlots 맵
    const teacherSlotRef = db.collection("availableSlots").doc(lesson.teacherId);

    batch.set(
      teacherSlotRef,
      {
        bookedSlots: {
          [lesson.lessonId]: {
            date,
            duration: lesson.duration,
            isRescheduled: false,
            status: "confirmed",
            studentId: lesson.studentId,
          },
        },
      },
      { merge: true },
    );

    created.push(lesson.lessonId);
  }

  if (!DRY_RUN) {
      await batch.commit();
    }

  return res.json({
      dryRun: DRY_RUN,
      plannedCount: planned.length,
      createdCount: DRY_RUN ? 0 : created.length,
      planned,  // 어떤 것들이 대상인지 확인용
      created,
    });
});

module.exports = { manualCreateRestoredLessons };
