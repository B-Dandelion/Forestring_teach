const fs = require("fs");
const path = require("path");

function getArg(name, defaultValue = "") {
  const prefix = `${name}=`;
  const found = process.argv.find((arg) => arg.startsWith(prefix));
  if (!found) return defaultValue;
  return found.slice(prefix.length);
}

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
      if (row.some((v) => String(v).trim() !== "")) rows.push(row);
      row = [];
      field = "";
      continue;
    }

    field += char;
  }

  if (field.length > 0 || row.length > 0) {
    row.push(field);
    if (row.some((v) => String(v).trim() !== "")) rows.push(row);
  }

  const headers = rows[0].map((h) => h.trim());
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

const csvPath = path.resolve(
  getArg("--csv", "scripts/dryrun_restore_strict_legacy_20260518T111200_491Z.csv")
);

if (!fs.existsSync(csvPath)) {
  throw new Error(`CSV 파일 없음: ${csvPath}`);
}

const rows = parseCsv(fs.readFileSync(csvPath, "utf8"));

const legacyIdPattern = /^STU_\d+_\d{4}-\d{2}_[A-Z]{2}\d{4}\d{3}$/;

const actionCounts = rows.reduce((acc, row) => {
  acc[row.action] = (acc[row.action] ?? 0) + 1;
  return acc;
}, {});

const duplicateIds = rows
  .map((row) => row.lessonId)
  .filter((id, index, arr) => arr.indexOf(id) !== index);

const invalidIds = rows.filter((row) => !legacyIdPattern.test(row.lessonId));
const restoreRows = rows.filter((row) => row.action === "RESTORE");
const okRows = rows.filter((row) => row.action === "OK");
const conflictRows = rows.filter((row) => row.action === "CONFLICT_SKIP");

const weirdRestoreRows = restoreRows.filter((row) => {
  return !(
    row.willCreateTop === "true" &&
    row.willCreateSub === "true" &&
    row.willCreateSlot === "true"
  );
});

const weirdOkRows = okRows.filter((row) => {
  return !(
    row.willCreateTop === "false" &&
    row.willCreateSub === "false" &&
    row.willCreateSlot === "false"
  );
});

const restoreByDate = restoreRows.reduce((acc, row) => {
  acc[row.expectedYmd] = (acc[row.expectedYmd] ?? 0) + 1;
  return acc;
}, {});

console.log("DRY RUN 검증 결과");
console.log(`CSV: ${csvPath}`);
console.log(`전체 행 수: ${rows.length}`);
console.log("action counts:", actionCounts);
console.log(`RESTORE 행 수: ${restoreRows.length}`);
console.log(`OK 행 수: ${okRows.length}`);
console.log(`CONFLICT_SKIP 행 수: ${conflictRows.length}`);
console.log(`중복 lessonId 수: ${duplicateIds.length}`);
console.log(`잘못된 lessonId 패턴 수: ${invalidIds.length}`);
console.log(`RESTORE인데 3곳 생성이 아닌 행 수: ${weirdRestoreRows.length}`);
console.log(`OK인데 생성 예정이 있는 행 수: ${weirdOkRows.length}`);

console.log("");
console.log("RESTORE 날짜별 개수:");
console.table(restoreByDate);

if (invalidIds.length > 0) {
  console.log("잘못된 ID 예시:");
  console.table(invalidIds.slice(0, 10).map((row) => ({
    lessonId: row.lessonId,
    studentName: row.studentName,
    expectedYmd: row.expectedYmd,
  })));
}

if (weirdRestoreRows.length > 0) {
  console.log("RESTORE 이상 행 예시:");
  console.table(weirdRestoreRows.slice(0, 10).map((row) => ({
    lessonId: row.lessonId,
    top: row.willCreateTop,
    sub: row.willCreateSub,
    slot: row.willCreateSlot,
  })));
}

const previewPath = path.join(
  path.dirname(csvPath),
  `preview_write_paths_${path.basename(csvPath)}`
);

const previewHeaders = [
  "lessonId",
  "studentName",
  "studentId",
  "teacherId",
  "expectedYmd",
  "expectedStartTime",
  "expectedDuration",
  "expectedCode",
  "topPath",
  "subPath",
  "bookedSlotPath",
  "topAndSubRequiredShape",
  "bookedSlotRequiredShape",
];

const previewRows = restoreRows.map((row) => ({
  lessonId: row.lessonId,
  studentName: row.studentName,
  studentId: row.studentId,
  teacherId: row.teacherId,
  expectedYmd: row.expectedYmd,
  expectedStartTime: row.expectedStartTime,
  expectedDuration: row.expectedDuration,
  expectedCode: row.expectedCode,
  topPath: `lessons/${row.lessonId}`,
  subPath: `users/${row.studentId}/lessons/${row.lessonId}`,
  bookedSlotPath: `availableSlots/${row.teacherId}.bookedSlots.${row.lessonId}`,
  topAndSubRequiredShape:
    "code:string,date:Timestamp,duration:number,isRescheduled:false,status:confirmed,studentId:string,teacherId:string,createdAt:serverTimestamp,updatedAt:serverTimestamp",
  bookedSlotRequiredShape:
    "date:Timestamp,duration:number,isRescheduled:false,status:confirmed,studentId:string",
}));

const previewCsv = [
  previewHeaders.join(","),
  ...previewRows.map((row) =>
    previewHeaders.map((header) => csvEscape(row[header])).join(",")
  ),
].join("\n");

fs.writeFileSync(previewPath, previewCsv, "utf8");

console.log("");
console.log(`생성 경로/구조 프리뷰 CSV 저장: ${previewPath}`);

if (
  duplicateIds.length === 0 &&
  invalidIds.length === 0 &&
  conflictRows.length === 0 &&
  weirdRestoreRows.length === 0 &&
  weirdOkRows.length === 0
) {
  console.log("");
  console.log("기계적 검증은 통과했습니다.");
} else {
  console.log("");
  console.log("검증 실패 항목이 있습니다. apply 하지 마세요.");
}