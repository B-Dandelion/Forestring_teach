class ScheduleModel {
  final String id;
  final int startTime;

  ScheduleModel({
    required this.id,
    required this.startTime,
  });

  ScheduleModel.fromJson({
    required Map<String, dynamic> json,
  }) : id = json['id'],
        startTime = json['startTime'];

  Map<String, dynamic> toJson(){
    return {
      'id' : id,
      'startTime' : startTime,
    };
  }

  ScheduleModel copyWith({
    String? id,
    int? startTime,
  }) {
    return ScheduleModel(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
    );
  }
}

