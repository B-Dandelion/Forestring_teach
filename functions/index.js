const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const { setGlobalOptions } = require("firebase-functions/v2");
setGlobalOptions({ region: "asia-northeast3" });

// 학생 아카이빙 함수 가져오기
const { autoArchiveStudents } = require("./archive/autoArchive");
exports.autoArchiveStudents = autoArchiveStudents;

// 수업 자동 생성 함수
const { autoFillFutureLessons } = require("./lesson/autoFillFutureLessons");
exports.autoFillFutureLessons = autoFillFutureLessons;

// 수업 자동 제거 함수
const { cleanupLeftoverLessons } = require("./lesson/cleanupLeftoverLessons");
exports.cleanupLeftoverLessons = cleanupLeftoverLessons;

// 휴원 기간과 겹치는 수업 제거
//const { removeLessonsInHolidayRange } = require("./lesson/removeLessonsInHolidayRange");
//exports.removeLessonsInHolidayRange = removeLessonsInHolidayRange;

// 특정 기간 정규 수업 추가
const { manualCreateRestoredLessons } = require("./lesson/manualCreateRestoredLessons");
exports.manualCreateRestoredLessons = manualCreateRestoredLessons;

// 오전 12시로 잘못 생성된 수업 삭제 함수
const { deleteMidnightLessons } = require("./lesson/deleteMidnightLessons");
exports.deleteMidnightLessons = deleteMidnightLessons;

// 수업 시간 +9시간 하는 함수
const { fixLessonTimes } = require("./lesson/fixLessonTimes");
exports.fixLessonTimes = fixLessonTimes;

// 특정 날짜 이후 수업을 전부 삭제하는 함수 (꼬였을 때 대비)
const { deleteLessonsAfterDate } = require("./lesson/deleteLessonsAfterDate");
exports.deleteLessonsAfterDate = deleteLessonsAfterDate;

// 왜 탈퇴학생 수업 삭제가 안되냐
const { cleanupStudentLessons } = require('./archive/LessonArchive');
exports.cleanupStudentLessons = cleanupStudentLessons;

const { deleteFriday3pmLessons } = require("./lesson/deleteFriday3pmLessons");
exports.deleteFriday3pmLessons = deleteFriday3pmLessons;

const { applyScheduleChangeFromDate } = require("./lesson/applyScheduleChangeFromDate");
exports.applyScheduleChangeFromDate = applyScheduleChangeFromDate;

const { repairBookedSlotsForRun } = require("./lesson/repairBookedSlotsForRun");
exports.repairBookedSlotsForRun = repairBookedSlotsForRun;

const { backfillSemesterLessons } = require("./lesson/backfillSemesterLessons");
exports.backfillSemesterLessons = backfillSemesterLessons;

const { rebuildCode0LessonsFrom20260119 } = require("./lesson/rebuildCode0LessonsFrom20260119");
exports.rebuildCode0LessonsFrom20260119 = rebuildCode0LessonsFrom20260119;