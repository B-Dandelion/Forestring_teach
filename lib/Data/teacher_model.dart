
class TeacherModel{
  //학생 클래스(이름,수업 시작 시간, 수업 요일)

  final String id;
  final String name;
  final Map<String,List> worktime;
  final List<dynamic> students;

  TeacherModel({required this.id, required this.name,
    required this.worktime, required this.students});

  TeacherModel.fromJson({
    required Map<String, dynamic> json,
  }) : id = json['id'],
        name = json['name'],
        worktime = {'Mon' : [json['Mon'][0].toDate(), json['Mon'][1].toDate()],
          'Tue' : [json['Tue'][0].toDate(), json['Tue'][1].toDate()],
          'Wed' : [json['Wed'][0].toDate(), json['Wed'][1].toDate()],
          'Thu' : [json['Thu'][0].toDate(), json['Thu'][1].toDate()],
          'Fri' : [json['Fri'][0].toDate(), json['Fri'][1].toDate()],
          'Sat' : [json['Sat'][0].toDate(), json['Sat'][1].toDate()],
        },
        students = [json['students']];

  Map<String, dynamic> toJson() {
    return {
      'id' : id,
      'name' : name,
      'worktime' : worktime,
      'students' : students
    };
  }
}
