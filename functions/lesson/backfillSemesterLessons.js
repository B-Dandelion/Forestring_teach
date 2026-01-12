const admin = require("firebase-admin");
const functions = require("firebase-functions");
const { onRequest } = require("firebase-functions/v2/https");

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const REGION = "asia-northeast3";
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const dayMap = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

function parseBool(v, defaultValue = false) {
  if (v === undefined || v === null) return defaultValue;
  const s = String(v).toLowerCase();
  return s === "1" || s === "true" || s === "yes" || s === "y";
}

function requireAdminToken(req, res) {
  const cfgToken = functions.config()?.admintasks?.token;
  const token = req.query.token;
  if (!cfgToken || !token || token !== cfgToken) {
    res.status(403).send("Forbidden (bad token)");
    return false;
  }
  return true;
}

function getKstDay(date) {
  return new Date(date.getTime() + KST_OFFSET_MS).getUTCDay();
}

function getFirstDateMatchingDayKST(startDate, dayCode) {
  const targetDay = dayMap[dayCode];
  const d = new Date(startDate.getTime());
  while (getKstDay(d) !== targetDay) {
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return d;
}

function isHoliday(date, holidays) {
  // end exclusive
  return holidays.some(h => date >= h.start && date < h.end);
}

function addDaysUTC(date, days) {
  const d = new Date(date.getTime());
  d.setUTCDate(d.getUTCDate() + days);
  return d;
}

exports.backfillSemesterLessons = onRequest(
  { region: REGION, invoker: "public", timeoutSeconds: 540 },
  async (req, res) => {
    try {
      if (!requireAdminToken(req, res)) return;

      const semesterId = String(req.query.semesterId || "").trim();
      const commit = parseBool(req.query.commit, false);
      const onlyTeacherId = String(req.query.teacherId || "").trim();
      const onlyStudentId = String(req.query.studentId || "").trim();

      if (!semesterId) {
        res.status(400).json({ ok: false, error: "semesterId is required" });
        return;
      }

      const runId = `backfill_${semesterId}_${Date.now()}`;
      console.log(`[backfill] start runId=${runId} semesterId=${semesterId} commit=${commit}`);

      // semester 로드
      const semDoc = await db.collection("semesters").doc(semesterId).get();
      if (!semDoc.exists) {
        res.status(404).json({ ok: false, error: `semester not found: ${semesterId}` });
        return;
      }

      const sem = semDoc.data();
      const start = sem.startDate.toDate();
      const end = sem.endDate.toDate(); // end exclusive
      const holidays = (sem.holidayPeriods || []).map(h => ({
        start: h.startDate.toDate(),
        end: h.endDate.toDate(),
      }));

      // 학생 로드
      let studentsQuery = db.collection("users").where("role", "==", "student");
      if (onlyTeacherId) studentsQuery = studentsQuery.where("teacherId", "==", onlyTeacherId);

      let students = [];
      if (onlyStudentId) {
        const st = await db.collection("users").doc(onlyStudentId).get();
        if (st.exists && st.data()?.role === "student") students = [st];
        else students = [];
      } else {
        const snap = await studentsQuery.get();
        students = snap.docs;
      }

      let batch = db.batch();
      let opCount = 0;

      let studentProcessed = 0;
      let totalPlannedCreate = 0;

      async function flushBatch() {
        if (opCount === 0) return;
        if (!commit) {
          opCount = 0;
          batch = db.batch();
          return;
        }
        await batch.commit();
        opCount = 0;
        batch = db.batch();
      }

      for (const stDoc of students) {
        const studentId = stDoc.id;
        const st = stDoc.data() || {};
        const teacherId = st.teacherId;
        const schedule = st.weeklySchedule;

        studentProcessed++;

        if (!teacherId) {
          console.warn(`[backfill][${runId}] teacherId 없음: ${studentId}`);
          continue;
        }
        if (!Array.isArray(schedule) || schedule.length === 0) {
          console.warn(`[backfill][${runId}] weeklySchedule 없음: ${studentId}`);
          continue;
        }

        // 학기 범위 내 기존 수업만 쿼리(가벼움)
        const existingSnap = await db
          .collection(`users/${studentId}/lessons`)
          .where("date", ">=", start)
          .where("date", "<", end)
          .get();

        const existingTimeKeys = new Set();
        for (const l of existingSnap.docs) {
          const raw = l.data()?.date;
          if (!raw || typeof raw.toDate !== "function") continue;
          const d = raw.toDate();
          existingTimeKeys.add(Math.floor(d.getTime() / 60000));
        }

        const createdLessonIds = [];
        const alreadyHadTimes = [];

        for (const sched of schedule) {
          const { day, startTime, duration, code } = sched || {};
          if (!dayMap.hasOwnProperty(day) || typeof startTime !== "string") continue;

          const dur = Number(duration) || 0;
          const baseCode = `${day}${startTime.replace(":", "")}`;
          const [hour, minute] = startTime.split(":").map(Number);

          // 1) 이 학기에서 "휴일 제외하고" 해당 요일/시간의 후보 날짜를 쭉 만들고, 앞에서 4개만 target로 잡음
          let cursor = getFirstDateMatchingDayKST(start, day);
          cursor.setUTCHours(hour - 9, minute, 0, 0);

          const targetDates = [];
          while (cursor < end && targetDates.length < 4) {
            if (!isHoliday(cursor, holidays)) targetDates.push(cursor);
            cursor = addDaysUTC(cursor, 7);
          }

          // 2) targetDates 각각이 "이미 있는 시간인지" 확인하고 없으면 생성
          for (let i = 0; i < targetDates.length; i++) {
            const dt = targetDates[i];
            const timeKey = Math.floor(dt.getTime() / 60000);

            if (existingTimeKeys.has(timeKey)) {
              alreadyHadTimes.push(dt.toISOString());
              continue;
            }

            const suffix = String(i + 1).padStart(3, "0"); // ✅ 날짜 기준 1~4 고정
            const lessonId = `${studentId}_${semesterId}_${baseCode}${suffix}`;

            // 혹시 id가 이미 있으면 스킵(희귀 케이스)
            const lessonRef = db.collection("lessons").doc(lessonId);
            const exists = await lessonRef.get();
            if (exists.exists) {
              // id는 있는데 timeKey는 없다? 이상 케이스라 기록만
              console.warn(`[backfill][${runId}] ID exists but time missing? ${lessonId}`);
              continue;
            }

            const lessonData = {
              code,
              date: dt,
              duration: dur,
              isRescheduled: false,
              status: "confirmed",
              studentId,
              teacherId,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              backfillRunId: runId,
              source: "backfill",
            };

            // 1) lessons
            batch.set(lessonRef, lessonData); opCount++;

            // 2) users/{studentId}/lessons
            const studentRef = db.collection("users").doc(studentId).collection("lessons").doc(lessonId);
            batch.set(studentRef, lessonData); opCount++;

            // 3) (구버전) availableSlots/{teacherId}.bookedSlots.{lessonId}
            const teacherDocRef = db.collection("availableSlots").doc(teacherId);
            const updateData = {};
            updateData[`bookedSlots.${lessonId}`] = {
              date: dt,
              duration: dur,
              isRescheduled: false,
              status: "confirmed",
              studentId,
            };
            batch.update(teacherDocRef, updateData); opCount++;

            createdLessonIds.push(lessonId);
            existingTimeKeys.add(timeKey);
            totalPlannedCreate++;

            if (opCount >= 450) await flushBatch();
          }
        }

        await flushBatch();

        console.log(`[backfill][${runId}] student=${studentId} created=${createdLessonIds.length}`);

        if (commit) {
          await db
            .collection("adminLogs")
            .doc("backfillSemesterLessons")
            .collection("runs")
            .doc(runId)
            .collection("students")
            .doc(studentId)
            .set(
              {
                studentId,
                teacherId,
                semesterId,
                createdLessonIds,
                alreadyHadTimes,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
        }
      }

      console.log(`[backfill] end runId=${runId} students=${studentProcessed} plannedCreate=${totalPlannedCreate}`);
      res.json({
        ok: true,
        runId,
        semesterId,
        commit,
        studentProcessed,
        plannedCreate: totalPlannedCreate,
        filters: { teacherId: onlyTeacherId || null, studentId: onlyStudentId || null },
      });
    } catch (e) {
      console.error("[backfillSemesterLessons] ERROR", e);
      res.status(500).json({ ok: false, error: String(e?.message || e) });
    }
  }
);
