import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherClass{
  //학생 클래스

  final String id;
  final String name;
  final String role;
  final String password;
  final List<String> studentList;
  final List<DateTime> workTime;
  final List<String> classList;

  TeacherClass({required this.id, required this.name, required this.role, required this.password,
    required this.studentList, required this.workTime, required this.classList});

  TeacherClass.fromJson({
    required Map<String, dynamic> json,
  }) : id = json['id'],
        name = json['name'],
        role = json['role'],
        password = json['password'],
        studentList = List<String>.from(json['studentList']),
  // workTime = List<DateTime>.from(json['workTime'].toDate()),
        workTime = List<DateTime>.from(
            json['workTime']?.map((item) => (item as Timestamp).toDate()) ?? []),
        classList = List<String>.from(json['classList']);


  Map<String, dynamic> toJson() {
    return {
      'id' : id,
      'name' : name,
      'role' : role,
      'password' : password,
      'studentList' : studentList,
      'workTime' : workTime,
      'classList' : classList,
    };
  }
}