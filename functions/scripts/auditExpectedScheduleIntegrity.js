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

/**
 * 검사 범위.
 * END_YMD는 미포함.
 * 예: 2026-07-01이면 2026-06-30 23:59까지 검사.
 */
const START_YMD = "2026-05-31";
const END_YMD = "2026-07-01";

/**
 * 특정 선생님만 보고 싶으면 "TCH_250313460" 입력.
 * 전체 검사하려면 빈 문자열.
 */
const TARGET_TEACHER_ID = "";

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
  const text = String(value ?? "").trim();
  if (!text) return "";

  const [rawHour, rawMinute] = text.split(":");
  if (rawHour == null || rawMinute == null) return text;

  return `${rawHour.padStart(2, "0")}:${rawMinute.padStart(2, "0")}`;
}

function parseYmd(ymd) {
  const [year, month, day] = ymd.split("-").map(Number);
  return { year, month, day };
}

function addDaysYmd(ymd, days) {
  const { year, month, day } = parseYmd(ymd);
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return date.toISOString().slice(0, 10);
}

function compareYmd(a, b) {
  return a.localeCompare(b);
}

function kstDateTimeToUtcDate(ymd, hhmm) {
  return new Date(`${ymd}T${hhmm}:00+09:00`);
}

function getKstWeekdayIndex(ymd) {
  const date = kstDateTimeToUtcDate(ymd, "12:00");
  return date.getUTCDay();
}

