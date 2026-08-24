enum LessonType {
  regular,
  flex,
  makeup;

  static LessonType fromValue(String value) {
    return switch (value) {
      'flex' => LessonType.flex,
      'makeup' => LessonType.makeup,
      _ => LessonType.regular,
    };
  }

  String get label {
    return switch (this) {
      LessonType.regular => '정규 수업',
      LessonType.flex => '자율 예약 수업',
      LessonType.makeup => '보강 수업',
    };
  }
}

enum LessonStatus {
  scheduled,
  canceled;

  static LessonStatus fromValue(String value) {
    return value == 'canceled'
        ? LessonStatus.canceled
        : LessonStatus.scheduled;
  }
}

class Lesson {
  const Lesson({
    required this.id,
    required this.studentId,
    required this.teacherId,
    required this.startsAt,
    required this.endsAt,
    required this.durationMinutes,
    required this.type,
    required this.status,
    this.occurrenceAt,
    this.rescheduledBy,
    this.lessonRightId,
    this.branchId,
    this.studentName,
    this.teacherName,
    this.canceledAt,
    this.cancellationReason,
  });

  final String id;
  final String studentId;
  final String teacherId;
  final DateTime startsAt;
  final DateTime endsAt;
  final int durationMinutes;
  final LessonType type;
  final LessonStatus status;
  final DateTime? occurrenceAt;
  final String? rescheduledBy;
  final String? lessonRightId;
  final String? branchId;
  final String? studentName;
  final String? teacherName;
  final DateTime? canceledAt;
  final String? cancellationReason;

  bool get isCanceled => status == LessonStatus.canceled;

  bool get isStudentRebooked =>
      rescheduledBy != null && rescheduledBy == studentId;

  bool get isStaffChanged =>
      rescheduledBy != null && rescheduledBy != studentId;

  bool get isRescheduled => isStudentRebooked || isStaffChanged;

  String get displayTypeLabel {
    if (isStudentRebooked) {
      return '재예약 수업';
    }
    if (isStaffChanged) {
      return '변경 수업';
    }
    return type.label;
  }

  String? get changeBadgeLabel {
    if (isStudentRebooked) {
      return '재예약';
    }
    if (isStaffChanged) {
      return '변경';
    }
    return null;
  }

  Lesson copyWithNames({
    String? studentName,
    String? teacherName,
  }) {
    return Lesson(
      id: id,
      studentId: studentId,
      teacherId: teacherId,
      startsAt: startsAt,
      endsAt: endsAt,
      durationMinutes: durationMinutes,
      type: type,
      status: status,
      occurrenceAt: occurrenceAt,
      rescheduledBy: rescheduledBy,
      lessonRightId: lessonRightId,
      branchId: branchId,
      studentName: studentName ?? this.studentName,
      teacherName: teacherName ?? this.teacherName,
      canceledAt: canceledAt,
      cancellationReason: cancellationReason,
    );
  }

  factory Lesson.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      return DateTime.parse(value.toString()).toLocal();
    }

    DateTime? parseNullableDate(dynamic value) {
      if (value == null) {
        return null;
      }
      return parseDate(value);
    }

    return Lesson(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      teacherId: json['teacher_id'] as String,
      startsAt: parseDate(json['starts_at']),
      endsAt: parseDate(json['ends_at']),
      durationMinutes: json['duration_minutes'] as int,
      type: LessonType.fromValue(
        json['lesson_type'] as String,
      ),
      status: LessonStatus.fromValue(
        json['status'] as String,
      ),
      occurrenceAt: parseNullableDate(
        json['occurrence_at'],
      ),
      rescheduledBy: json['rescheduled_by'] as String?,
      lessonRightId: json['lesson_right_id'] as String?,
      branchId: json['branch_id'] as String?,
      canceledAt: parseNullableDate(json['canceled_at']),
      cancellationReason: json['cancellation_reason'] as String?,
    );
  }
}

class TeacherBlockedPeriod {
  const TeacherBlockedPeriod({
    required this.id,
    required this.teacherId,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    this.reason,
    this.teacherName,
  });

  final String id;
  final String teacherId;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime createdAt;
  final String? reason;
  final String? teacherName;

  int get durationMinutes => endsAt.difference(startsAt).inMinutes;

  String get displayLabel {
    final memo = reason?.trim();
    return memo == null || memo.isEmpty ? '개인 일정' : memo;
  }

  TeacherBlockedPeriod copyWithTeacherName(String? value) {
    return TeacherBlockedPeriod(
      id: id,
      teacherId: teacherId,
      startsAt: startsAt,
      endsAt: endsAt,
      createdAt: createdAt,
      reason: reason,
      teacherName: value ?? teacherName,
    );
  }

  factory TeacherBlockedPeriod.fromJson(Map<String, dynamic> json) {
    return TeacherBlockedPeriod(
      id: json['id'] as String,
      teacherId: json['teacher_id'] as String,
      startsAt: DateTime.parse(json['starts_at'].toString()).toLocal(),
      endsAt: DateTime.parse(json['ends_at'].toString()).toLocal(),
      createdAt: DateTime.parse(json['created_at'].toString()).toLocal(),
      reason: json['reason'] as String?,
    );
  }
}

class TeacherWorkHour {
  const TeacherWorkHour({
    required this.teacherId,
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  final String teacherId;
  final int weekday;
  final String startTime;
  final String endTime;

  factory TeacherWorkHour.fromJson(Map<String, dynamic> json) {
    return TeacherWorkHour(
      teacherId: json['teacher_id'] as String,
      weekday: json['weekday'] as int,
      startTime: json['start_time'].toString(),
      endTime: json['end_time'].toString(),
    );
  }
}

class VisibleTeacher {
  const VisibleTeacher({
    required this.id,
    required this.displayName,
    this.branchId,
  });

  final String id;
  final String displayName;
  final String? branchId;
}

class LessonMutationResult {
  const LessonMutationResult({
    required this.changed,
    required this.requiresConfirmation,
    this.warningCodes = const [],
  });

  final bool changed;
  final bool requiresConfirmation;
  final List<String> warningCodes;

  factory LessonMutationResult.fromJson(Map<String, dynamic> json) {
    final rawWarnings = json['warningCodes'];

    return LessonMutationResult(
      changed: json['changed'] == true,
      requiresConfirmation:
          json['requiresConfirmation'] == true,
      warningCodes: rawWarnings is List
          ? rawWarnings.map((e) => e.toString()).toList()
          : const [],
    );
  }
}
