const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const REGION = "asia-northeast3";

// v2에서는 functions.config() 대신 Secret 사용
const ADMIN_TASK_TOKEN = defineSecret("ADMIN_TASK_TOKEN");

function parseBool(v, defaultValue = false) {
  if (v === undefined || v === null) return defaultValue;
  const s = String(v).toLowerCase();
  return s === "1" || s === "true" || s === "yes" || s === "y";
}

function requireAdminToken(req, res) {
  const cfgToken = ADMIN_TASK_TOKEN.value(); // Secret 값
  const token = String(req.query.token || "");
  if (!cfgToken || !token || token !== cfgToken) {
    res.status(403).send("Forbidden (bad token)");
    return false;
  }
  return true;
}

exports.repairBookedSlotsForRun = onRequest(
  { region: REGION, invoker: "public", timeoutSeconds: 540, secrets: [ADMIN_TASK_TOKEN] },
  async (req, res) => {
    try {
      if (!requireAdminToken(req, res)) return;

      const runId = String(req.query.runId || "").trim();
      const commit = parseBool(req.query.commit, false);

      if (!runId) {
        res.status(400).json({ ok: false, error: "runId is required" });
        return;
      }

      const startedAt = new Date();
      console.log(`[repairBookedSlotsForRun] start runId=${runId} commit=${commit}`);

      // runId로 생성된 lessons를 전부 가져옴 (페이지네이션)
      const pageSize = 400; // 읽기는 넉넉하게
      let lastDoc = null;

      let totalLessons = 0;
      let plannedWrites = 0;

      let repairedCount = 0;
      let deletedSubcolCount = 0;
      let missingTeacherId = 0;

      // 배치(500 op 제한)
      let batch = db.batch();
      let opCount = 0;

      // teacher별 집계 로그
      const teacherAgg = {}; // teacherId -> { repaired, deleted }

      async function flushBatch() {
        if (opCount === 0) return;
        if (!commit) {
          // dry-run이면 커밋 안 함
          opCount = 0;
          batch = db.batch();
          return;
        }
        await batch.commit();
        batch = db.batch();
        opCount = 0;
      }

      while (true) {
        let q = db
          .collection("lessons")
          .where("autoFillRunId", "==", runId)
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(pageSize);

        if (lastDoc) q = q.startAfter(lastDoc);

        const snap = await q.get();
        if (snap.empty) break;

        for (const doc of snap.docs) {
          totalLessons++;
          lastDoc = doc;

          const lessonId = doc.id;
          const data = doc.data() || {};

          const teacherId = data.teacherId;
          const studentId = data.studentId;
          const status = data.status || "confirmed";
          const isRescheduled = !!data.isRescheduled;
          const duration = Number(data.duration) || 0;
          const date = data.date; // Timestamp 그대로

          if (!teacherId) {
            missingTeacherId++;
            console.warn(`[repair] missing teacherId lessonId=${lessonId}`);
            continue;
          }

          // 1) 구버전 Map 필드 채우기: availableSlots/{teacherId}.bookedSlots.{lessonId}
          // update는 doc 있어야 함(보통 있음). 혹시 없을 수 있으면 set(merge) 먼저 1회 해도 됨.
          const teacherDocRef = db.collection("availableSlots").doc(teacherId);
          const updateData = {};
          updateData[`bookedSlots.${lessonId}`] = {
            date,
            duration,
            isRescheduled,
            status,
            studentId,
          };

          batch.update(teacherDocRef, updateData);
          opCount++;
          plannedWrites++;

          repairedCount++;
          teacherAgg[teacherId] = teacherAgg[teacherId] || { repaired: 0, deleted: 0 };
          teacherAgg[teacherId].repaired++;

          // 2) 신버전 서브컬렉션 삭제: availableSlots/{teacherId}/bookedSlots/{lessonId}
          const subRef = teacherDocRef.collection("bookedSlots").doc(lessonId);
          batch.delete(subRef);
          opCount++;
          plannedWrites++;

          deletedSubcolCount++;
          teacherAgg[teacherId].deleted++;

          // 배치 한도 처리
          if (opCount >= 450) {
            await flushBatch();
          }
        }

        if (snap.size < pageSize) break;
      }

      await flushBatch();

      // 요약 로그 저장
      const endedAt = new Date();
      const summary = {
        runId,
        commit,
        totalLessons,
        repairedCount,
        deletedSubcolCount,
        missingTeacherId,
        startedAt: admin.firestore.Timestamp.fromDate(startedAt),
        endedAt: admin.firestore.Timestamp.fromDate(endedAt),
        teacherAgg,
      };

      if (commit) {
        await db
          .collection("adminLogs")
          .doc("repairBookedSlotsForRun")
          .collection("runs")
          .doc(runId)
          .set(
            { ...summary, createdAt: admin.firestore.FieldValue.serverTimestamp() },
            { merge: true }
          );
      }

      console.log(`[repairBookedSlotsForRun] end runId=${runId} summary=${JSON.stringify(summary)}`);
      res.json({ ok: true, ...summary });
    } catch (e) {
      console.error("[repairBookedSlotsForRun] ERROR", e);
      res.status(500).json({ ok: false, error: String(e?.message || e) });
    }
  }
);