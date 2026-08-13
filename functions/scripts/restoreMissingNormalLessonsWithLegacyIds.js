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

const SCRIPT_NAME = "restoreMissingNormalLessonsWithLegacyIds";

const DEFAULT_CSV_PATH = path.resolve(
  __dirname,
  "audit_expected_schedule_integrity_issues_only.csv"
);

function getArg(name, defaultValue = "") {
  const prefix = `${name}=`;
  const found = process.argv.find((arg) => arg.startsWith(prefix));
  if (!found) return defaultValue;
  return found.slice(prefix.length);
}

function hasFlag(name) {
  return process.argv.includes(name);
}

const APPLY = hasFlag("--apply");
const DRY_RUN = !APPLY;

const CSV_PATH = path.resolve(getArg("--csv", DEFAULT_CSV_PATH));

const RUN_ID =
  getArg("--runId") ||
  `restore_legacy_ids_${new Date()
    .toISOString()
    .replaceAll("-", "")
    .replaceAll(":", "")
    .replaceAll(".", "_")}`;

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let inQuotes = false;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    const next = text[i + 1];

    if (char === '"' && inQuotes && next === '"') {
      field += '"';
      i += 1;
      continue;
    }

    if (char === '"') {
      inQuotes = !inQuotes;
      continue;
    }

    if (char === "," && !inQuotes) {
      row.push(field);
      field = "";
      continue;
    }

    if ((char === "\n" || char === "\r") && !inQuotes) {
      if (char === "\r" && next === "\n") i += 1;

      row.push(field);

      if (row.some((value) => String(value).trim() !== "")) {
        rows.push(row);
      }

      row = [];
      field = "";
      continue;
    }

    field += char;
  }

  if (field.length > 0 || row.length > 0) {
    row.push(field);

    if (row.some((value) => String(value).trim() !== "")) {
      rows.push(row);
    }
  }

  if (rows.length === 0) return [];

  const headers = rows[0].map((header) => header.trim());

  return rows.slice(1).map((values) => {
    const item = {};
    headers.forEach((header, index) => {
      item[header] = values[index] ?? "";
    });
    return item;
  });
}

