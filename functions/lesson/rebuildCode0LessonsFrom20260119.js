const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const db = admin.firestore();
const ADMIN_TASK_TOKEN = defineSecret("ADMIN_TASK_TOKEN");

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY = 24 * 60 * 60 * 1000;

const dayMap = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

function toBool(v, def = false) {
  if (typeof v === "boolean") return v;
  if (typeof v !== "string") return def;
  const s = v.trim().toLowerCase();
  if (["1", "true", "t", "yes", "y"].includes(s)) return true;
  if (["0", "false", "f", "no", "n"].includes(s)) return false;
  return def;
}

function minuteKey(date) {
  return Math.floor(date.getTime() / 60000);
}

function kstPartsFromUtc(date) {
  const k = new Date(date.getTime() + KST_OFFSET_MS);
  return {
    y: k.getUTCFullYear(),
    m: k.getUTCMonth() + 1,
    d: k.getUTCDate(),
    dow: k.getUTCDay(), // KST 기준 요일
  };
}

function utcFromKstParts(y, m, d, hh, mm) {
  // KST 시간을 UTC로 변환해서 Date 생성
  return new Date(Date.UTC(y, m - 1, d, hh - 9, mm, 0, 0));
}

function parseHHMM(str) {
  const [h, m] = String(str).split(":").map(Number);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
  return { h, m };
}

// baseUtc(포함) 이후에서, KST 기준 dayCode 요일 + startTime 시간인 첫 UTC instant 반환
function firstOccurrenceUtc(baseUtc, dayCode, startTime) {
  const targetDow = dayMap[dayCode];
  const t = parseHHMM(startTime);
  if (targetDow == null || !t) return null;

  // base의 KST 날짜를 기준으로 후보 생성
  let { y, m, d } = kstPartsFromUtc(baseUtc);
  let cand = utcFromKstParts(y, m, d, t.h, t.m);

  // 같은 KST 날짜라도 cand가 base보다 이전이면 다음날로
  if (cand < baseUtc) cand = new Date(cand.getTime() + DAY);

  // 요일 맞출 때까지 하루씩
  while (kstPartsFromUtc(cand).dow !== targetDow) {
    cand = new Date(cand.getTime() + DAY);
  }
  return cand;
}

function isHolidayUtc(dateUtc, holidays) {
  // [start, end) (end exclusive)
  return holidays.some(h => dateUtc >= h.start && dateUtc < h.end);
}

async function loadSemesters() {
  const snap = await db.collection("semesters").orderBy("startDate").get();
  return snap.docs.map(d => ({ id: d.id, ...d.data() }));
}

// teacher bookedSlots(Map)에서 minuteKey->lessonId 인덱스 만들기
async function loadTeacherBookedIndex(teacherId, ignoreLessonIds = new Set()) {
  const ref = db.collection("availableSlots").doc(teacherId);
  const snap = await ref.get();
  const data = snap.exists ? snap.data() : null;
  const booked = data?.bookedSlots || {};

  const idx = new Map();
  for (const [lessonId, v] of Object.entries(booked)) {
    if (!v || ignoreLessonIds.has(lessonId)) continue;
    const raw = v.date;
    let dt = null;
    if (raw && typeof raw.toDate === "function") dt = raw.toDate();
    else if (raw instanceof Date) dt = raw;
    if (!dt) continue;
    idx.set(minuteKey(dt), lessonId);
  }
  return { teacherRef: ref, index: idx };
}

