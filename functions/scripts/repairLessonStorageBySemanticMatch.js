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
const FieldValue = admin.firestore.FieldValue;

const SCRIPT_NAME = "repairLessonStorageBySemanticMatch";

const TARGET_TEACHER_ID = "TCH_250313460";
const START_YMD = "2026-05-31";
const END_YMD = "2026-07-01"; // 미포함

const APPLY = process.argv.includes("--apply");
const DRY_RUN = !APPLY;

function getArg(name, defaultValue = "") {
  const prefix = `${name}=`;
  const found = process.argv.find((arg) => arg.startsWith(prefix));
  if (!found) return defaultValue;
  return found.slice(prefix.length);
}

const RUN_ID =
  getArg("--runId") ||
  `repair_semantic_${new Date()
    .toISOString()
    .replaceAll("-", "")
    .replaceAll(":", "")
    .replaceAll(".", "_")}`;

const DAY_MAP = {
  SU: 0,
  SUN: 0,
  SUNDAY: 0,
  일: 0,
  일요일: 0,

  MO: 1,
  MON: 1,
  MONDAY: 1,
  월: 1,
  월요일: 1,

  TU: 2,
  TUE: 2,
  TUESDAY: 2,
  화: 2,
  화요일: 2,

  WE: 3,
  WED: 3,
  WEDNESDAY: 3,
  수: 3,
  수요일: 3,

  TH: 4,
  THU: 4,
  THURSDAY: 4,
  목: 4,
  목요일: 4,

  FR: 5,
  FRI: 5,
  FRIDAY: 5,
  금: 5,
  금요일: 5,

  SA: 6,
  SAT: 6,
  SATURDAY: 6,
  토: 6,
  토요일: 6,
};

function normalizeText(value) {
  return String(value ?? "").trim();
}

function normalizeTime(value) {
  const text = normalizeText(value);
  const [h, m] = text.split(":");

  if (h == null || m == null) return text;

  return `${h.padStart(2, "0")}:${m.padStart(2, "0")}`;
}

function normalizeNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isNaN(n) ? fallback : n;
}

