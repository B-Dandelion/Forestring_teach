const admin = require("firebase-admin");
const { onDocumentCreated, onDocumentUpdated } = functions; // 문서 생성, 업뎃 될 때 트리거 됨
const db = admin.firestore();

const sendNotification = async (title, body, studentId, teacherId, skipStudent = false) => {
  // 알람을 보낸다예요 함수
  const tokens = [];

  const studentSnap = await db.collection("users").doc(studentId).get();
  const teacherSnap = await db.collection("users").doc(teacherId).get();

  const studentToken = studentSnap.data().fcmToken;
  const teacherToken = teacherSnap.data().fcmToken;

  if (studentToken && !skipStudent) tokens.push(studentToken);
  if (teacherToken) tokens.push(teacherToken);

  if (tokens.length > 0) {
    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
    });
    console.log(`📤 알림 전송 완료: ${tokens.length}개`);
  }
};
const getTimeRange = (date, duration) => {
      const start = new Date(date.seconds * 1000);
      const end = new Date(start.getTime() + duration * 60000);
      const format = (d) => `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
      return `${format(start)} ~ ${format(end)}`;
    };

const lessonCreated = onDocumentCreated("lessons/{lessonId}", async (event) => {
  // 레슨 생성이 감지되었을 때, 가는 알림!
  const lesson = event.data.data();
  const { isRescheduled, code, studentId, teacherId, date, duration, RescheduledBy } = lesson;

  if (!isRescheduled) return;

  const getUserName = async (userId) => {
    const snap = await db.collection("users").doc(userId).get();
    return snap.exists ? snap.data().name : "알 수 없음";
  };

  const [studentName, teacherNameRaw] = await Promise.all([
    getUserName(studentId),
    getUserName(teacherId),
  ]);

  const teacherName = `${teacherNameRaw} 선생님`;
  const timeText = getTimeRange(date, duration);
  const title = code === -1 ? "보강 수업이 등록되었습니다." : "새로운 수업이 예약되었습니다.";
  const body = `${teacherName} / ${studentName} ${timeText} 수업이 등록되었습니다.`;

  // 본인이 예약한 수업이고 보강이 아닌 경우 → 학생에게 알림 보내지 않음
  const skipStudent = code !== -1 && RescheduledBy === studentId;

  await sendNotification(title, body, studentId, teacherId, skipStudent);
  console.log(`✅ [Created] 알림 보냄 - ${studentName} / ${teacherName} / ${timeText}`);
});

const lessonUpdated = onDocumentUpdated("lessons/{lessonId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  const { studentId, teacherId, date, duration } = after;

  // 변경이 없으면 무시
  if (
    before.isRescheduled === after.isRescheduled &&
    before.status === after.status &&
    before.code === after.code
  ) {
    console.log("단순 변경 무시됨");
    return;
  }

  // Firestore에서 이름 가져오기
  const studentSnap = await db.collection("users").doc(studentId).get();
  const teacherSnap = await db.collection("users").doc(teacherId).get();

  const studentName = studentSnap.exists ? studentSnap.data().name : "학생";
  const teacherName = teacherSnap.exists ? teacherSnap.data().name : "선생님";
  const teacherDisplayName = `${teacherName} 선생님`;

  const timeText = getTimeRange(date.toDate(), after.duration);

  // 취소된 경우
  if (before.status === "confirm" && after.status === "canceled") {
    const title = "수업이 취소되었습니다.";
    const body = `${teacherDisplayName} / ${studentName} ${timeText} 수업이 취소되었습니다.`;
    await sendNotification(title, body, studentId, teacherId);
    console.log(`✅ [Canceled] 알림 보냄 - ${studentName} / ${teacherName} / ${timeText}`);
    return;
  }

  // 수업 변경
  if (!before.isRescheduled && after.isRescheduled) {
    const title = "수업이 변경되었습니다.";
    const body = `${teacherDisplayName} / ${studentName} ${timeText} 수업 일정이 변경되었습니다.`;
    await sendNotification(title, body, studentId, teacherId);
    console.log(`✅ [Changed] 알림 보냄 - ${studentName} / ${teacherName} / ${timeText}`);

  }
});

module.exports = {
  lessonCreated,
  lessonUpdated,
};
