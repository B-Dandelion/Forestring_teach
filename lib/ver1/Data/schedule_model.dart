class ScheduleModel {
  final String id;
  final String name;
  DateTime date;
  final String teacher;
  final bool rebook;

  ScheduleModel({
    required this.id,
    required this.name,
    required this.date,
    required this.teacher,
    required this.rebook,
  });

  ScheduleModel copyWith({
    String? id,
    String? name,
    DateTime? date,
    String? teacher,
    bool? rebook,
  }) {
    return ScheduleModel(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      teacher: teacher ?? this.teacher,
      rebook: rebook ?? this.rebook,
    );
  }
}

