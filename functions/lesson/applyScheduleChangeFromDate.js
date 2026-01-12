const functions = require("firebase-functions");
const admin = require("firebase-admin");

// 3명의 학생 일정 1/19일 이후 수업부터 수정하는 함수

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const KST_OFFSET = 9 * 60 * 60 * 1000;
const DAY_OFF = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

function kstMidnightUtc(y, m, d) {
  // KST yyyy-mm-dd 00:00 -> UTC Date
  return new Date(Date.UTC(y, m, d, 0, 0, 0) - KST_OFFSET);
}

function startOfWeekSundayKSTUtc(d) {
  // d(UTC instant)를 KST로 보고, 그 주(일요일 00:00 KST)의 UTC instant를 반환
  const k = new Date(d.getTime() + KST_OFFSET); // KST를 UTC처럼 다루기
  const dow = k.getUTCDay(); // KST 요일
  const y = k.getUTCFullYear();
  const m = k.getUTCMonth();
  const day = k.getUTCDate();
  const midnightUtc = kstMidnightUtc(y, m, day);
  return new Date(midnightUtc.getTime() - dow * 86400000);
}

function parseHHMM(s) {
  // "17:15"
  const [hh, mm] = String(s).split(":");
  return { h: Number(hh), m: Number(mm) };
}

function pickTimestamp(data) {
  const v = data.startTime ?? data.date;
  return v && typeof v.toDate === "function" ? v : null;
}

function fmtKstIso(d) {
  const k = new Date(d.getTime() + KST_OFFSET);
  return k.toISOString().replace("T", " ").slice(0, 16) + " (KST)";
}

async function commitBatch(logger, label, batch, ops) {
  if (ops === 0) return { batch, ops };
  logger.info(`[BATCH COMMIT] ${label} ops=${ops}`);
  await batch.commit();
  return { batch: db.batch(), ops: 0 };
}

// ✅ 여기만 수정하면 됨: 적용 일정(코드 "0","1" 기준)
const CHANGESET = [
  {
    studentId: "STU_251224556", // 허예준
    items: [
      { code: "0", day: "MO", startTime: "17:15" },
      { code: "1", day: "TH", startTime: "17:15" },
    ],
  },
  {
    studentId: "STU_251224100", // 허예성
    items: [
      { code: "0", day: "TU", startTime: "18:00" },
      { code: "1", day: "FR", startTime: "16:15" },
    ],
  },
  {
    studentId: "STU_251224151", // 허예나
    items: [
      { code: "0", day: "TU", startTime: "18:00" },
      { code: "1", day: "FR", startTime: "16:30" },
    ],
  },
];

