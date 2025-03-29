const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");

const db = admin.firestore();
setGlobalOptions({ region: "asia-northeast3" }); // 서울 리전

const autoArchiveStudents = onSchedule(
  { schedule: "every 24 hours", timeZone: "Asia/Seoul" },
  async () => {
    // withdrawalDate랑 날짜 비교를 위해 오늘 날짜를 Timestamp 형식으로 저장
    const now = new Date();
    now.setHours(0, 0, 0, 0);
    const todayTS = admin.firestore.Timestamp.fromDate(now);
    // 유저 - 학생 중 탈퇴 날짜가 오늘 이후인 경우
    const studentsSnapshot = await db.collection("users")
      .where("role", "==", "student")
      .where("withdrawalDate", "<", todayTS)
      .get();

    for (const doc of studentsSnapshot.docs) {
    // 위에서 찾은 학생들을 한 명씩 처리함
      const studentId = doc.id;
      const student = doc.data();
      const { name, teacherId } = student; // 이름과 담당 선생님 ID만 꺼냄

      console.log(`아카이빙 시작: ${studentId} (${name})`);

      const batch = db.batch(); // 작업 동기화를 위한 배치 선언

      // 1. users/{studentId} → archivedUsers/{studentId}
      batch.set(db.collection("archivedUsers").doc(studentId), student);

      // 2. users/{studentId}/lessons → archivedLessons/{studentId}/lessons
      const lessonsRef = db.collection(`users/${studentId}/lessons`);
      const lessonsSnap = await lessonsRef.get();

      for (const lessonDoc of lessonsSnap.docs) {
        const lessonId = lessonDoc.id;
        const lessonData = lessonDoc.data();

        const archivedLessonRef = db.collection(`archivedLessons/${studentId}/lessons`).doc(lessonId);
        batch.set(archivedLessonRef, lessonData); // 아카이브 장소에 백업
        // users/{studentId}/lessons/{lessonId} 삭제
        batch.delete(lessonsRef.doc(lessonId));
      }

      // 3. usersByName/{studentName}에서 제거
      const nameDocRef = db.collection("usersByName").doc(name);
      const nameSnap = await nameDocRef.get();

      if (nameSnap.exists) {
        const ids = nameSnap.data().userIds || [];
        const filtered = ids.filter(id => id !== studentId);
        if (filtered.length > 0) {
          batch.update(nameDocRef, { userIds: filtered });
        } else {
          batch.delete(nameDocRef); // 더 이상 이 이름을 쓰는 학생이 없으면 문서 삭제
        }
      }

      // 4. teacher 문서에서 studentId 제거
      if (teacherId) {
        const teacherRef = db.collection("users").doc(teacherId);
        const teacherSnap = await teacherRef.get();
        if (teacherSnap.exists) {
          const studentIds = teacherSnap.data().studentIds || [];
          const updated = studentIds.filter(id => id !== studentId);
          batch.update(teacherRef, { studentIds: updated });
        }
      }

      // 5. users/{studentId} 삭제
      batch.delete(db.collection("users").doc(studentId));

      await batch.commit();
      console.log(`✅ 아카이빙 완료: ${studentId}`);
    }

    console.log("자동 아카이빙 작업 종료");
  });

module.exports = { autoArchiveStudents }; // 8. 함수 export
