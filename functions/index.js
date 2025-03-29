const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

// 학생 아카이빙 함수 가져오기
const { autoArchiveStudents } = require("./archive/autoArchive");
exports.autoArchiveStudents = autoArchiveStudents;