exports.applyScheduleChangeFromDate = functions.https.onRequest(async (req, res) => {
  const runId = `run_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const logger = functions.logger;

  const commit = String(req.query.commit ?? "false").toLowerCase() === "true";

  // ✅ 1/19부터 적용 (연도는 현재 맥락상 2026으로 박음)
  const effectiveUtc = kstMidnightUtc(2026, 0, 19);
  const effectiveTs = admin.firestore.Timestamp.fromDate(effectiveUtc);

  logger.info(`[${runId}] START applyScheduleChangeFromDate`, {
    commit,
    effectiveKST: fmtKstIso(effectiveUtc),
    changesetCount: CHANGESET.length,
  });

  let batch = db.batch();
  let ops = 0;

  const summary = [];

  async function flushIfNeeded(label) {
    if (!commit) return;
    if (ops >= 450) {
      const r = await commitBatch(logger, `${runId}:${label}(auto)`, batch, ops);
      batch = r.batch;
      ops = r.ops;
    }
  }

  for (const change of CHANGESET) {
    const { studentId, items } = change;

    logger.info(`[${runId}] STUDENT start`, { studentId, items });

    // 1) 학생 doc weeklySchedule 업데이트
    const stuRef = db.collection("students").doc(studentId);
    const stuSnap = await stuRef.get();
    if (!stuSnap.exists) {
      logger.error(`[${runId}] student doc not found`, { studentId });
      continue;
    }

    const stuData = stuSnap.data() || {};
    const teacherIdFallback = stuData.teacherId || null;
    const weekly = Array.isArray(stuData.weeklySchedule) ? stuData.weeklySchedule : [];

    const byCode = new Map(items.map((x) => [String(x.code), x]));
    const newWeekly = weekly.map((w) => {
      const c = String(w.code ?? "");
      const upd = byCode.get(c);
      if (!upd) return w;
      return { ...w, day: upd.day, startTime: upd.startTime };
    });

    logger.info(`[${runId}] weeklySchedule patch`, {
      studentId,
      before: weekly,
      after: newWeekly,
    });

    if (commit) {
      batch.update(stuRef, { weeklySchedule: newWeekly, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
      ops++;
      await flushIfNeeded("student");
    }

    // 2) 메인 lessons에서 해당 학생 레슨 전부 가져와서(인덱스 회피) 필터
    const lessonsSnap = await db.collection("lessons").where("studentId", "==", studentId).get();

    let touchedLessons = 0;
    let touchedBooked = 0;

    for (const doc of lessonsSnap.docs) {
      const data = doc.data();
      const code = String(data.code ?? "");
      if (!byCode.has(code)) continue;     // 코드 0/1만
      if (code === "-1") continue;         // makeup 같은 건 스킵(원하면 제거)

      const oldTs = pickTimestamp(data);
      if (!oldTs) continue;
      if (oldTs.toMillis() < effectiveTs.toMillis()) continue; // 1/19 이전 스킵

      const teacherId = data.teacherId || teacherIdFallback;
      const oldDate = oldTs.toDate();
      const weekStartUtc = startOfWeekSundayKSTUtc(oldDate);

      const target = byCode.get(code);
      const { h, m } = parseHHMM(target.startTime);
      const dayOff = DAY_OFF[target.day];
      if (dayOff === undefined) continue;

      const newDateUtc = new Date(weekStartUtc.getTime() + dayOff * 86400000 + (h * 3600 + m * 60) * 1000);

      logger.info(`[${runId}] LESSON move`, {
        studentId,
        lessonId: doc.id,
        code,
        teacherId,
        oldKST: fmtKstIso(oldDate),
        newKST: fmtKstIso(newDateUtc),
      });

      // (A) /lessons/{lessonId}
      if (commit) {
        const patch = {
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (data.startTime) patch.startTime = admin.firestore.Timestamp.fromDate(newDateUtc);
        if (data.date) patch.date = admin.firestore.Timestamp.fromDate(newDateUtc);

        batch.update(doc.ref, patch);
        ops++;
        await flushIfNeeded("lessons");
      }

      // (B) /students/{studentId}/lessons/{lessonId}
      const stuLessonRef = db.collection("students").doc(studentId).collection("lessons").doc(doc.id);
      if (commit) {
        const patch2 = {
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (data.startTime) patch2.startTime = admin.firestore.Timestamp.fromDate(newDateUtc);
        if (data.date) patch2.date = admin.firestore.Timestamp.fromDate(newDateUtc);

        batch.update(stuLessonRef, patch2);
        ops++;
        await flushIfNeeded("studentLessons");
      }

      // (C) /teachers/{teacherId}/bookedSlots : (studentId + date==oldTs) 찾아서 date 업데이트
      if (teacherId) {
        const bookedCol = db.collection("teachers").doc(teacherId).collection("bookedSlots");

        // 인덱스 없을 수 있어서 studentId만 쿼리 후 date ms로 필터
        const bsSnap = await bookedCol.where("studentId", "==", studentId).get();
        const oldMs = oldTs.toDate().getTime();

        const matchedBooked = bsSnap.docs.filter((b) => {
          const v = b.get("date");
          return v && typeof v.toDate === "function" && v.toDate().getTime() === oldMs;
        });

        logger.info(`[${runId}] bookedSlots match`, {
          studentId,
          teacherId,
          lessonId: doc.id,
          fetchedByStudent: bsSnap.size,
          matchedByDate: matchedBooked.length,
        });

        for (const b of matchedBooked) {
          if (commit) {
            batch.update(b.ref, {
              date: admin.firestore.Timestamp.fromDate(newDateUtc),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            ops++;
            await flushIfNeeded("bookedSlots");
          }
          touchedBooked++;
        }
      } else {
        logger.warn(`[${runId}] teacherId missing -> bookedSlots skip`, { studentId, lessonId: doc.id });
      }

      touchedLessons++;
    }

    summary.push({ studentId, touchedLessons, touchedBooked });
    logger.info(`[${runId}] STUDENT done`, { studentId, touchedLessons, touchedBooked });

    await flushIfNeeded("loop");
  }

  if (commit) {
    const r = await commitBatch(logger, `${runId}:final`, batch, ops);
    batch = r.batch;
    ops = r.ops;
  }

  logger.info(`[${runId}] DONE`, { commit, summary });

  return res.status(200).json({
    ok: true,
    runId,
    commit,
    effectiveKST: fmtKstIso(effectiveUtc),
    summary,
  });
});
