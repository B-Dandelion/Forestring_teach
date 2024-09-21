class ScheduleModel {
  final String id;
  final String teacher;
  final DateTime date;
  final int startTime;
  final int endTime;

  ScheduleModel({
    required this.id,
    required this.teacher,
    required this.date,
    required this.startTime,
    required this.endTime,
  });

  ScheduleModel.fromJson({
    required Map<String, dynamic> json,
  }) : id = json['id'],
        teacher = json['teacher'],
        date = DateTime.parse(json['date']),
        startTime = json['startTime'],
        endTime = json['endTime'];

  Map<String, dynamic> toJson(){
    return {
      'id' : id,
      'teacher' : teacher,
      'date' : '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}',
      'startTime' : startTime,
      'endTime' : endTime,
    };
  }

  ScheduleModel copyWith({
    String? id,
    String? teacher,
    DateTime? date,
    int? startTime,
    int? endTime,
  }) {
    return ScheduleModel(
      id: id ?? this.id,
      teacher: teacher ?? this.teacher,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