function getWeekStartSundayYmd(ymd) {
  const weekday = getKstWeekdayIndex(ymd);
  return addDaysYmd(ymd, -weekday);
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

function getBookedSlotDate(slot) {
  return (
    getDateValue(slot.date) ||
    getDateValue(slot.startTime) ||
    getDateValue(slot.startDate) ||
    getDateValue(slot.lessonDate) ||
    null
  );
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

function isSameMinute(a, b) {
  if (!a || !b) return false;
  return Math.abs(a.getTime() - b.getTime()) < 60 * 1000;
}

function isSameDuration(a, b) {
  const n1 = Number(a);
  const n2 = Number(b);

  if (Number.isNaN(n1) || Number.isNaN(n2)) return true;
  return n1 === n2;
}

function isNormalLesson(data) {
  const status = normalizeText(data.status);
  const code = normalizeText(data.code);

  const isNormalStatus = status === "confirm" || status === "confirmed";
  const isMakeup = code === "-1";
  const isRescheduled = data.isRescheduled === true;

  return isNormalStatus && !isMakeup && !isRescheduled;
}

function isNormalBookedSlot(slot) {
  const status = normalizeText(slot.status);

  const isNormalStatus = status === "confirm" || status === "confirmed";
  const isRescheduled = slot.isRescheduled === true;

  return isNormalStatus && !isRescheduled;
}

function getStudentIdFromLesson(data, fallbackStudentId = "") {
  return (
    data.studentId ||
    data.Student_id ||
    data.studentID ||
    data.userId ||
    fallbackStudentId ||
    ""
  );
}

function getTeacherIdFromLesson(data, fallbackTeacherId = "") {
  return (
    data.teacherId ||
    data.Teacher_id ||
    data.teacherID ||
    fallbackTeacherId ||
    ""
  );
}

function getStudentIdFromBookedSlot(slot) {
  return (
    slot.studentId ||
    slot.Student_id ||
    slot.studentID ||
    slot.userId ||
    ""
  );
}

/**
 * top-level lessons 매칭 기준.
 * code는 비교하지 않는다.
 * code는 정규/보강 판정에서만 사용한다.
 */
function matchesExpectedLesson(data, expected) {
  const lessonDate = getLessonDate(data);

  const sameStudent = getStudentIdFromLesson(data) === expected.studentId;
  const sameTeacher = getTeacherIdFromLesson(data) === expected.teacherId;
  const sameDate = isSameMinute(lessonDate, expected.dateObj);
  const sameDuration = isSameDuration(data.duration, expected.duration);

  return sameStudent && sameTeacher && sameDate && sameDuration;
}

/**
 * users/{studentId}/lessons 매칭 기준.
 * 하위 문서에 studentId가 없을 수 있으므로 parentStudentId를 fallback으로 쓴다.
 */
function matchesExpectedSubLesson(data, expected, parentStudentId) {
  const lessonDate = getLessonDate(data);

  const sameStudent = getStudentIdFromLesson(data, parentStudentId) === expected.studentId;
  const sameTeacher = getTeacherIdFromLesson(data, expected.teacherId) === expected.teacherId;
  const sameDate = isSameMinute(lessonDate, expected.dateObj);
  const sameDuration = isSameDuration(data.duration, expected.duration);

  return sameStudent && sameTeacher && sameDate && sameDuration;
}

/**
 * availableSlots/{teacherId}.bookedSlots 내부 slot 매칭 기준.
 * bookedSlots에는 code가 없으므로 code 비교 금지.
 */
function matchesExpectedBookedSlot(slot, expected) {
  const slotDate = getBookedSlotDate(slot);

  const sameStudent = getStudentIdFromBookedSlot(slot) === expected.studentId;
  const sameDate = isSameMinute(slotDate, expected.dateObj);
  const sameDuration = isSameDuration(slot.duration, expected.duration);

  return sameStudent && sameDate && sameDuration;
}

function getStoreState(anyMatches, normalMatches) {
  if (normalMatches.length > 0) return "OK";
  if (anyMatches.length > 0) return "EXISTS_BUT_NOT_NORMAL";
  return "MISSING";
}

function makeIssue(topState, subState, bookedState) {
  if (topState === "OK" && subState === "OK" && bookedState === "OK") {
    return "OK";
  }

  if (
    topState === "MISSING" &&
    subState === "MISSING" &&
    bookedState === "MISSING"
  ) {
    return "ALL_3_MISSING";
  }

  const parts = [];

  if (topState !== "OK") parts.push(`lessons:${topState}`);
  if (subState !== "OK") parts.push(`studentSub:${subState}`);
  if (bookedState !== "OK") parts.push(`bookedSlots:${bookedState}`);

  return parts.join(" | ");
}

function csvEscape(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

function isDummyStudent(docId, data, teacherId) {
  const name = String(data.name ?? "");

  return (
    docId.includes("{") ||
    teacherId.includes("{") ||
    name.includes("KimS") ||
    name.includes("{")
  );
}

function makeExpectedLessonsForStudent(student) {
  const expected = [];

  for (const schedule of student.weeklySchedule) {
    const dayRaw = normalizeText(schedule.day).toUpperCase();
    const targetDay = DAY_MAP[dayRaw];

    if (targetDay == null) {
      console.warn(
        `요일 파싱 실패: ${student.name} ${student.id}, day=${schedule.day}`
      );
      continue;
    }

    const startTime = normalizeTime(schedule.startTime);
    const duration = Number(schedule.duration ?? 0);
    const code = normalizeText(schedule.code);

    if (!startTime) {
      console.warn(
        `startTime 없음: ${student.name} ${student.id}, schedule=${JSON.stringify(schedule)}`
      );
      continue;
    }

    let ymd = START_YMD;

    while (compareYmd(ymd, END_YMD) < 0) {
      const currentDay = getKstWeekdayIndex(ymd);

      if (currentDay === targetDay) {
        const dateObj = kstDateTimeToUtcDate(ymd, startTime);

        expected.push({
          expectedKey: `${student.id}_${ymd}_${startTime}_${duration}`,
          studentId: student.id,
          studentName: student.name,
          teacherId: student.teacherId,
          expectedYmd: ymd,
          expectedWeekStartYmd: getWeekStartSundayYmd(ymd),
          expectedDay: schedule.day,
          expectedStartTime: startTime,
          expectedDuration: duration,
          expectedCode: code,
          dateObj,
        });
      }

      ymd = addDaysYmd(ymd, 1);
    }
  }

  return expected;
}

function uniqueBySlotKey(items) {
  const map = new Map();

  for (const item of items) {
    if (!item.slotKey) continue;
    if (!map.has(item.slotKey)) {
      map.set(item.slotKey, item);
    }
  }

  return [...map.values()];
}

function findBookedMatches(bookedSlots, expected, topAnyMatches, subAnyMatches) {
  const matches = [];

  const candidateLessonIds = [
    ...new Set(
      [...topAnyMatches, ...subAnyMatches]
        .map((item) => item.lessonId)
        .filter(Boolean)
    ),
  ];

  /**
   * 1순위:
   * bookedSlots map의 key는 lessonId 구조이므로,
   * top/sub lessons에서 찾은 lessonId로 직접 확인한다.
   */
  for (const lessonId of candidateLessonIds) {
    const slot = bookedSlots[lessonId];

    if (slot) {
      matches.push({
        slotKey: lessonId,
        matchType: "lessonId",
        ...slot,
      });
    }
  }

  /**
   * 2순위:
   * 혹시 key가 lessonId와 다르거나 top/sub가 누락된 경우를 대비해
   * studentId + date + duration으로도 찾는다.
   */
  for (const [slotKey, slot] of Object.entries(bookedSlots)) {
    if (matchesExpectedBookedSlot(slot, expected)) {
      matches.push({
        slotKey,
        matchType: "studentDateDuration",
        ...slot,
      });
    }
  }

  return uniqueBySlotKey(matches);
}

function summarizeByStudent(issueRows) {
  const map = new Map();

  for (const row of issueRows) {
    const key = row.studentId;

    if (!map.has(key)) {
      map.set(key, {
        studentName: row.studentName,
        studentId: row.studentId,
        teacherId: row.teacherId,
        issueCount: 0,
        all3MissingCount: 0,
        partialIssueCount: 0,
        firstIssueDate: row.expectedDateKst,
      });
    }

    const item = map.get(key);
    item.issueCount += 1;

    if (row.issue === "ALL_3_MISSING") {
      item.all3MissingCount += 1;
    } else {
      item.partialIssueCount += 1;
    }
  }

  return [...map.values()].sort((a, b) => b.issueCount - a.issueCount);
}

function summarizeByWeek(issueRows) {
  const map = new Map();

  for (const row of issueRows) {
    const key = row.expectedWeekStartYmd;

    if (!map.has(key)) {
      map.set(key, {
        weekStartYmd: row.expectedWeekStartYmd,
        issueCount: 0,
        all3MissingCount: 0,
        partialIssueCount: 0,
      });
    }

    const item = map.get(key);
    item.issueCount += 1;

    if (row.issue === "ALL_3_MISSING") {
      item.all3MissingCount += 1;
    } else {
      item.partialIssueCount += 1;
    }
  }

  return [...map.values()].sort((a, b) =>
    a.weekStartYmd.localeCompare(b.weekStartYmd)
  );
}

async function main() {
  console.log("읽기 전용 점검 시작");
  console.log(`검사 범위: ${START_YMD} 이상 ~ ${END_YMD} 미만`);

  if (TARGET_TEACHER_ID) {
    console.log(`대상 선생님: ${TARGET_TEACHER_ID}`);
  }

  console.log("");
  console.log("학생 weeklySchedule 조회 중...");

  const usersSnap = await db.collection("users").get();

  const students = [];

  usersSnap.forEach((doc) => {
    const data = doc.data();

    const role = normalizeText(data.role);
    const weeklySchedule = data.weeklySchedule;
    const teacherId = data.teacherId || data.teacherID || "";

    const isStudent = role === "student";
    const hasSchedule = Array.isArray(weeklySchedule) && weeklySchedule.length > 0;

    const isArchived =
      data.isArchived === true ||
      data.archived === true ||
      data.status === "archived" ||
      data.deletedAt != null;

    if (!isStudent || !hasSchedule || isArchived) return;
    if (isDummyStudent(doc.id, data, teacherId)) return;
    if (TARGET_TEACHER_ID && teacherId !== TARGET_TEACHER_ID) return;

    students.push({
      id: doc.id,
      name: data.name ?? "",
      teacherId,
      weeklySchedule,
    });
  });

  console.log(`검사 대상 학생 수: ${students.length}`);

  const expectedLessons = students.flatMap(makeExpectedLessonsForStudent);

  expectedLessons.sort((a, b) => a.dateObj.getTime() - b.dateObj.getTime());

  console.log(`weeklySchedule 기준 예상 정규수업 수: ${expectedLessons.length}`);

  const START = admin.firestore.Timestamp.fromDate(
    kstDateTimeToUtcDate(START_YMD, "00:00")
  );

  const END = admin.firestore.Timestamp.fromDate(
    kstDateTimeToUtcDate(END_YMD, "00:00")
  );

  console.log("");
  console.log("top-level lessons 조회 중...");

  const lessonsSnap = await db
    .collection("lessons")
    .where("date", ">=", START)
    .where("date", "<", END)
    .get();

  const topLessons = [];

  lessonsSnap.forEach((doc) => {
    const data = doc.data();

    if (TARGET_TEACHER_ID && getTeacherIdFromLesson(data) !== TARGET_TEACHER_ID) {
      return;
    }

    topLessons.push({
      lessonId: doc.id,
      ...data,
    });
  });

  console.log(`조회된 top-level lessons 수: ${topLessons.length}`);

  console.log("");
  console.log("학생 subcollection lessons 조회 중...");

  const subLessonsByStudent = new Map();

  for (const student of students) {
    const subSnap = await db
      .collection("users")
      .doc(student.id)
      .collection("lessons")
      .where("date", ">=", START)
      .where("date", "<", END)
      .get();

    const list = [];

    subSnap.forEach((doc) => {
      list.push({
        lessonId: doc.id,
        parentStudentId: student.id,
        ...doc.data(),
      });
    });

    subLessonsByStudent.set(student.id, list);
  }

  const totalSubLessons = [...subLessonsByStudent.values()].reduce(
    (sum, list) => sum + list.length,
    0
  );

  console.log(`조회된 student subcollection lessons 수: ${totalSubLessons}`);

  console.log("");
  console.log("availableSlots bookedSlots 조회 중...");

  const teacherIds = [
    ...new Set(
      students
        .map((student) => student.teacherId)
        .filter((teacherId) => typeof teacherId === "string" && teacherId.length > 0)
    ),
  ];

  const bookedSlotsByTeacher = new Map();

  for (const teacherId of teacherIds) {
    const slotDoc = await db.collection("availableSlots").doc(teacherId).get();

    if (!slotDoc.exists) {
      bookedSlotsByTeacher.set(teacherId, {});
      continue;
    }

    const data = slotDoc.data();
    bookedSlotsByTeacher.set(teacherId, data.bookedSlots ?? {});
  }

  console.log(`조회된 availableSlots 선생님 수: ${teacherIds.length}`);

  console.log("");
  console.log("예상 수업별 3개 저장소 대조 중...");

  const rows = [];

  for (const expected of expectedLessons) {
    const topAnyMatches = topLessons.filter((lesson) =>
      matchesExpectedLesson(lesson, expected)
    );

    const topNormalMatches = topAnyMatches.filter(isNormalLesson);

    const subLessons = subLessonsByStudent.get(expected.studentId) ?? [];

    const subAnyMatches = subLessons.filter((lesson) =>
      matchesExpectedSubLesson(lesson, expected, expected.studentId)
    );

    const subNormalMatches = subAnyMatches.filter(isNormalLesson);

    const bookedSlots = bookedSlotsByTeacher.get(expected.teacherId) ?? {};

    const bookedAnyMatches = findBookedMatches(
      bookedSlots,
      expected,
      topAnyMatches,
      subAnyMatches
    );

    const bookedNormalMatches = bookedAnyMatches.filter(isNormalBookedSlot);

    const topState = getStoreState(topAnyMatches, topNormalMatches);
    const subState = getStoreState(subAnyMatches, subNormalMatches);
    const bookedState = getStoreState(bookedAnyMatches, bookedNormalMatches);

    const issue = makeIssue(topState, subState, bookedState);

    rows.push({
      issue,

      studentName: expected.studentName,
      studentId: expected.studentId,
      teacherId: expected.teacherId,

      expectedDateKst: formatKst(expected.dateObj),
      expectedYmd: expected.expectedYmd,
      expectedWeekStartYmd: expected.expectedWeekStartYmd,
      expectedDay: expected.expectedDay,
      expectedStartTime: expected.expectedStartTime,
      expectedDuration: expected.expectedDuration,
      expectedCode: expected.expectedCode,

      topState,
      topAnyCount: topAnyMatches.length,
      topNormalCount: topNormalMatches.length,
      topLessonIds: topAnyMatches.map((item) => item.lessonId).join(" / "),
      topStatuses: topAnyMatches.map((item) => item.status).join(" / "),

      subState,
      subAnyCount: subAnyMatches.length,
      subNormalCount: subNormalMatches.length,
      subLessonIds: subAnyMatches.map((item) => item.lessonId).join(" / "),
      subStatuses: subAnyMatches.map((item) => item.status).join(" / "),

      bookedState,
      bookedAnyCount: bookedAnyMatches.length,
      bookedNormalCount: bookedNormalMatches.length,
      bookedSlotKeys: bookedAnyMatches.map((item) => item.slotKey).join(" / "),
      bookedStatuses: bookedAnyMatches.map((item) => item.status).join(" / "),
      bookedMatchTypes: bookedAnyMatches.map((item) => item.matchType).join(" / "),
    });
  }

  const issueRows = rows.filter((row) => row.issue !== "OK");
  const all3MissingRows = issueRows.filter((row) => row.issue === "ALL_3_MISSING");
  const partialRows = issueRows.filter((row) => row.issue !== "ALL_3_MISSING");

  console.log("");
  console.log("점검 결과");
  console.log(`전체 예상 수업 수: ${rows.length}`);
  console.log(`정상 수업 수: ${rows.length - issueRows.length}`);
  console.log(`문제 수업 수: ${issueRows.length}`);
  console.log(`3곳 모두 없음: ${all3MissingRows.length}`);
  console.log(`일부 저장소만 누락/비정상: ${partialRows.length}`);

  if (issueRows.length > 0) {
    console.log("");
    console.log("문제 수업 미리보기 최대 100개");
    console.table(
      issueRows.slice(0, 100).map((row) => ({
        issue: row.issue,
        date: row.expectedDateKst,
        week: row.expectedWeekStartYmd,
        name: row.studentName,
        studentId: row.studentId,
        teacherId: row.teacherId,
        top: row.topState,
        sub: row.subState,
        booked: row.bookedState,
      }))
    );
  }

  const summaryRows = summarizeByStudent(issueRows);
  const weekSummaryRows = summarizeByWeek(issueRows);

  if (summaryRows.length > 0) {
    console.log("");
    console.log("학생별 문제 요약");
    console.table(summaryRows);
  }

  if (weekSummaryRows.length > 0) {
    console.log("");
    console.log("주차별 문제 요약");
    console.table(weekSummaryRows);
  }

  const detailPath = path.join(
    __dirname,
    "audit_expected_schedule_integrity.csv"
  );

  const issuePath = path.join(
    __dirname,
    "audit_expected_schedule_integrity_issues_only.csv"
  );

  const summaryPath = path.join(
    __dirname,
    "audit_expected_schedule_integrity_summary.csv"
  );

  const weekSummaryPath = path.join(
    __dirname,
    "audit_expected_schedule_integrity_week_summary.csv"
  );

  const detailHeaders = [
    "issue",

    "studentName",
    "studentId",
    "teacherId",

    "expectedDateKst",
    "expectedYmd",
    "expectedWeekStartYmd",
    "expectedDay",
    "expectedStartTime",
    "expectedDuration",
    "expectedCode",

    "topState",
    "topAnyCount",
    "topNormalCount",
    "topLessonIds",
    "topStatuses",

    "subState",
    "subAnyCount",
    "subNormalCount",
    "subLessonIds",
    "subStatuses",

    "bookedState",
    "bookedAnyCount",
    "bookedNormalCount",
    "bookedSlotKeys",
    "bookedStatuses",
    "bookedMatchTypes",
  ];

  const detailCsv = [
    detailHeaders.join(","),
    ...rows.map((row) =>
      detailHeaders.map((header) => csvEscape(row[header])).join(",")
    ),
  ].join("\n");

  const issueCsv = [
    detailHeaders.join(","),
    ...issueRows.map((row) =>
      detailHeaders.map((header) => csvEscape(row[header])).join(",")
    ),
  ].join("\n");

  fs.writeFileSync(detailPath, detailCsv, "utf8");
  fs.writeFileSync(issuePath, issueCsv, "utf8");

  const summaryHeaders = [
    "studentName",
    "studentId",
    "teacherId",
    "issueCount",
    "all3MissingCount",
    "partialIssueCount",
    "firstIssueDate",
  ];

  const summaryCsv = [
    summaryHeaders.join(","),
    ...summaryRows.map((row) =>
      summaryHeaders.map((header) => csvEscape(row[header])).join(",")
    ),
  ].join("\n");

  fs.writeFileSync(summaryPath, summaryCsv, "utf8");

  const weekSummaryHeaders = [
    "weekStartYmd",
    "issueCount",
    "all3MissingCount",
    "partialIssueCount",
  ];

  const weekSummaryCsv = [
    weekSummaryHeaders.join(","),
    ...weekSummaryRows.map((row) =>
      weekSummaryHeaders.map((header) => csvEscape(row[header])).join(",")
    ),
  ].join("\n");

  fs.writeFileSync(weekSummaryPath, weekSummaryCsv, "utf8");

  console.log("");
  console.log(`상세 CSV 저장 완료: ${detailPath}`);
  console.log(`문제만 CSV 저장 완료: ${issuePath}`);
  console.log(`학생 요약 CSV 저장 완료: ${summaryPath}`);
  console.log(`주차 요약 CSV 저장 완료: ${weekSummaryPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});