function csvEscape(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

function ymdToKstDate(ymd, time = "00:00") {
  return new Date(`${ymd}T${normalizeTime(time)}:00+09:00`);
}

function addDaysYmd(ymd, days) {
  const date = new Date(`${ymd}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function compareYmd(a, b) {
  return a.localeCompare(b);
}

function getKstWeekdayIndex(ymd) {
  const date = ymdToKstDate(ymd, "12:00");
  return date.getUTCDay();
}

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function dateToKstYmd(value) {
  const date = toDate(value);
  if (!date) return "";

  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function dateToKstTime(value) {
  const date = toDate(value);
  if (!date) return "";

  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Seoul",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function formatKst(value) {
  const date = toDate(value);
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

function sameMinute(a, b) {
  const da = toDate(a);
  const db = toDate(b);

  if (!da || !db) return false;

  return Math.abs(da.getTime() - db.getTime()) < 60 * 1000;
}

function compactTime(time) {
  return normalizeTime(time).replace(":", "");
}

function padSeq(value) {
  return String(value).padStart(3, "0");
}

function isNormalStatus(status) {
  const value = normalizeText(status);
  return value === "confirm" || value === "confirmed";
}

function isNormalLessonData(data) {
  if (!data) return false;

  const code = normalizeText(data.code);
  const isMakeup = code === "-1";
  const isRescheduled = data.isRescheduled === true;

  return isNormalStatus(data.status) && !isMakeup && !isRescheduled;
}

function isNormalBookedSlot(slot) {
  if (!slot) return false;

  const isRescheduled = slot.isRescheduled === true;

  return isNormalStatus(slot.status) && !isRescheduled;
}

function isHolidayYmd(ymd, holidays) {
  for (const holiday of holidays) {
    if (ymd >= holiday.startYmd && ymd <= holiday.endYmd) {
      return true;
    }
  }

  return false;
}

function makeLegacyLessonId(expected) {
  return `${expected.studentId}_${expected.semesterId}_${expected.dayCode}${compactTime(expected.startTime)}${padSeq(expected.sequence)}`;
}

function matchesExpectedLesson(data, expected, fallbackStudentId = "") {
  if (!data) return false;

  const studentId = data.studentId || fallbackStudentId;

  const sameStudent = studentId === expected.studentId;
  const sameTeacher = data.teacherId === expected.teacherId;
  const sameDate = sameMinute(data.date, expected.date);
  const sameDuration = Number(data.duration) === Number(expected.duration);
  const sameCode = normalizeText(data.code) === normalizeText(expected.code);

  return (
    sameStudent &&
    sameTeacher &&
    sameDate &&
    sameDuration &&
    sameCode &&
    isNormalLessonData(data)
  );
}

function matchesExpectedBookedSlot(slot, expected) {
  if (!slot) return false;

  const sameStudent = slot.studentId === expected.studentId;
  const sameDate = sameMinute(slot.date, expected.date);
  const sameDuration = Number(slot.duration) === Number(expected.duration);

  return sameStudent && sameDate && sameDuration && isNormalBookedSlot(slot);
}

function cleanBaseLessonData(data) {
  const base = { ...(data ?? {}) };

  delete base.id;
  delete base.lessonId;

  delete base.recoveryRunId;
  delete base.recoveryScript;
  delete base.recoveryReason;
  delete base.recoveryExpectedYmd;
  delete base.recoveryExpectedStartTime;
  delete base.recoveryExpectedDuration;
  delete base.recoveryExpectedCode;
  delete base.recoveryCreatedAt;

  delete base.semanticRepairRunId;
  delete base.semanticRepairScript;
  delete base.semanticRepairReason;

  delete base.autoFillRunId;
  delete base.autoFillScript;
  delete base.autoFillCreatedAt;

  delete base.rescheduledAt;
  delete base.rescheduledBy;
  delete base.RescheduledBy;
  delete base.originalDate;
  delete base.originalLessonId;

  delete base.canceledAt;
  delete base.cancelledAt;
  delete base.canceledBy;
  delete base.cancelReason;

  return base;
}

function makeLessonData(expected, sourceData) {
  const base = cleanBaseLessonData(sourceData);

  return {
    ...base,

    code: expected.code,
    date: expected.date,
    duration: expected.duration,
    isRescheduled: false,
    status: "confirmed",

    studentId: expected.studentId,
    teacherId: expected.teacherId,

    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),

    recoveryRunId: RUN_ID,
    recoveryScript: SCRIPT_NAME,
    recoveryReason: "repair lesson storage by semantic match",
    recoveryExpectedYmd: expected.ymd,
    recoveryExpectedStartTime: expected.startTime,
    recoveryExpectedDuration: expected.duration,
    recoveryExpectedCode: expected.code,
  };
}

function makeBookedSlotData(expected) {
  return {
    date: expected.date,
    duration: expected.duration,
    isRescheduled: false,
    status: "confirmed",
    studentId: expected.studentId,

    recoveryRunId: RUN_ID,
    recoveryScript: SCRIPT_NAME,
  };
}

async function loadSemesters() {
  const snap = await db.collection("semesters").get();

  const semesters = [];

  snap.forEach((doc) => {
    const data = doc.data();

    const startDate = toDate(data.startDate);
    const endDate = toDate(data.endDate);

    if (!startDate || !endDate) return;

    const holidays = [];

    const rawHolidays = Array.isArray(data.holidayPeriods)
      ? data.holidayPeriods
      : [];

    for (const item of rawHolidays) {
      const start = toDate(item.startDate);
      const end = toDate(item.endDate);

      if (!start || !end) continue;

      holidays.push({
        startYmd: dateToKstYmd(start),
        endYmd: dateToKstYmd(end),
      });
    }

    semesters.push({
      id: doc.id,
      startDate,
      endDate,
      startYmd: dateToKstYmd(startDate),
      endYmd: dateToKstYmd(endDate),
      holidays,
    });
  });

  semesters.sort((a, b) => a.startYmd.localeCompare(b.startYmd));

  return semesters;
}

async function loadStudents() {
  const snap = await db.collection("users").get();

  const students = [];

  snap.forEach((doc) => {
    const data = doc.data();

    if (data.role !== "student") return;
    if (data.teacherId !== TARGET_TEACHER_ID) return;
    if (!Array.isArray(data.weeklySchedule)) return;
    if (data.weeklySchedule.length === 0) return;

    const isArchived =
      data.isArchived === true ||
      data.archived === true ||
      data.status === "archived" ||
      data.deletedAt != null;

    if (isArchived) return;

    students.push({
      id: doc.id,
      name: data.name ?? "",
      teacherId: data.teacherId,
      weeklySchedule: data.weeklySchedule,
    });
  });

  return students;
}

async function loadTopLessonsInRange() {
  const start = admin.firestore.Timestamp.fromDate(
    ymdToKstDate(START_YMD, "00:00")
  );
  const end = admin.firestore.Timestamp.fromDate(
    ymdToKstDate(END_YMD, "00:00")
  );

  const snap = await db
    .collection("lessons")
    .where("date", ">=", start)
    .where("date", "<", end)
    .get();

  const lessons = [];

  snap.forEach((doc) => {
    const data = doc.data();

    if (data.teacherId !== TARGET_TEACHER_ID) return;

    lessons.push({
      id: doc.id,
      ...data,
    });
  });

  return lessons;
}

async function loadSubLessonsByStudent(students) {
  const start = admin.firestore.Timestamp.fromDate(
    ymdToKstDate(START_YMD, "00:00")
  );
  const end = admin.firestore.Timestamp.fromDate(
    ymdToKstDate(END_YMD, "00:00")
  );

  const result = new Map();

  for (const student of students) {
    const snap = await db
      .collection("users")
      .doc(student.id)
      .collection("lessons")
      .where("date", ">=", start)
      .where("date", "<", end)
      .get();

    const lessons = [];

    snap.forEach((doc) => {
      const data = doc.data();

      if (data.teacherId !== TARGET_TEACHER_ID) return;

      lessons.push({
        id: doc.id,
        parentStudentId: student.id,
        ...data,
      });
    });

    result.set(student.id, lessons);
  }

  return result;
}

async function loadAllTopLessonsByStudent(students) {
  const result = new Map();

  for (const student of students) {
    const snap = await db
      .collection("lessons")
      .where("studentId", "==", student.id)
      .get();

    const lessons = [];

    snap.forEach((doc) => {
      lessons.push({
        id: doc.id,
        ...doc.data(),
      });
    });

    result.set(student.id, lessons);
  }

  return result;
}

async function loadBookedSlots() {
  const snap = await db.collection("availableSlots").doc(TARGET_TEACHER_ID).get();

  if (!snap.exists) {
    return {};
  }

  return snap.data().bookedSlots ?? {};
}

function generateExpectedLessons(students, semesters) {
  const expected = [];

  for (const student of students) {
    for (const schedule of student.weeklySchedule) {
      const dayCode = normalizeText(schedule.day).toUpperCase();
      const targetWeekday = DAY_MAP[dayCode];

      if (targetWeekday == null) {
        console.warn(`요일 파싱 실패: ${student.name} ${student.id} day=${schedule.day}`);
        continue;
      }

      const startTime = normalizeTime(schedule.startTime);
      const duration = normalizeNumber(schedule.duration, 0);
      const code = normalizeText(schedule.code);

      for (const semester of semesters) {
        const allDatesInSemester = [];

        let ymd = semester.startYmd;

        while (compareYmd(ymd, addDaysYmd(semester.endYmd, 1)) < 0) {
          const weekday = getKstWeekdayIndex(ymd);

          if (
            weekday === targetWeekday &&
            !isHolidayYmd(ymd, semester.holidays)
          ) {
            allDatesInSemester.push(ymd);
          }

          ymd = addDaysYmd(ymd, 1);
        }

        allDatesInSemester.sort();

        allDatesInSemester.forEach((lessonYmd, index) => {
          const inTargetRange =
            compareYmd(lessonYmd, START_YMD) >= 0 &&
            compareYmd(lessonYmd, END_YMD) < 0;

          if (!inTargetRange) return;

          expected.push({
            studentId: student.id,
            studentName: student.name,
            teacherId: student.teacherId,
            semesterId: semester.id,
            ymd: lessonYmd,
            dayCode,
            startTime,
            duration,
            code,
            sequence: index + 1,
            date: admin.firestore.Timestamp.fromDate(
              ymdToKstDate(lessonYmd, startTime)
            ),
          });
        });
      }
    }
  }

  expected.sort((a, b) => {
    const diff = toDate(a.date).getTime() - toDate(b.date).getTime();
    if (diff !== 0) return diff;
    return a.studentId.localeCompare(b.studentId);
  });

  return expected;
}

function findTemplateLesson(expected, allLessonsByStudent) {
  const lessons = allLessonsByStudent.get(expected.studentId) ?? [];

  const candidates = lessons.filter((lesson) => {
    if (!isNormalLessonData(lesson)) return false;
    if (lesson.teacherId !== expected.teacherId) return false;
    if (Number(lesson.duration) !== Number(expected.duration)) return false;
    if (normalizeText(lesson.code) !== normalizeText(expected.code)) return false;

    return true;
  });

  const sameTime = candidates.filter((lesson) => {
    return dateToKstTime(lesson.date) === expected.startTime;
  });

  return sameTime[0] ?? candidates[0] ?? null;
}

function uniqueValues(values) {
  return [...new Set(values.filter(Boolean))];
}

async function commitInChunks(ops, chunkSize = 450) {
  for (let i = 0; i < ops.length; i += chunkSize) {
    const batch = db.batch();
    const chunk = ops.slice(i, i + chunkSize);

    for (const op of chunk) {
      op(batch);
    }

    await batch.commit();
  }
}

async function main() {
  console.log("semantic match 기반 수업 저장소 복구 시작");
  console.log(`mode: ${DRY_RUN ? "DRY_RUN" : "APPLY"}`);
  console.log(`runId: ${RUN_ID}`);
  console.log(`range: ${START_YMD} <= date < ${END_YMD}`);
  console.log(`teacherId: ${TARGET_TEACHER_ID}`);

  const semesters = await loadSemesters();
  const students = await loadStudents();
  const expectedLessons = generateExpectedLessons(students, semesters);

  const topLessons = await loadTopLessonsInRange();
  const subLessonsByStudent = await loadSubLessonsByStudent(students);
  const allTopLessonsByStudent = await loadAllTopLessonsByStudent(students);
  const bookedSlots = await loadBookedSlots();

  const ops = [];
  const rows = [];

  let okCount = 0;
  let createAllCount = 0;
  let repairPartialCount = 0;
  let conflictCount = 0;

  let createTopCount = 0;
  let createSubCount = 0;
  let createSlotCount = 0;

  for (const expected of expectedLessons) {
    const legacyLessonId = makeLegacyLessonId(expected);

    const topMatches = topLessons.filter((lesson) =>
      matchesExpectedLesson(lesson, expected)
    );

    const subLessons = subLessonsByStudent.get(expected.studentId) ?? [];
    const subMatches = subLessons.filter((lesson) =>
      matchesExpectedLesson(lesson, expected, expected.studentId)
    );

    const slotMatches = Object.entries(bookedSlots)
      .filter(([, slot]) => matchesExpectedBookedSlot(slot, expected))
      .map(([id, slot]) => ({
        id,
        ...slot,
      }));

    let action = "OK";
    let reason = "";

    const duplicateConflict =
      topMatches.length > 1 ||
      subMatches.length > 1 ||
      slotMatches.length > 1;

    const presentIds = uniqueValues([
      ...topMatches.map((item) => item.id),
      ...subMatches.map((item) => item.id),
      ...slotMatches.map((item) => item.id),
    ]);

    const idMismatchConflict = presentIds.length > 1;

    const hasTop = topMatches.length === 1;
    const hasSub = subMatches.length === 1;
    const hasSlot = slotMatches.length === 1;

    const hasAny = hasTop || hasSub || hasSlot;
    const allPresent = hasTop && hasSub && hasSlot;

    let canonicalId = "";
    let sourceData = null;

    if (duplicateConflict) {
      action = "CONFLICT_SKIP";
      reason = "DUPLICATE_SEMANTIC_MATCH";
      conflictCount += 1;
    } else if (idMismatchConflict) {
      action = "CONFLICT_SKIP";
      reason = `ID_MISMATCH: ${presentIds.join(" / ")}`;
      conflictCount += 1;
    } else if (allPresent) {
      action = "OK";
      okCount += 1;
      canonicalId = presentIds[0];
    } else if (hasAny) {
      action = "REPAIR_PARTIAL";
      repairPartialCount += 1;

      canonicalId = presentIds[0];

      sourceData =
        topMatches[0] ||
        subMatches[0] ||
        findTemplateLesson(expected, allTopLessonsByStudent);

      if (!sourceData) {
        action = "CONFLICT_SKIP";
        reason = "SOURCE_TEMPLATE_NOT_FOUND";
        conflictCount += 1;
        repairPartialCount -= 1;
      }
    } else {
      action = "CREATE_ALL";
      createAllCount += 1;

      canonicalId = legacyLessonId;
      sourceData = findTemplateLesson(expected, allTopLessonsByStudent);

      if (!sourceData) {
        action = "CONFLICT_SKIP";
        reason = "TEMPLATE_NOT_FOUND";
        conflictCount += 1;
        createAllCount -= 1;
      } else {
        const topLegacySnap = await db.collection("lessons").doc(canonicalId).get();
        const subLegacySnap = await db
          .collection("users")
          .doc(expected.studentId)
          .collection("lessons")
          .doc(canonicalId)
          .get();

        const slotLegacyExists = bookedSlots[canonicalId] != null;

        if (topLegacySnap.exists || subLegacySnap.exists || slotLegacyExists) {
          action = "CONFLICT_SKIP";
          reason = "LEGACY_ID_ALREADY_EXISTS_BUT_NOT_SEMANTIC_MATCH";
          conflictCount += 1;
          createAllCount -= 1;
        }
      }
    }

    let willCreateTop = false;
    let willCreateSub = false;
    let willCreateSlot = false;

    if (action === "REPAIR_PARTIAL" || action === "CREATE_ALL") {
      const lessonData = makeLessonData(expected, sourceData);
      const slotData = makeBookedSlotData(expected);

      const topRef = db.collection("lessons").doc(canonicalId);
      const subRef = db
        .collection("users")
        .doc(expected.studentId)
        .collection("lessons")
        .doc(canonicalId);
      const slotRef = db.collection("availableSlots").doc(expected.teacherId);

      willCreateTop = !hasTop;
      willCreateSub = !hasSub;
      willCreateSlot = !hasSlot;

      if (willCreateTop) {
        createTopCount += 1;
        ops.push((batch) => batch.set(topRef, lessonData));
      }

      if (willCreateSub) {
        createSubCount += 1;
        ops.push((batch) => batch.set(subRef, lessonData));
      }

      if (willCreateSlot) {
        createSlotCount += 1;
        ops.push((batch) =>
          batch.set(
            slotRef,
            {
              bookedSlots: {
                [canonicalId]: slotData,
              },
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          )
        );
      }
    }

    rows.push({
      runId: RUN_ID,
      mode: DRY_RUN ? "DRY_RUN" : "APPLY",
      action,
      reason,

      legacyLessonId,
      canonicalId,

      semesterId: expected.semesterId,
      sequence: expected.sequence,

      studentName: expected.studentName,
      studentId: expected.studentId,
      teacherId: expected.teacherId,

      expectedYmd: expected.ymd,
      expectedDateKst: formatKst(expected.date),
      expectedDay: expected.dayCode,
      expectedStartTime: expected.startTime,
      expectedDuration: expected.duration,
      expectedCode: expected.code,

      topMatchCount: topMatches.length,
      subMatchCount: subMatches.length,
      slotMatchCount: slotMatches.length,

      topMatchIds: topMatches.map((item) => item.id).join(" / "),
      subMatchIds: subMatches.map((item) => item.id).join(" / "),
      slotMatchIds: slotMatches.map((item) => item.id).join(" / "),

      willCreateTop,
      willCreateSub,
      willCreateSlot,

      topPath: willCreateTop ? `lessons/${canonicalId}` : "",
      subPath: willCreateSub
        ? `users/${expected.studentId}/lessons/${canonicalId}`
        : "",
      bookedSlotPath: willCreateSlot
        ? `availableSlots/${expected.teacherId}.bookedSlots.${canonicalId}`
        : "",
    });
  }

  if (!DRY_RUN && ops.length > 0) {
    await commitInChunks(ops);
  }

  const outputPath = path.join(
    __dirname,
    `${DRY_RUN ? "dryrun" : "applied"}_${RUN_ID}.csv`
  );

  const headers = [
    "runId",
    "mode",
    "action",
    "reason",

    "legacyLessonId",
    "canonicalId",

    "semesterId",
    "sequence",

    "studentName",
    "studentId",
    "teacherId",

    "expectedYmd",
    "expectedDateKst",
    "expectedDay",
    "expectedStartTime",
    "expectedDuration",
    "expectedCode",

    "topMatchCount",
    "subMatchCount",
    "slotMatchCount",

    "topMatchIds",
    "subMatchIds",
    "slotMatchIds",

    "willCreateTop",
    "willCreateSub",
    "willCreateSlot",

    "topPath",
    "subPath",
    "bookedSlotPath",
  ];

  const csv = [
    headers.join(","),
    ...rows.map((row) =>
      headers.map((header) => csvEscape(row[header])).join(",")
    ),
  ].join("\n");

  fs.writeFileSync(outputPath, csv, "utf8");

  console.log("");
  console.log("복구 계획 요약");
  console.log(`전체 예상 수업 수: ${expectedLessons.length}`);
  console.log(`OK 수업 수: ${okCount}`);
  console.log(`전체 신규 생성 수업 수: ${createAllCount}`);
  console.log(`일부 저장소 보정 수업 수: ${repairPartialCount}`);
  console.log(`충돌 스킵 수업 수: ${conflictCount}`);
  console.log(`lessons 생성 예정/완료: ${createTopCount}`);
  console.log(`users/{studentId}/lessons 생성 예정/완료: ${createSubCount}`);
  console.log(`bookedSlots 생성 예정/완료: ${createSlotCount}`);
  console.log(`결과 CSV: ${outputPath}`);

  if (DRY_RUN) {
    console.log("");
    console.log("실제 반영하려면:");
    console.log(`node scripts/repairLessonStorageBySemanticMatch.js --apply --runId=${RUN_ID}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});