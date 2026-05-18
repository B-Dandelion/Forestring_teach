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

const SCRIPT_NAME = "restoreMissingNormalLessonsFromAudit";

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

const APPLY = hasFlag("--apply") || process.env.DRY_RUN === "false";
const DRY_RUN = !APPLY;

const CSV_PATH = path.resolve(getArg("--csv", DEFAULT_CSV_PATH));

const RUN_ID =
  getArg("--runId") ||
  `restore_missing_lessons_${new Date()
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
      if (char === "\r" && next === "\n") {
        i += 1;
      }

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

  if (rawHour == null || rawMinute == null) {
    return text;
  }

  return `${rawHour.padStart(2, "0")}:${rawMinute.padStart(2, "0")}`;
}

function kstDateTimeToUtcDate(ymd, hhmm) {
  return new Date(`${ymd}T${hhmm}:00+09:00`);
}

function formatYmdCompact(ymd) {
  return String(ymd).replaceAll("-", "");
}

function formatTimeCompact(hhmm) {
  return String(hhmm).replace(":", "");
}

function makeLessonId(row) {
  const studentId = normalizeText(row.studentId);
  const ymd = normalizeText(row.expectedYmd);
  const startTime = normalizeTime(row.expectedStartTime);

  return `${studentId}_${formatYmdCompact(ymd)}_${formatTimeCompact(startTime)}_RESTORE`;
}

function isNormalLesson(data) {
  const status = normalizeText(data.status);
  const code = normalizeText(data.code);

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

function getLessonDate(data) {
  return (
    getDateValue(data.date) ||
    getDateValue(data.startTime) ||
    getDateValue(data.startDate) ||
    getDateValue(data.lessonDate) ||
    null
  );
}

function getKstTimeKey(date) {
  if (!date) return "";

  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Seoul",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function getKstWeekdayKey(date) {
  if (!date) return "";

  return new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Seoul",
    weekday: "short",
  }).format(date);
}

function removeUndefinedDeep(value) {
  if (Array.isArray(value)) {
    return value.map(removeUndefinedDeep);
  }

  if (value && typeof value === "object" && !(value instanceof Date)) {
    if (typeof value.toDate === "function") {
      return value;
    }

    const cleaned = {};

    for (const [key, innerValue] of Object.entries(value)) {
      if (innerValue === undefined) continue;
      cleaned[key] = removeUndefinedDeep(innerValue);
    }

    return cleaned;
  }

  return value;
}

async function loadStudentsById(studentIds) {
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

async function loadTemplateLessonsByStudent(studentIds) {
  const result = new Map();

  for (const studentId of studentIds) {
    const snap = await db
      .collection("lessons")
      .where("studentId", "==", studentId)
      .get();

    const lessons = [];

    snap.forEach((doc) => {
      const data = doc.data();

      lessons.push({
        lessonId: doc.id,
        ...data,
      });
    });

    result.set(studentId, lessons);
  }

  return result;
}

function findTemplateLesson(row, templates) {
  const expectedTeacherId = normalizeText(row.teacherId);
  const expectedDuration = normalizeNumber(row.expectedDuration, 0);
  const expectedStartTime = normalizeTime(row.expectedStartTime);

  const normalTemplates = templates.filter((lesson) => {
    if (!isNormalLesson(lesson)) return false;
    if (normalizeText(lesson.teacherId) !== expectedTeacherId) return false;

    const lessonDuration = normalizeNumber(lesson.duration, expectedDuration);
    const sameDuration = lessonDuration === expectedDuration;

    return sameDuration;
  });

  if (normalTemplates.length === 0) {
    return null;
  }

  const sameTimeTemplates = normalTemplates.filter((lesson) => {
    const date = getLessonDate(lesson);
    return getKstTimeKey(date) === expectedStartTime;
  });

  if (sameTimeTemplates.length > 0) {
    return sameTimeTemplates[0];
  }

  return normalTemplates[0];
}

function makeLessonData(row, student, template, lessonId) {
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

  delete base.lessonId;
  delete base.id;
  delete base.createdAt;
  delete base.updatedAt;
  delete base.canceledAt;
  delete base.cancelledAt;
  delete base.cancelReason;
  delete base.rescheduledAt;
  delete base.rescheduledBy;
  delete base.RescheduledBy;
  delete base.originalDate;
  delete base.originalLessonId;

  const status =
    normalizeText(template?.status) === "confirm" ||
    normalizeText(template?.status) === "confirmed"
      ? normalizeText(template.status)
      : "confirmed";

  return removeUndefinedDeep({
    ...base,

    lessonId,
    studentId,
    studentName,
    teacherId,

    date,
    duration,
    code,
    status,
    isRescheduled: false,

    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),

    recoveryRunId: RUN_ID,
    recoveryScript: SCRIPT_NAME,
    recoveryReason: "restore missing regular lessons from schedule audit",
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
    slotDocExists: slotSnap.exists,
    slotExists,
  };
}

async function main() {
  console.log("누락 정규수업 복구 스크립트 시작");
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
    console.log("복구 대상이 없습니다.");
    return;
  }

  const studentIds = [
    ...new Set(targetRows.map((row) => normalizeText(row.studentId)).filter(Boolean)),
  ];

  const studentsById = await loadStudentsById(studentIds);
  const templatesByStudent = await loadTemplateLessonsByStudent(studentIds);

  const planRows = [];
  const batch = db.batch();

  let createTopCount = 0;
  let createSubCount = 0;
  let createBookedSlotCount = 0;
  let skippedCount = 0;

  for (const row of targetRows) {
    const studentId = normalizeText(row.studentId);
    const student = studentsById.get(studentId);
    const templates = templatesByStudent.get(studentId) ?? [];

    const lessonId = makeLessonId(row);
    const existing = await checkExistingTargets(row, lessonId);

    const template = findTemplateLesson(row, templates);

    const shouldCreateTop = !existing.topExists;
    const shouldCreateSub = !existing.subExists;
    const shouldCreateBookedSlot = !existing.slotExists;

    const skipReasonParts = [];

    if (!student) {
      skipReasonParts.push("STUDENT_DOC_NOT_FOUND");
    }

    if (!template) {
      skipReasonParts.push("TEMPLATE_LESSON_NOT_FOUND");
    }

    const canCreate = student && template;

    if (!canCreate) {
      skippedCount += 1;
    }

    const lessonData = canCreate
      ? makeLessonData(row, student, template, lessonId)
      : null;

    const bookedSlotData = canCreate ? makeBookedSlotData(row) : null;

    if (canCreate && !DRY_RUN) {
      if (shouldCreateTop) {
        batch.set(existing.topRef, lessonData);
      }

      if (shouldCreateSub) {
        batch.set(existing.subRef, lessonData);
      }

      if (shouldCreateBookedSlot) {
        batch.set(
          existing.slotRef,
          {
            bookedSlots: {
              [lessonId]: bookedSlotData,
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
    }

    if (canCreate && shouldCreateTop) createTopCount += 1;
    if (canCreate && shouldCreateSub) createSubCount += 1;
    if (canCreate && shouldCreateBookedSlot) createBookedSlotCount += 1;

    planRows.push({
      runId: RUN_ID,
      mode: DRY_RUN ? "DRY_RUN" : "APPLY",
      action: canCreate ? "RESTORE" : "SKIP",
      skipReason: skipReasonParts.join(" / "),

      lessonId,
      studentName: normalizeText(row.studentName),
      studentId,
      teacherId: normalizeText(row.teacherId),
      expectedDateKst: normalizeText(row.expectedDateKst),
      expectedYmd: normalizeText(row.expectedYmd),
      expectedStartTime: normalizeText(row.expectedStartTime),
      expectedDuration: normalizeText(row.expectedDuration),
      expectedCode: normalizeText(row.expectedCode),

      templateLessonId: template?.lessonId ?? "",

      topExistsBefore: existing.topExists,
      subExistsBefore: existing.subExists,
      bookedSlotExistsBefore: existing.slotExists,

      willCreateTop: canCreate && shouldCreateTop,
      willCreateSub: canCreate && shouldCreateSub,
      willCreateBookedSlot: canCreate && shouldCreateBookedSlot,
    });
  }

  if (!DRY_RUN) {
    await batch.commit();
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
    "studentName",
    "studentId",
    "teacherId",
    "expectedDateKst",
    "expectedYmd",
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
    ...planRows.map((row) => headers.map((header) => csvEscape(row[header])).join(",")),
  ].join("\n");

  fs.writeFileSync(outputPath, outCsv, "utf8");

  console.log("");
  console.log("복구 계획 요약");
  console.log(`mode: ${DRY_RUN ? "DRY_RUN" : "APPLY"}`);
  console.log(`runId: ${RUN_ID}`);
  console.log(`대상 행 수: ${targetRows.length}`);
  console.log(`skip 수: ${skippedCount}`);
  console.log(`lessons 생성 예정/완료: ${createTopCount}`);
  console.log(`users/{studentId}/lessons 생성 예정/완료: ${createSubCount}`);
  console.log(`bookedSlots 생성 예정/완료: ${createBookedSlotCount}`);
  console.log(`결과 CSV: ${outputPath}`);

  if (DRY_RUN) {
    console.log("");
    console.log("실제 생성하려면 아래처럼 실행:");
    console.log(`node scripts/restoreMissingNormalLessonsFromAudit.js --apply --runId=${RUN_ID}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});