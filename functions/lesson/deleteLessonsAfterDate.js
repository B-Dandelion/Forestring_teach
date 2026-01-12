const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const db = admin.firestore();

exports.deleteLessonsAfterDate = onRequest(async (req, res) => {
  try {
    const target = new Date("2026-01-25T00:00:00+09:00"); // 2026-01-25 KST 00:00 포함

    const snap = await db.collection("lessons")
      .where("date", ">=", target)
      .get();

    let deleted = 0;
    let skippedMakeup = 0;

    let batch = db.batch();
    let ops = 0;

    const commitIfNeeded = async (force = false) => {
      if (!force && ops < 450) return; // 500 제한 여유
      if (ops === 0) return;
      await batch.commit();
      batch = db.batch();
      ops = 0;
    };

    for (const doc of snap.docs) {
      const lessonId = doc.id;
      const data = doc.data() || {};

      // ✅ 보강(-1) 제외: "문자열만" 이라면 이걸로 끝
      if (data.code === "-1") {
        skippedMakeup++;
        continue;
      }

      const studentId = data.studentId;
      const teacherId = data.teacherId;

      // 1) lessons/{lessonId}
      batch.delete(db.collection("lessons").doc(lessonId)); ops++;

      // 2) users/{studentId}/lessons/{lessonId}
      if (typeof studentId === "string" && studentId.length > 0) {
        batch.delete(db.collection("users").doc(studentId).collection("lessons").doc(lessonId)); ops++;
      }

      // 3) availableSlots/{teacherId}.bookedSlots[lessonId] (구버전 Map)
      // update는 문서 없으면 터질 수 있어서 merge set으로 안전하게
      if (typeof teacherId === "string" && teacherId.length > 0) {
        const teacherDocRef = db.collection("availableSlots").doc(teacherId);
        batch.set(teacherDocRef, {}, { merge: true }); ops++;

        batch.update(teacherDocRef, {
          [`bookedSlots.${lessonId}`]: admin.firestore.FieldValue.delete(),
        }); ops++;

        // (혹시 남아있으면) availableSlots/{teacherId}/bookedSlots/{lessonId} 도 삭제
        batch.delete(teacherDocRef.collection("bookedSlots").doc(lessonId)); ops++;
      }

      deleted++;
      await commitIfNeeded(false);
    }

    await commitIfNeeded(true);

    res.json({
      ok: true,
      target: target.toISOString(),
      scanned: snap.size,
      deleted,
      skippedMakeup,
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ ok: false, error: String(e?.message || e) });
  }
});