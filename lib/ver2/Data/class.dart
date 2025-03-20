import 'package:cloud_firestore/cloud_firestore.dart';

// 2월 20일에 새롭게 작성하는 선생님 / 학생 클래스.
// Lesson 클래스도 함께!
// 학생과 선생님 클래스를 한 곳에 작성한다.

// firebase에 미리 작성해둔 구조를 토대로 작성하기.

// new TeacherClass code
class Teacher {
  final String id;  // Firestore 문서 ID
  final String name;
  final String password;
  final String role; // "teacher" 고정
  final List<String> studentIds; // 담당 학생 ID 리스트

  Teacher({
    required this.id,
    required this.name,
    required this.password,
    required this.role,
    required this.studentIds,
  });

  // Firestore에서 가져온 데이터를 Dart 객체로 변환
  factory Teacher.fromMap(Map<String, dynamic> data, String documentId) {
    return Teacher(
      id: documentId,
      name: data['name'] as String,
      password: data['password'] as String,
      role: data['role'] ?? 'teacher',
      studentIds: List<String>.from(data['studentIds'] ?? []),
    );
  }

  // Dart 객체를 Firestore 문서 형태로 변환
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'password': password,
      'role': role,
      'studentIds': studentIds,
    };
  }
}


// new StudentClass code
class Student {
  final String id;  // Firestore 문서 ID
  final String name;
  final String password;
  final String role; // "student" 고정
  final String teacherId;
  final List<Lesson>? lessons; // 학생의 수업 정보 (선택적)

  Student({
    required this.id,
    required this.name,
    required this.password,
    required this.role,
    required this.teacherId,
    this.lessons,
  });

  // Firestore에서 가져온 데이터를 Dart 객체로 변환
  factory Student.fromMap(Map<String, dynamic> data, String documentId, {List<Lesson>? lessons}) {
    return Student(
      id: documentId,
      name: data['name'] as String,
      password: data['password'] as String,
      role: data['role'] ?? 'student',
      teacherId: data['teacherId'] as String,
      lessons: lessons,
    );
  }

  // Dart 객체를 Firestore 문서 형태로 변환
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'password': password,
      'role': role,
      'teacherId': teacherId,
    };
  }
}


// Lesson 클래스.

// 새로운 코드
class Lesson {
  final String id;  // Firestore 문서 ID (lesson 고유 아이디)
  final String studentId;
  final String teacherId;
  final DateTime date;
  final int duration;
  final bool isRescheduled;
  final String status; // ["confirmed", "canceled"]
  final DateTime createdAt;
  final DateTime updatedAt;

  Lesson({
    required this.id,
    required this.studentId,
    required this.teacherId,
    required this.date,
    this.duration = 30,
    this.isRescheduled = false,
    this.status = "confirmed",
    required this.createdAt,
    required this.updatedAt,
  });

  // Firestore에서 가져온 데이터를 Dart 객체로 변환
  factory Lesson.fromMap(Map<String, dynamic> data, String documentId) {
    return Lesson(
      id: documentId,
      studentId: data['studentId'] as String,
      teacherId: data['teacherId'] as String,
      date: (data['date'] as Timestamp).toDate(),
      duration: data['duration'] ?? 30,
      isRescheduled: data['isRescheduled'] ?? false,
      status: data['status'] ?? 'confirmed',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  // Dart 객체를 Firestore 문서 형태로 변환
  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'teacherId': teacherId,
      'date': Timestamp.fromDate(date),
      'duration': duration,
      'isRescheduled': isRescheduled,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
