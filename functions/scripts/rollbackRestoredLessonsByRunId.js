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

function getArg(name, defaultValue = "") {
  const prefix = `${name}=`;
  const found = process.argv.find((arg) => arg.startsWith(prefix));
  if (!found) return defaultValue;
  return found.slice(prefix.length);
}

function hasFlag(name) {
  return process.argv.includes(name);
}

function csvEscape(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

const RUN_ID = getArg("--runId");
const APPLY = hasFlag("--apply");
const DRY_RUN = !APPLY;

if (!RUN_ID) {
  console.error("runId가 필요합니다.");
  console.error("예: node scripts/rollbackRestoredLessonsByRunId.js --runId=restore_missing_lessons_xxx");
  process.exit(1);
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
  console.log("복구 수업 롤백 시작");
  console.log(`mode: ${DRY_RUN ? "DRY_RUN" : "APPLY"}`);
  console.log(`runId: ${RUN_ID}`);

  const topSnap = await db
    .collection("lessons")
    .where("recoveryRunId", "==", RUN_ID)
    .get();

  const targets = [];

  topSnap.forEach((doc) => {
    const data = doc.data();

    targets.push({
      lessonId: doc.id,
      studentId: data.studentId ?? "",
      teacherId: data.teacherId ?? "",
      studentName: data.studentName ?? "",
    });
  });

  console.log(`top-level lessons 기준 롤백 대상: ${targets.length}`);

  if (targets.length === 0) {
    console.log("삭제 대상이 없습니다.");
    return;
  }

  const rows = [];

  for (const target of targets) {
    rows.push({
      runId: RUN_ID,
      mode: DRY_RUN ? "DRY_RUN" : "APPLY",
      action: "DELETE_TOP_LESSON",
      source: "lessons",
      lessonId: target.lessonId,
      studentId: target.studentId,
      teacherId: target.teacherId,
      studentName: target.studentName,
    });

    rows.push({
      runId: RUN_ID,
      mode: DRY_RUN ? "DRY_RUN" : "APPLY",
      action: "DELETE_STUDENT_SUB_LESSON",
      source: "users/{studentId}/lessons",
      lessonId: target.lessonId,
      studentId: target.studentId,
      teacherId: target.teacherId,
      studentName: target.studentName,
    });

    rows.push({
      runId: RUN_ID,
      mode: DRY_RUN ? "DRY_RUN" : "APPLY",
      action: "DELETE_BOOKED_SLOT",
      source: "availableSlots.bookedSlots",
      lessonId: target.lessonId,
      studentId: target.studentId,
      teacherId: target.teacherId,
      studentName: target.studentName,
    });
  }

  if (!DRY_RUN) {
    const ops = [];

    for (const target of targets) {
      const topRef = db.collection("lessons").doc(target.lessonId);

      const subRef = db
        .collection("users")
        .doc(target.studentId)
        .collection("lessons")
        .doc(target.lessonId);

      const slotRef = db.collection("availableSlots").doc(target.teacherId);

      ops.push((batch) => {
        batch.delete(topRef);
      });

      ops.push((batch) => {
        batch.delete(subRef);
      });

      ops.push((batch) => {
        batch.set(
          slotRef,
          {
            bookedSlots: {
              [target.lessonId]: FieldValue.delete(),
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      });
    }

    await commitInChunks(ops);
  }

  const outputPath = path.join(
    __dirname,
    `${DRY_RUN ? "dryrun_rollback" : "applied_rollback"}_${RUN_ID}.csv`
  );

  const headers = [
    "runId",
    "mode",
    "action",
    "source",
    "lessonId",
    "studentId",
    "teacherId",
    "studentName",
  ];

  const csv = [
    headers.join(","),
    ...rows.map((row) =>
      headers.map((header) => csvEscape(row[header])).join(",")
    ),
  ].join("\n");

  fs.writeFileSync(outputPath, csv, "utf8");

  console.log("");
  console.log("롤백 요약");
  console.log(`mode: ${DRY_RUN ? "DRY_RUN" : "APPLY"}`);
  console.log(`top-level lessons 삭제 대상: ${targets.length}`);
  console.log(`student subcollection 삭제 대상: ${targets.length}`);
  console.log(`bookedSlots 삭제 대상: ${targets.length}`);
  console.log(`총 작업 수: ${rows.length}`);
  console.log(`결과 CSV: ${outputPath}`);

  if (DRY_RUN) {
    console.log("");
    console.log("실제 삭제하려면:");
    console.log(`node scripts/rollbackRestoredLessonsByRunId.js --apply --runId=${RUN_ID}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});