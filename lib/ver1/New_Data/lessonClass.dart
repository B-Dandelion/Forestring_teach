import 'package:cloud_firestore/cloud_firestore.dart';

class Lesson {
  final String id; // 수업 ID
  final DateTime time; // 수업 시간
  bool isValid; // 취소 여부

  Lesson({
    required this.id,
    required this.time,
    required this.isValid,
  });

  // Firestore에서 데이터를 받아올 때 사용
  Lesson.fromJson({
    required Map<String, dynamic> json ,
    required this.id,})
      : time = (json['time'] as Timestamp).toDate(),
        isValid = json['valid'];

  // Firestore에 저장할 때 사용
  Map<String, dynamic> toJson() {
    return {
      'time': Timestamp.fromDate(time),
      'valid': isValid,
    };
  }
}
