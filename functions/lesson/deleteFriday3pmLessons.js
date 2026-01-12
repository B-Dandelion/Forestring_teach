// functions/lesson/deleteFriday3pmLessons.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// bookedSlots (스크린샷 기준)
const BOOKED_DATE_FIELD = "date";
const BOOKED_STUDENT_FIELD = "studentId";

const LESSONS_COL = "lessons";
const STUDENTS_COL = "students";
const STUDENT_LESSONS_SUBCOL = "lessons";
const TEACHERS_COL = "teachers";
const TEACHER_BOOKED_SUBCOL = "bookedSlots";

const LESSON_STUDENT_FIELD = "studentId";
const LESSON_TEACHER_FIELD = "teacherId";
const LESSON_START_FIELDS = ["startTime", "date"]; // startTime 없으면 date fallback

function toKSTParts(d) {
  const kstMs = d.getTime() + 9 * 60 * 60 * 1000;
  const kst = new Date(kstMs);
  return {
    dow: kst.getUTCDay(), // 0=Sun ... 5=Fri
    hour: kst.getUTCHours(),
    minute: kst.getUTCMinutes(),
    iso: kst.toISOString(),
  };
}

function parseBool(v, def) {
  if (v === undefined || v === null) return def;
  const s = String(v).toLowerCase().trim();
  if (["1", "true", "t", "yes", "y"].includes(s)) return true;
  if (["0", "false", "f", "no", "n"].includes(s)) return false;
  return def;
}

function pickTimestamp(data) {
  for (const key of LESSON_START_FIELDS) {
    const v = data[key];
    if (v && typeof v.toDate === "function") return v; // Firestore Timestamp
  }
  return null;
}

async function commitBatch(logger, label, batch, ops) {
  if (ops === 0) return { batch, ops };
  logger.info(`[BATCH COMMIT] ${label} ops=${ops}`);
  await batch.commit();
  return { batch: db.batch(), ops: 0 };
}

exports.deleteFriday3pmLessons = functions.https.onRequest(async (req, res) => {
    const runId = `run_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const logger = functions.logger;

    const studentId = String(req.query.studentId ?? "STU_251224995");
    const commit = parseBool(req.query.commit, false); // 기본 dry-run
    const targetHour = Number(req.query.hour ?? 15);
    const targetMinute = Number(req.query.minute ?? 0);

    logger.info(`[${runId}] START`, { studentId, commit, targetHour, targetMinute });

    const lessonsSnap = await db
      .collection(LESSONS_COL)
      .where(LESSON_STUDENT_FIELD, "==", studentId)
      .get();

    logger.info(`[${runId}] lessons fetched`, { count: lessonsSnap.size });

    const matched = [];
    for (const doc of lessonsSnap.docs) {
      const data = doc.data();
      const startTs = pickTimestamp(data);
      if (!startTs) {
        logger.warn(`[${runId}] SKIP no startTime/date`, { lessonId: doc.id });
        continue;
      }

      const k = toKSTParts(startTs.toDate());
      const isTarget = k.dow === 5 && k.hour === targetHour && k.minute === targetMinute;
      if (!isTarget) continue;

      const teacherId = data[LESSON_TEACHER_FIELD] ?? null;
      matched.push({ lessonId: doc.id, teacherId, startTs, startIsoKst: k.iso });
    }

    logger.info(`[${runId}] matched lessons`, {
      matchedCount: matched.length,
      sample: matched.slice(0, 10),
    });

    if (matched.length === 0) {
      return res.status(200).json({ ok: true, runId, studentId, matched: 0, commit });
    }

    let batch = db.batch();
    let ops = 0;

    let deletedLessons = 0;
    let deletedStudentLessons = 0;
    let deletedBookedSlots = 0;
    let fallbackBookedSlotsQueries = 0;

    async function flushIfNeeded(label) {
      if (!commit) return;
      if (ops >= 450) {
        const r = await commitBatch(logger, `${runId}:${label}(auto)`, batch, ops);
        batch = r.batch;
        ops = r.ops;
      }
    }

    for (const item of matched) {
      const { lessonId, teacherId, startTs, startIsoKst } = item;
      logger.info(`[${runId}] PROCESS`, { lessonId, teacherId, startIsoKst });

      if (commit) {
        batch.delete(db.collection(LESSONS_COL).doc(lessonId));
        ops++;
      }
      deletedLessons++;

      if (commit) {
        batch.delete(
          db.collection(STUDENTS_COL).doc(studentId).collection(STUDENT_LESSONS_SUBCOL).doc(lessonId)
        );
        ops++;
      }
      deletedStudentLessons++;

      if (!teacherId) {
        logger.warn(`[${runId}] teacherId missing -> bookedSlots skip`, { lessonId });
        await flushIfNeeded("loop");
        continue;
      }

      const bookedCol = db
        .collection(TEACHERS_COL)
        .doc(teacherId)
        .collection(TEACHER_BOOKED_SUBCOL);

      let bookedDocs = [];

      try {
        const qs = await bookedCol
          .where(BOOKED_STUDENT_FIELD, "==", studentId)
          .where(BOOKED_DATE_FIELD, "==", startTs)
          .get();
        bookedDocs = qs.docs;
        logger.info(`[${runId}] bookedSlots exactQuery`, { lessonId, teacherId, found: bookedDocs.length });
      } catch (e) {
        fallbackBookedSlotsQueries++;
        logger.warn(`[${runId}] bookedSlots exactQuery FAILED -> fallback`, {
          lessonId,
          teacherId,
          error: String(e?.message ?? e),
        });

        const qs2 = await bookedCol.where(BOOKED_STUDENT_FIELD, "==", studentId).get();
        const targetMs = startTs.toDate().getTime();
        bookedDocs = qs2.docs.filter((d) => {
          const v = d.get(BOOKED_DATE_FIELD);
          return v && typeof v.toDate === "function" && v.toDate().getTime() === targetMs;
        });

        logger.info(`[${runId}] bookedSlots fallbackQuery`, {
          lessonId,
          teacherId,
          fetchedByStudent: qs2.size,
          matchedByDate: bookedDocs.length,
        });
      }

      for (const bd of bookedDocs) {
        if (commit) {
          batch.delete(bd.ref);
          ops++;
        }
        deletedBookedSlots++;
        logger.info(`[${runId}] bookedSlots DELETE`, { teacherId, bookedSlotId: bd.id, lessonId });
        await flushIfNeeded("bookedSlots");
      }

      await flushIfNeeded("loop");
    }

    if (commit) {
      const r = await commitBatch(logger, `${runId}:final`, batch, ops);
      batch = r.batch;
      ops = r.ops;
    }

    logger.info(`[${runId}] DONE`, {
      studentId,
      commit,
      matched: matched.length,
      deletedLessons,
      deletedStudentLessons,
      deletedBookedSlots,
      fallbackBookedSlotsQueries,
    });

    return res.status(200).json({
      ok: true,
      runId,
      studentId,
      commit,
      matched: matched.length,
      deletedLessons,
      deletedStudentLessons,
      deletedBookedSlots,
      fallbackBookedSlotsQueries,
      lessonIds: matched.map((m) => m.lessonId),
    });
  });