const rebuildCode0LessonsFrom20260119 = onRequest(
  {
    region: "asia-northeast3",
    timeoutSeconds: 540,
    secrets: [ADMIN_TASK_TOKEN],
  },
  async (req, res) => {
    try {
      const token = String(req.query.token || req.get("x-admin-token") || "");
      if (!token || token !== ADMIN_TASK_TOKEN.value()) {
        return res.status(403).json({ ok: false, error: "forbidden" });
      }

      const commit = toBool(req.query.commit, false);
      const mode = String(req.query.mode || "both"); // delete | create | both

      const cutoff = new Date("2026-01-19T00:00:00+09:00"); // ✅ 2026년 1/19 (포함)
      const runId = `rebuild_code0_${new Date().toISOString().slice(0, 10)}_${Date.now()}`;

      // 학생별 code0 타겟 시간표
      const targets = [
        { studentId: "STU_251224100", code: "0", toDay: "TU", toStartTime: "18:00" }, // 예성
        { studentId: "STU_251224151", code: "0", toDay: "TU", toStartTime: "18:15" }, // 예나
      ];

      // 생성은 "현재 학기 포함 + 이후 3개 학기"만 (원하면 숫자 바꾸면 됨)
      const semesterCount = 3;
      const semesters = await loadSemesters();

      const writer = db.bulkWriter();
      const out = {
        ok: true,
        runId,
        commit,
        mode,
        cutoff: cutoff.toISOString(),
        students: {},
        totals: { deleteScanned: 0, deleted: 0, created: 0, conflicts: 0, scheduleUpdated: 0 },
      };

      for (const t of targets) {
        const { studentId, code, toDay, toStartTime } = t;
        out.students[studentId] = {
          studentId,
          code,
          teacherId: null,
          deleteScanned: 0,
          deleted: 0,
          created: 0,
          conflicts: 0,
          scheduleUpdated: false,
          deleteLessonIds: [],
          createLessonIds: [],
        };

        const userRef = db.collection("users").doc(studentId);
        const userSnap = await userRef.get();
        if (!userSnap.exists) continue;

        const user = userSnap.data();
        const teacherId = user.teacherId;
        const weeklySchedule = Array.isArray(user.weeklySchedule) ? user.weeklySchedule : [];

        out.students[studentId].teacherId = teacherId || null;
        if (!teacherId) continue;

        // 1) 삭제 대상 lessonIds 수집 (학생 서브컬렉션에서 date>=cutoff만 읽고, code=='0'만 필터)
        const userLessonsSnap = await userRef.collection("lessons")
          .where("date", ">=", cutoff)
          .get();

        const deleteLessonIds = [];
        for (const d of userLessonsSnap.docs) {
          out.students[studentId].deleteScanned++;
          out.totals.deleteScanned++;

          const v = d.data();
          if (String(v.code) !== String(code)) continue; // ✅ code '0'만
          deleteLessonIds.push(d.id);
        }
        out.students[studentId].deleteLessonIds = deleteLessonIds;

        // teacher 인덱스는 "삭제 예정 lessonId는 무시"하고 만듦(드라이런/동시 실행 시 충돌 방지)
        const ignoreSet = new Set(deleteLessonIds);
        const { teacherRef, index: teacherIndex } = await loadTeacherBookedIndex(teacherId, ignoreSet);

        // 2) weeklySchedule에서 code '0' 항목을 새 시간표로 수정
        const newSchedule = weeklySchedule.map(s => ({ ...s }));
        const idx = newSchedule.findIndex(s => s && String(s.code) === String(code));
        if (idx !== -1) {
          newSchedule[idx].day = toDay;
          newSchedule[idx].startTime = toStartTime;

          out.students[studentId].scheduleUpdated = true;
          out.totals.scheduleUpdated++;

          if (commit && (mode === "create" || mode === "both")) {
            writer.update(userRef, {
              weeklySchedule: newSchedule,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              timetableChangeRunId: runId,
            });
          }
        }

        // 3) 삭제 실행
        if (mode === "delete" || mode === "both") {
          for (const lessonId of deleteLessonIds) {
            if (!commit) continue;

            // root lessons
            writer.delete(db.collection("lessons").doc(lessonId));
            // users/{sid}/lessons
            writer.delete(userRef.collection("lessons").doc(lessonId));

            // availableSlots/{tid}.bookedSlots[lessonId] (Map) — doc 없어도 터지지 않게 set+merge로 delete
            writer.set(
              teacherRef,
              { bookedSlots: { [lessonId]: admin.firestore.FieldValue.delete() } },
              { merge: true }
            );

            // 혹시 남아있을 수 있는 서브컬렉션 형태도 정리 (있어도/없어도 delete는 안전)
            writer.delete(
              db.collection("availableSlots").doc(teacherId).collection("bookedSlots").doc(lessonId)
            );

            out.students[studentId].deleted++;
            out.totals.deleted++;
          }
        }

        // 4) 새로 생성 (code '0' 한 항목만 / 학기당 최대 4개 / 휴일 스킵)
        if (mode === "create" || mode === "both") {
          // 생성 대상 학기: endDate > cutoff 인 첫 학기부터 semesterCount개
          const futureSemesters = semesters
            .filter(s => s.endDate?.toDate && s.endDate.toDate() > cutoff)
            .slice(0, semesterCount);

          for (const sem of futureSemesters) {
            const semesterId = sem.id;
            const startUtc = sem.startDate.toDate();
            const endUtc = sem.endDate.toDate(); // end exclusive

            const holidays = (sem.holidayPeriods || []).map(h => ({
              start: h.startDate.toDate(),
              end: h.endDate.toDate(), // end exclusive
            }));

            const baseUtc = (cutoff > startUtc) ? cutoff : startUtc;
            let cur = firstOccurrenceUtc(baseUtc, toDay, toStartTime);
            if (!cur) continue;

            let made = 0;
            let seq = 1;

            while (cur < endUtc && made < 4) {
              // 휴일이면 그냥 다음주
              if (isHolidayUtc(cur, holidays)) {
                cur = new Date(cur.getTime() + 7 * DAY);
                continue;
              }

              // teacher 충돌 체크
              const k = minuteKey(cur);
              const occupied = teacherIndex.get(k);
              if (occupied) {
                out.students[studentId].conflicts++;
                out.totals.conflicts++;
                cur = new Date(cur.getTime() + 7 * DAY);
                continue;
              }

              const baseCode = `${toDay}${toStartTime.replace(":", "")}`;
              const suffix = String(seq).padStart(3, "0");
              const lessonId = `${studentId}_${semesterId}_${baseCode}${suffix}`;
              seq++;

              // (혹시 남아있는 동일 ID가 있으면 스킵)
              // root 확인을 위해 get하면 느려지니까, 그냥 set(merge=false)로 덮어쓰기 위험이 싫으면 여기서 get 넣어도 됨.
              // 너 상황상 "삭제 후 생성"이라 거의 없음. 그래도 안전하게 get 한 번만:
              const rootRef = db.collection("lessons").doc(lessonId);
              const exists = await rootRef.get();
              if (exists.exists) {
                cur = new Date(cur.getTime() + 7 * DAY);
                continue;
              }

              const lessonData = {
                code: String(code),
                date: cur,
                duration: Number(newSchedule[idx]?.duration) || 15,
                isRescheduled: false,
                status: "confirmed",
                studentId,
                teacherId,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                rebuildRunId: runId,
              };

              out.students[studentId].createLessonIds.push(lessonId);

              if (commit) {
                // lessons
                writer.set(rootRef, lessonData);
                // users/{sid}/lessons
                writer.set(userRef.collection("lessons").doc(lessonId), lessonData);

                // availableSlots/{tid}.bookedSlots[lessonId]
                writer.set(
                  teacherRef,
                  {
                    bookedSlots: {
                      [lessonId]: {
                        date: cur,
                        duration: lessonData.duration,
                        isRescheduled: false,
                        status: "confirmed",
                        studentId,
                        lessonId,
                        teacherId,
                        rebuildRunId: runId,
                      },
                    },
                  },
                  { merge: true }
                );
              }

              // 인덱스 갱신해서 같은 실행 중 중복 방지
              teacherIndex.set(k, lessonId);

              made++;
              out.students[studentId].created++;
              out.totals.created++;

              cur = new Date(cur.getTime() + 7 * DAY);
            }
          }
        }
      }

      await writer.close();

      return res.json(out);
    } catch (e) {
      console.error(e);
      return res.status(500).json({ ok: false, error: String(e?.message || e) });
    }
  }
);

module.exports = { rebuildCode0LessonsFrom20260119 };
