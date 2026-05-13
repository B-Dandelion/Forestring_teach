const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const serviceAccountPath = path.resolve(__dirname, "../serviceAccountKey.json");

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
const START = admin.firestore.Timestamp.fromDate(
  new Date("2026-05-30T15:00:00.000Z")
);

// 필요하면 끝 날짜도 제한 가능.
// 지금은 넉넉하게 2026-09-01 00:00:00 KST까지 봄.
const END = admin.firestore.Timestamp.fromDate(
  new Date("2026-08-31T15:00:00.000Z")
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

function csvEscape(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

function getSlotDate(slot) {
  if (!slot) return null;

  return (
    getDateValue(slot.date) ||
    getDateValue(slot.startTime) ||
    getDateValue(slot.startDate) ||
    getDateValue(slot.lessonDate) ||
    null
  );
}

function isSameMinute(a, b) {
  if (!a || !b) return false;
  const diff = Math.abs(a.getTime() - b.getTime());
  return diff < 60 * 1000;
}

async function main() {
  console.log("2026-05-31 이후 정상 lessons 조회 중...");

  const lessonsSnap = await db
    .collection("lessons")
    .where("date", ">=", START)
    .where("date", "<", END)
    .get();

  const normalLessons = [];

  lessonsSnap.forEach((doc) => {
    const data = doc.data();

    if (!isNormalLesson(data)) return;

    normalLessons.push({
      lessonId: doc.id,
      ...data,
      dateObj: getDateValue(data.date),
    });
  });

  normalLessons.sort((a, b) => {
    const aTime = a.dateObj ? a.dateObj.getTime() : 0;
    const bTime = b.dateObj ? b.dateObj.getTime() : 0;
    return aTime - bTime;
  });

  console.log(`정상 lessons 수: ${normalLessons.length}`);

  const teacherIds = [
    ...new Set(
      normalLessons
        .map((lesson) => lesson.teacherId)
        .filter((teacherId) => typeof teacherId === "string" && teacherId.length > 0)
    ),
  ];

  console.log(`검사 teacher 수: ${teacherIds.length}`);
  console.log(teacherIds);

  const bookedSlotsByTeacher = new Map();

  for (const teacherId of teacherIds) {
    const slotDoc = await db.collection("availableSlots").doc(teacherId).get();

    if (!slotDoc.exists) {
      bookedSlotsByTeacher.set(teacherId, {});
      continue;
    }

    const bookedSlots = slotDoc.data().bookedSlots ?? {};
    bookedSlotsByTeacher.set(teacherId, bookedSlots);
  }

  const rows = [];

  for (const lesson of normalLessons) {
    const bookedSlots = bookedSlotsByTeacher.get(lesson.teacherId) ?? {};

    const directSlot = bookedSlots[lesson.lessonId];

    let hasBookedSlot = directSlot != null;
    let matchType = hasBookedSlot ? "lessonId" : "";

    // lessonId 키로 없더라도, 혹시 다른 키로 들어가 있는 경우를 대비해
    // studentId + date 같은 시각 기준으로 한 번 더 탐색
    if (!hasBookedSlot) {
      for (const [slotId, slot] of Object.entries(bookedSlots)) {
        const slotDate = getSlotDate(slot);

        const sameStudent =
          slot.studentId === lesson.studentId ||
          slot.Student_id === lesson.studentId ||
          slot.studentID === lesson.studentId;

        const sameDate = isSameMinute(slotDate, lesson.dateObj);

        if (sameStudent && sameDate) {
          hasBookedSlot = true;
          matchType = `sameStudentAndDate:${slotId}`;
          break;
        }
      }
    }

    rows.push({
      issue: hasBookedSlot ? "" : "MISSING_BOOKED_SLOT",
      lessonId: lesson.lessonId,
      studentId: lesson.studentId,
      studentName: lesson.studentName ?? lesson.name ?? "",
      teacherId: lesson.teacherId,
      dateKst: formatKst(lesson.dateObj),
      status: lesson.status ?? "",
      code: lesson.code ?? "",
      isRescheduled: lesson.isRescheduled ?? "",
      hasBookedSlot,
      matchType,
    });
  }

  const missingRows = rows.filter((row) => row.issue === "MISSING_BOOKED_SLOT");

  console.log("");
  console.log(`bookedSlots 누락 정상수업 수: ${missingRows.length}`);

  if (missingRows.length > 0) {
    console.table(
      missingRows.slice(0, 100).map((row) => ({
        date: row.dateKst,
        studentName: row.studentName,
        studentId: row.studentId,
        teacherId: row.teacherId,
        lessonId: row.lessonId,
      }))
    );
  }

  const outputPath = path.join(
    __dirname,
    "audit_booked_slots_after_20260531.csv"
  );

  const headers = [
    "issue",
    "lessonId",
    "studentId",
    "studentName",
    "teacherId",
    "dateKst",
    "status",
    "code",
    "isRescheduled",
    "hasBookedSlot",
    "matchType",
  ];

  const csv = [
    headers.join(","),
    ...rows.map((row) => headers.map((header) => csvEscape(row[header])).join(",")),
  ].join("\n");

  fs.writeFileSync(outputPath, csv, "utf8");

  console.log("");
  console.log(`CSV 저장 완료: ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});