function csvEscape(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

function normalizeText(value) {
  return String(value ?? "").trim();
}

function normalizeNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function normalizeTime(value) {
  const text = String(value ?? "").trim();
  const [rawHour, rawMinute] = text.split(":");

  if (rawHour == null || rawMinute == null) return text;

  return `${rawHour.padStart(2, "0")}:${rawMinute.padStart(2, "0")}`;
}

function timeCompact(hhmm) {
  return normalizeTime(hhmm).replace(":", "");
}

function padSeq(value) {
  return String(value).padStart(3, "0");
}

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function kstDateTimeToUtcDate(ymd, hhmm) {
  return new Date(`${ymd}T${normalizeTime(hhmm)}:00+09:00`);
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

function getYmdKst(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function getTimeKst(date) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Seoul",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function isSameMinute(a, b) {
  if (!a || !b) return false;
  return Math.abs(a.getTime() - b.getTime()) < 60 * 1000;
}

function isNormalLesson(data) {
  const status = normalizeText(data.status);
  const code = normalizeText(data.code);

  const isNormalStatus = status === "confirm" || status === "confirmed";
  const isMakeup = code === "-1";
  const isRescheduled = data.isRescheduled === true;

  return isNormalStatus && !isMakeup && !isRescheduled;
}

function getLessonDate(data) {
  return (
    toDate(data.date) ||
    toDate(data.startTime) ||
    toDate(data.startDate) ||
    toDate(data.lessonDate) ||
    null
  );
}

function getDayCodeFromRow(row) {
  return normalizeText(row.expectedDay).toUpperCase();
}

function makeLegacyPrefix(row, semesterId) {
  const studentId = normalizeText(row.studentId);
  const dayCode = getDayCodeFromRow(row);
  const compactTime = timeCompact(row.expectedStartTime);

  return `${studentId}_${semesterId}_${dayCode}${compactTime}`;
}

function parseLegacySeqFromId(lessonId, prefix) {
  if (!lessonId.startsWith(prefix)) return null;

  const tail = lessonId.slice(prefix.length);
  if (!/^\d{3}$/.test(tail)) return null;

  return Number(tail);
}

function makeLegacyLessonId(row, semesterId, sequence) {
  const prefix = makeLegacyPrefix(row, semesterId);
  return `${prefix}${padSeq(sequence)}`;
}

function isDateInsideSemester(date, semester) {
  const start = semester.startDate;
  const endExclusive = new Date(semester.endDate.getTime());
  endExclusive.setDate(endExclusive.getDate() + 1);

  return date >= start && date < endExclusive;
}

async function loadSemesters() {
  const snap = await db.collection("semesters").get();

  const semesters = [];

  snap.forEach((doc) => {
    const data = doc.data();

    const startDate = toDate(data.startDate);
    const endDate = toDate(data.endDate);

    if (!startDate || !endDate) return;

    semesters.push({
      id: doc.id,
      startDate,
      endDate,
    });
  });

  semesters.sort((a, b) => a.startDate.getTime() - b.startDate.getTime());

  return semesters;
}

function findSemesterIdForDate(date, semesters) {
  const found = semesters.find((semester) => isDateInsideSemester(date, semester));

  if (!found) {
    throw new Error(`해당 날짜가 속한 학기를 찾을 수 없음: ${formatKst(date)}`);
  }

  return found.id;
}

async function loadStudents(studentIds) {
  const result = new Map();

  for (const studentId of studentIds) {
    const snap = await db.collection("users").doc(studentId).get();

    if (!snap.exists) {
      result.set(studentId, null);
      continue;
    }

    result.set(studentId, {
      id: snap.id,
      ...snap.data(),
    });
  }

  return result;
}

async function loadTopLessonsByStudent(studentIds) {
  const result = new Map();

  for (const studentId of studentIds) {
    const snap = await db
      .collection("lessons")
      .where("studentId", "==", studentId)
      .get();

    const lessons = [];

    snap.forEach((doc) => {
      lessons.push({
        id: doc.id,
        ...doc.data(),
      });
    });

    result.set(studentId, lessons);
  }

  return result;
}

function findTemplateLesson(row, templates) {
  const teacherId = normalizeText(row.teacherId);
  const duration = normalizeNumber(row.expectedDuration, 0);
  const startTime = normalizeTime(row.expectedStartTime);
  const code = normalizeText(row.expectedCode);

  const normalTemplates = templates.filter((lesson) => {
    if (!isNormalLesson(lesson)) return false;
    if (normalizeText(lesson.teacherId) !== teacherId) return false;

    const lessonDuration = normalizeNumber(lesson.duration, duration);
    return lessonDuration === duration;
  });

  const sameCodeAndTime = normalTemplates.filter((lesson) => {
    const date = getLessonDate(lesson);
    return normalizeText(lesson.code) === code && getTimeKst(date) === startTime;
  });

  if (sameCodeAndTime.length > 0) return sameCodeAndTime[0];

  const sameTime = normalTemplates.filter((lesson) => {
    const date = getLessonDate(lesson);
    return getTimeKst(date) === startTime;
  });

  if (sameTime.length > 0) return sameTime[0];

  return normalTemplates[0] ?? null;
}

function buildGroupKey(row, semesterId) {
  return [
    normalizeText(row.studentId),
    semesterId,
    getDayCodeFromRow(row),
    timeCompact(row.expectedStartTime),
  ].join("|");
}

function buildSequenceMaps(targetRows, existingLessonsByStudent, semesters) {
  const groupDates = new Map();

  function addDateToGroup(groupKey, ymd) {
    if (!groupDates.has(groupKey)) {
      groupDates.set(groupKey, new Set());
    }

    groupDates.get(groupKey).add(ymd);
  }

  for (const row of targetRows) {
    const dateObj = kstDateTimeToUtcDate(row.expectedYmd, row.expectedStartTime);
    const semesterId = findSemesterIdForDate(dateObj, semesters);
    const groupKey = buildGroupKey(row, semesterId);

    addDateToGroup(groupKey, normalizeText(row.expectedYmd));
  }

  for (const [studentId, lessons] of existingLessonsByStudent.entries()) {
    for (const lesson of lessons) {
      const date = getLessonDate(lesson);
      if (!date) continue;

      const semester = semesters.find((item) => isDateInsideSemester(date, item));
      if (!semester) continue;

      const ymd = getYmdKst(date);
      const time = getTimeKst(date);

      const id = lesson.id;

      const regex = new RegExp(
        `^${studentId}_${semester.id}_([A-Z]{2})(\\d{4})(\\d{3})$`
      );

      const match = id.match(regex);
      if (!match) continue;

      const dayCode = match[1];
      const compactTime = match[2];

      if (compactTime !== time.replace(":", "")) continue;

      const fakeRow = {
        studentId,
        expectedDay: dayCode,
        expectedStartTime: time,
      };

      const groupKey = buildGroupKey(fakeRow, semester.id);

      addDateToGroup(groupKey, ymd);
    }
  }

  const sequenceByGroupAndYmd = new Map();

  for (const [groupKey, ymdSet] of groupDates.entries()) {
    const sortedYmds = [...ymdSet].sort();

    const seqMap = new Map();

    sortedYmds.forEach((ymd, index) => {
      seqMap.set(ymd, index + 1);
    });

    sequenceByGroupAndYmd.set(groupKey, seqMap);
  }

  return sequenceByGroupAndYmd;
}

function removeUndefinedDeep(value) {
  if (Array.isArray(value)) {
    return value.map(removeUndefinedDeep);
  }

  if (value && typeof value === "object" && !(value instanceof Date)) {
    if (typeof value.toDate === "function") return value;

    const cleaned = {};

    for (const [key, innerValue] of Object.entries(value)) {
      if (innerValue === undefined) continue;
      cleaned[key] = removeUndefinedDeep(innerValue);
    }

    return cleaned;
  }

  return value;
}

function makeLessonData(row, student, template) {
  const studentId = normalizeText(row.studentId);
  const studentName = normalizeText(row.studentName) || normalizeText(student?.name);
  const teacherId = normalizeText(row.teacherId);
  const expectedYmd = normalizeText(row.expectedYmd);
  const expectedStartTime = normalizeTime(row.expectedStartTime);
  const duration = normalizeNumber(row.expectedDuration, 0);
  const code = normalizeText(row.expectedCode);

  const date = admin.firestore.Timestamp.fromDate(
    kstDateTimeToUtcDate(expectedYmd, expectedStartTime)
  );

  const base = template ? { ...template } : {};

  delete base.id;
  delete base.lessonId;
  delete base.createdAt;
  delete base.updatedAt;
  delete base.canceledAt;
  delete base.cancelledAt;
  delete base.cancelReason;
  delete base.canceledBy;
  delete base.rescheduledAt;
  delete base.rescheduledBy;
  delete base.RescheduledBy;
  delete base.originalDate;
  delete base.originalLessonId;
  delete base.recoveryRunId;
  delete base.recoveryScript;
  delete base.recoveryReason;
  delete base.recoveryCreatedAt;

  const status =
    normalizeText(template?.status) === "confirm" ||
    normalizeText(template?.status) === "confirmed"
      ? normalizeText(template.status)
      : "confirmed";

  return removeUndefinedDeep({
    ...base,

    code,
    date,
    duration,
    isRescheduled: false,
    status,

    studentId,
    studentName,
    teacherId,

    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),

    recoveryRunId: RUN_ID,
    recoveryScript: SCRIPT_NAME,
    recoveryReason: "restore missing regular lessons with legacy lessonId",
    recoveryExpectedYmd: expectedYmd,
    recoveryExpectedStartTime: expectedStartTime,
    recoveryExpectedDuration: duration,
    recoveryExpectedCode: code,
    recoveryCreatedAt: FieldValue.serverTimestamp(),
  });
}

function makeBookedSlotData(row) {
  const studentId = normalizeText(row.studentId);
  const expectedYmd = normalizeText(row.expectedYmd);
  const expectedStartTime = normalizeTime(row.expectedStartTime);
  const duration = normalizeNumber(row.expectedDuration, 0);

  return removeUndefinedDeep({
    date: admin.firestore.Timestamp.fromDate(
      kstDateTimeToUtcDate(expectedYmd, expectedStartTime)
    ),
    duration,
    isRescheduled: false,
    status: "confirmed",
    studentId,

    recoveryRunId: RUN_ID,
    recoveryScript: SCRIPT_NAME,
    recoveryCreatedAt: FieldValue.serverTimestamp(),
  });
}

async function checkExistingTargets(row, lessonId) {
  const studentId = normalizeText(row.studentId);
  const teacherId = normalizeText(row.teacherId);

  const topRef = db.collection("lessons").doc(lessonId);
  const subRef = db
    .collection("users")
    .doc(studentId)
    .collection("lessons")
    .doc(lessonId);
  const slotRef = db.collection("availableSlots").doc(teacherId);

  const [topSnap, subSnap, slotSnap] = await Promise.all([
    topRef.get(),
    subRef.get(),
    slotRef.get(),
  ]);

  const bookedSlots = slotSnap.exists ? slotSnap.data().bookedSlots ?? {} : {};
  const slotExists = bookedSlots[lessonId] != null;

  return {
    topRef,
    subRef,
    slotRef,
    topExists: topSnap.exists,
    subExists: subSnap.exists,
    slotExists,
  };
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
  console.log("기존 lessonId 규칙 기반 누락 정규수업 복구 시작");
  console.log(`mode: ${DRY_RUN ? "DRY_RUN" : "APPLY"}`);
  console.log(`runId: ${RUN_ID}`);
  console.log(`csv: ${CSV_PATH}`);

  if (!fs.existsSync(CSV_PATH)) {
    throw new Error(`CSV 파일을 찾을 수 없음: ${CSV_PATH}`);
  }

  const csvText = fs.readFileSync(CSV_PATH, "utf8");
  const allRows = parseCsv(csvText);

  const targetRows = allRows.filter((row) => normalizeText(row.issue) === "ALL_3_MISSING");

  console.log(`CSV 전체 행 수: ${allRows.length}`);
  console.log(`복구 대상 ALL_3_MISSING 행 수: ${targetRows.length}`);

  if (targetRows.length === 0) {
    console.log("복구 대상 없음");
    return;
  }

  const semesters = await loadSemesters();

  const studentIds = [
    ...new Set(targetRows.map((row) => normalizeText(row.studentId)).filter(Boolean)),
  ];

  const studentsById = await loadStudents(studentIds);
  const existingLessonsByStudent = await loadTopLessonsByStudent(studentIds);

  const sequenceMaps = buildSequenceMaps(targetRows, existingLessonsByStudent, semesters);

  const rows = [];
  const ops = [];

  let skipCount = 0;
  let createTopCount = 0;
  let createSubCount = 0;
  let createBookedSlotCount = 0;

  for (const row of targetRows) {
    const studentId = normalizeText(row.studentId);
    const student = studentsById.get(studentId);
    const existingLessons = existingLessonsByStudent.get(studentId) ?? [];

    const dateObj = kstDateTimeToUtcDate(row.expectedYmd, row.expectedStartTime);
    const semesterId = findSemesterIdForDate(dateObj, semesters);

    const groupKey = buildGroupKey(row, semesterId);
    const seqMap = sequenceMaps.get(groupKey);
    const sequence = seqMap?.get(normalizeText(row.expectedYmd));

    const lessonId = sequence
      ? makeLegacyLessonId(row, semesterId, sequence)
      : "";

    const template = findTemplateLesson(row, existingLessons);

    const skipReasons = [];

    if (!student) skipReasons.push("STUDENT_DOC_NOT_FOUND");
    if (!template) skipReasons.push("TEMPLATE_LESSON_NOT_FOUND");
    if (!lessonId) skipReasons.push("LEGACY_LESSON_ID_BUILD_FAILED");

    const canCreate = student && template && lessonId;

    let existing = null;

    if (canCreate) {
      existing = await checkExistingTargets(row, lessonId);
    }

    const shouldCreateTop = canCreate && !existing.topExists;
    const shouldCreateSub = canCreate && !existing.subExists;
    const shouldCreateBookedSlot = canCreate && !existing.slotExists;

    if (!canCreate) {
      skipCount += 1;
    }

    const lessonData = canCreate ? makeLessonData(row, student, template) : null;
    const bookedSlotData = canCreate ? makeBookedSlotData(row) : null;

    if (canCreate) {
      if (shouldCreateTop) {
        ops.push((batch) => batch.set(existing.topRef, lessonData));
        createTopCount += 1;
      }

      if (shouldCreateSub) {
        ops.push((batch) => batch.set(existing.subRef, lessonData));
        createSubCount += 1;
      }

      if (shouldCreateBookedSlot) {
        ops.push((batch) =>
          batch.set(
            existing.slotRef,
            {
              bookedSlots: {
                [lessonId]: bookedSlotData,
              },
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          )
        );
        createBookedSlotCount += 1;
      }
    }

    rows.push({
      runId: RUN_ID,
      mode: DRY_RUN ? "DRY_RUN" : "APPLY",
      action: canCreate ? "RESTORE" : "SKIP",
      skipReason: skipReasons.join(" / "),

      lessonId,
      semesterId,
      sequence,

      studentName: normalizeText(row.studentName),
      studentId,
      teacherId: normalizeText(row.teacherId),
      expectedDateKst: normalizeText(row.expectedDateKst),
      expectedYmd: normalizeText(row.expectedYmd),
      expectedDay: normalizeText(row.expectedDay),
      expectedStartTime: normalizeText(row.expectedStartTime),
      expectedDuration: normalizeText(row.expectedDuration),
      expectedCode: normalizeText(row.expectedCode),

      templateLessonId: template?.id ?? "",

      topExistsBefore: existing?.topExists ?? "",
      subExistsBefore: existing?.subExists ?? "",
      bookedSlotExistsBefore: existing?.slotExists ?? "",

      willCreateTop: shouldCreateTop,
      willCreateSub: shouldCreateSub,
      willCreateBookedSlot: shouldCreateBookedSlot,
    });
  }

  if (!DRY_RUN) {
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
    "skipReason",

    "lessonId",
    "semesterId",
    "sequence",

    "studentName",
    "studentId",
    "teacherId",
    "expectedDateKst",
    "expectedYmd",
    "expectedDay",
    "expectedStartTime",
    "expectedDuration",
    "expectedCode",

    "templateLessonId",

    "topExistsBefore",
    "subExistsBefore",
    "bookedSlotExistsBefore",

    "willCreateTop",
    "willCreateSub",
    "willCreateBookedSlot",
  ];

  const outCsv = [
    headers.join(","),
    ...rows.map((row) => headers.map((header) => csvEscape(row[header])).join(",")),
  ].join("\n");

  fs.writeFileSync(outputPath, outCsv, "utf8");

  console.log("");
  console.log("복구 계획 요약");
  console.log(`mode: ${DRY_RUN ? "DRY_RUN" : "APPLY"}`);
  console.log(`runId: ${RUN_ID}`);
  console.log(`대상 행 수: ${targetRows.length}`);
  console.log(`skip 수: ${skipCount}`);
  console.log(`lessons 생성 예정/완료: ${createTopCount}`);
  console.log(`users/{studentId}/lessons 생성 예정/완료: ${createSubCount}`);
  console.log(`bookedSlots 생성 예정/완료: ${createBookedSlotCount}`);
  console.log(`결과 CSV: ${outputPath}`);

  if (DRY_RUN) {
    console.log("");
    console.log("실제 생성하려면:");
    console.log(`node scripts/restoreMissingNormalLessonsWithLegacyIds.js --apply --runId=${RUN_ID}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});