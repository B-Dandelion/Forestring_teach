const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const serviceAccountPath = path.resolve(
  __dirname,
  "../serviceAccountKey.json"
);

if (!fs.existsSync(serviceAccountPath)) {
  throw new Error(`serviceAccountKey.json 파일을 찾을 수 없음: ${serviceAccountPath}`);
}

const serviceAccount = require(serviceAccountPath);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id,
  });
}

const db = admin.firestore();

// 2026-05-31 00:00:00 KST
const CUTOFF = admin.firestore.Timestamp.fromDate(
  new Date("2026-05-30T15:00:00.000Z")
);

function isNormalLesson(data) {
  const status = String(data.status ?? "").trim();
  const code = String(data.code ?? "").trim();

  const isNormalStatus = status === "confirm" || status === "confirmed";
  const isMakeup = code === "-1";
  const isRescheduled = data.isRescheduled === true;

  return isNormalStatus && !isMakeup && !isRescheduled;
}

function getDateValue(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function formatKst(date) {
  if (!date) return "";
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function scheduleToText(schedule) {
  if (!Array.isArray(schedule)) return "";

  return schedule
    .map((s) => {
      const day = s.day ?? "";
      const time = s.startTime ?? "";
      const duration = s.duration ?? "";
      const code = s.code ?? "";
      return `${day} ${time} ${duration}분 code:${code}`;
    })
    .join(" / ");
}

function csvEscape(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

async function main() {
  console.log("학생 목록 조회 중...");

  const usersSnap = await db.collection("users").get();

  const students = [];

  usersSnap.forEach((doc) => {
    const data = doc.data();

    const role = data.role;
    const weeklySchedule = data.weeklySchedule;

    const isStudent = role === "student";
    const hasSchedule = Array.isArray(weeklySchedule) && weeklySchedule.length > 0;

    const isArchived =
      data.isArchived === true ||
      data.archived === true ||
      data.status === "archived" ||
      data.deletedAt != null;

    if (!isStudent || !hasSchedule || isArchived) return;

    students.push({
      id: doc.id,
      name: data.name ?? "",
      teacherId: data.teacherId ?? data.teacherID ?? "",
      weeklySchedule,
    });
  });

  console.log(`검사 대상 학생 수: ${students.length}`);

  console.log("2026-05-31 이후 lessons 조회 중...");

  const lessonsSnap = await db
    .collection("lessons")
    .where("date", ">=", CUTOFF)
    .get();

  const normalLessonsByStudent = new Map();
  const nonNormalLessonsByStudent = new Map();
  const allFutureLessonsByStudent = new Map();
  const normalLessons = [];

  lessonsSnap.forEach((doc) => {
    const data = doc.data();
    const studentId = data.studentId;
    if (!studentId) return;

    const item = {
      id: doc.id,
      ...data,
      dateObj: getDateValue(data.date),
    };

    if (!allFutureLessonsByStudent.has(studentId)) {
      allFutureLessonsByStudent.set(studentId, []);
    }
    allFutureLessonsByStudent.get(studentId).push(item);

    if (isNormalLesson(data)) {
      if (!normalLessonsByStudent.has(studentId)) {
        normalLessonsByStudent.set(studentId, []);
      }
      normalLessonsByStudent.get(studentId).push(item);
      normalLessons.push(item);
    } else {
      if (!nonNormalLessonsByStudent.has(studentId)) {
        nonNormalLessonsByStudent.set(studentId, []);
      }
      nonNormalLessonsByStudent.get(studentId).push(item);
    }
  });

  console.log(`2026-05-31 이후 전체 lessons 수: ${lessonsSnap.size}`);
  console.log(`2026-05-31 이후 정상 정규수업 수: ${normalLessons.length}`);

  const reportRows = students.map((student) => {
    const normal = normalLessonsByStudent.get(student.id) ?? [];
    const nonNormal = nonNormalLessonsByStudent.get(student.id) ?? [];
    const all = allFutureLessonsByStudent.get(student.id) ?? [];

    normal.sort((a, b) => {
      const aTime = a.dateObj ? a.dateObj.getTime() : 0;
      const bTime = b.dateObj ? b.dateObj.getTime() : 0;
      return aTime - bTime;
    });

    return {
      studentId: student.id,
      name: student.name,
      teacherId: student.teacherId,
      weeklySchedule: scheduleToText(student.weeklySchedule),
      futureAllCount: all.length,
      futureNormalCount: normal.length,
      futureNonNormalCount: nonNormal.length,
      firstNormalDate: formatKst(normal[0]?.dateObj),
      lastNormalDate: formatKst(normal[normal.length - 1]?.dateObj),
    };
  });

  const missingNormalRows = reportRows.filter((row) => row.futureNormalCount === 0);
  const lowNormalRows = reportRows.filter(
    (row) => row.futureNormalCount > 0 && row.futureNormalCount < 4
  );

  console.log("");
  console.log("정상 정규수업 0개 학생:");
  console.table(
    missingNormalRows.map((row) => ({
      name: row.name,
      studentId: row.studentId,
      teacherId: row.teacherId,
      all: row.futureAllCount,
      normal: row.futureNormalCount,
      nonNormal: row.futureNonNormalCount,
      schedule: row.weeklySchedule,
    }))
  );

  console.log("");
  console.log("정상 정규수업은 있으나 4개 미만인 학생:");
  console.table(
    lowNormalRows.map((row) => ({
      name: row.name,
      studentId: row.studentId,
      teacherId: row.teacherId,
      normal: row.futureNormalCount,
      first: row.firstNormalDate,
      last: row.lastNormalDate,
      schedule: row.weeklySchedule,
    }))
  );

  console.log("");
  console.log("availableSlots bookedSlots 누락 여부 확인 중...");

  const teacherIds = [
    ...new Set(
      normalLessons
        .map((lesson) => lesson.teacherId)
        .filter((teacherId) => typeof teacherId === "string" && teacherId.length > 0)
    ),
  ];

  const bookedSlotsByTeacher = new Map();

  for (const teacherId of teacherIds) {
    const teacherSlotDoc = await db.collection("availableSlots").doc(teacherId).get();
    const bookedSlots = teacherSlotDoc.exists
      ? teacherSlotDoc.data().bookedSlots ?? {}
      : {};
    bookedSlotsByTeacher.set(teacherId, bookedSlots);
  }

  const missingBookedSlots = [];

  for (const lesson of normalLessons) {
    const bookedSlots = bookedSlotsByTeacher.get(lesson.teacherId) ?? {};
    const existsInBookedSlots = bookedSlots[lesson.id] != null;

    if (!existsInBookedSlots) {
      missingBookedSlots.push({
        lessonId: lesson.id,
        studentId: lesson.studentId,
        studentName: lesson.studentName ?? "",
        teacherId: lesson.teacherId,
        date: formatKst(lesson.dateObj),
      });
    }
  }

  console.log("");
  console.log(`bookedSlots 누락 정상수업 수: ${missingBookedSlots.length}`);

  if (missingBookedSlots.length > 0) {
    console.table(missingBookedSlots.slice(0, 50));
  }

  const outputPath = path.join(
    __dirname,
    "audit_missing_normal_lessons_after_20260531.csv"
  );

  const headers = [
    "studentId",
    "name",
    "teacherId",
    "weeklySchedule",
    "futureAllCount",
    "futureNormalCount",
    "futureNonNormalCount",
    "firstNormalDate",
    "lastNormalDate",
  ];

  const csv = [
    headers.join(","),
    ...reportRows.map((row) =>
      headers.map((header) => csvEscape(row[header])).join(",")
    ),
  ].join("\n");

  fs.writeFileSync(outputPath, csv, "utf8");

  console.log("");
  console.log(`CSV 저장 완료: ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});