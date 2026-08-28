import 'package:supabase_flutter/supabase_flutter.dart';

class StudentNextSemesterTypeFailure implements Exception {
  const StudentNextSemesterTypeFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class NextSemesterStudentTypePlan {
  const NextSemesterStudentTypePlan({
    required this.studentId,
    required this.currentStudentType,
    required this.currentSemesterCode,
    required this.currentSemesterStartsOn,
    required this.currentSemesterEndsOn,
    required this.nextSemesterId,
    required this.nextSemesterCode,
    required this.nextSemesterStartsOn,
    required this.nextSemesterEndsOn,
    required this.plannedStudentType,
    required this.regularScheduleCount,
    required this.teacherAssignmentCoversSemester,
    required this.canChange,
    required this.defaultFlexBaseRightCount,
    required this.defaultFlexDurationMinutes,
    this.nextPlanId,
    this.nextPlanStatus,
    this.flexBaseRightCount,
    this.flexDurationMinutes,
    this.teacherId,
    this.teacherName,
    this.withdrawalDate,
  });

  final String studentId;
  final String currentStudentType;
  final String currentSemesterCode;
  final DateTime currentSemesterStartsOn;
  final DateTime currentSemesterEndsOn;
  final String nextSemesterId;
  final String nextSemesterCode;
  final DateTime nextSemesterStartsOn;
  final DateTime nextSemesterEndsOn;
  final String? nextPlanId;
  final String? nextPlanStatus;
  final String plannedStudentType;
  final int? flexBaseRightCount;
  final int? flexDurationMinutes;
  final int defaultFlexBaseRightCount;
  final int defaultFlexDurationMinutes;
  final int regularScheduleCount;
  final String? teacherId;
  final String? teacherName;
  final bool teacherAssignmentCoversSemester;
  final DateTime? withdrawalDate;
  final bool canChange;

  bool get currentIsRegular => currentStudentType == 'regular';
  bool get currentIsFlex => currentStudentType == 'flex';
  bool get plannedIsRegular => plannedStudentType == 'regular';
  bool get plannedIsFlex => plannedStudentType == 'flex';

  String get currentTypeLabel => currentIsFlex ? '자율 예약' : '정규';
  String get plannedTypeLabel => plannedIsFlex ? '자율 예약' : '정규';
}

class NextSemesterTeacherWorkWindow {
  const NextSemesterTeacherWorkWindow({
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
  });

  final int weekday;
  final int startMinutes;
  final int endMinutes;
}

class NextSemesterStudentTypeChangeResult {
  const NextSemesterStudentTypeChangeResult({
    required this.changed,
    required this.currentStudentType,
    required this.plannedStudentType,
    required this.nextSemesterCode,
    required this.nextSemesterStartsOn,
    required this.regularScheduleCount,
    this.flexBaseRightCount,
    this.flexDurationMinutes,
  });

  final bool changed;
  final String currentStudentType;
  final String plannedStudentType;
  final String nextSemesterCode;
  final DateTime nextSemesterStartsOn;
  final int regularScheduleCount;
  final int? flexBaseRightCount;
  final int? flexDurationMinutes;

  String get plannedTypeLabel =>
      plannedStudentType == 'flex' ? '자율 예약' : '정규';
}

class StudentNextSemesterTypeRepository {
  StudentNextSemesterTypeRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<NextSemesterStudentTypePlan> fetchPlan(String studentId) async {
    try {
      final result = await _client.rpc(
        'get_next_semester_student_type_plan',
        params: {'p_student_id': studentId},
      );

      if (result is! Map) {
        throw const StudentNextSemesterTypeFailure(
          '다음 학기 수강 형태 정보를 확인하지 못했습니다.',
        );
      }

      final row = Map<String, dynamic>.from(result);
      return NextSemesterStudentTypePlan(
        studentId: row['studentId'].toString(),
        currentStudentType: row['currentStudentType'].toString(),
        currentSemesterCode: row['currentSemesterCode'].toString(),
        currentSemesterStartsOn:
            DateTime.parse(row['currentSemesterStartsOn'].toString()),
        currentSemesterEndsOn:
            DateTime.parse(row['currentSemesterEndsOn'].toString()),
        nextSemesterId: row['nextSemesterId'].toString(),
        nextSemesterCode: row['nextSemesterCode'].toString(),
        nextSemesterStartsOn:
            DateTime.parse(row['nextSemesterStartsOn'].toString()),
        nextSemesterEndsOn:
            DateTime.parse(row['nextSemesterEndsOn'].toString()),
        nextPlanId: row['nextPlanId']?.toString(),
        nextPlanStatus: row['nextPlanStatus']?.toString(),
        plannedStudentType: row['plannedStudentType'].toString(),
        flexBaseRightCount:
            (row['flexBaseRightCount'] as num?)?.toInt(),
        flexDurationMinutes:
            (row['flexDurationMinutes'] as num?)?.toInt(),
        defaultFlexBaseRightCount:
            (row['defaultFlexBaseRightCount'] as num?)?.toInt() ?? 4,
        defaultFlexDurationMinutes:
            (row['defaultFlexDurationMinutes'] as num?)?.toInt() ?? 30,
        regularScheduleCount:
            (row['regularScheduleCount'] as num?)?.toInt() ?? 0,
        teacherId: row['teacherId']?.toString(),
        teacherName: row['teacherName']?.toString(),
        teacherAssignmentCoversSemester:
            row['teacherAssignmentCoversSemester'] == true,
        withdrawalDate: row['withdrawalDate'] == null
            ? null
            : DateTime.parse(row['withdrawalDate'].toString()),
        canChange: row['canChange'] == true,
      );
    } on StudentNextSemesterTypeFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentNextSemesterTypeFailure(
        _friendlyMessage(error.message),
      );
    } catch (_) {
      throw const StudentNextSemesterTypeFailure(
        '다음 학기 수강 형태 정보를 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<List<NextSemesterTeacherWorkWindow>> fetchTeacherWorkHours({
    required String teacherId,
    required DateTime onDate,
  }) async {
    try {
      final result = await _client.rpc(
        'get_teacher_work_hours_for_date',
        params: {
          'p_teacher_id': teacherId,
          'p_on_date': _dateOnly(onDate),
        },
      );

      if (result is! Map) {
        throw const StudentNextSemesterTypeFailure(
          '담당 선생님의 근무시간을 확인하지 못했습니다.',
        );
      }

      final row = Map<String, dynamic>.from(result);
      final rawHours = row['hours'];
      if (rawHours is! List) {
        return const [];
      }

      return rawHours.map((raw) {
        final hour = Map<String, dynamic>.from(raw as Map);
        return NextSemesterTeacherWorkWindow(
          weekday: (hour['weekday'] as num).toInt(),
          startMinutes: _parseMinutes(hour['startTime'].toString()),
          endMinutes: _parseMinutes(hour['endTime'].toString()),
        );
      }).toList();
    } on StudentNextSemesterTypeFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentNextSemesterTypeFailure(
        _friendlyMessage(error.message),
      );
    } catch (_) {
      throw const StudentNextSemesterTypeFailure(
        '담당 선생님의 근무시간을 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<NextSemesterStudentTypeChangeResult> save({
    required String studentId,
    required String targetType,
    int? flexBaseRightCount,
    int? flexDurationMinutes,
    List<Map<String, dynamic>>? regularSchedules,
  }) async {
    if (targetType != 'regular' && targetType != 'flex') {
      throw const StudentNextSemesterTypeFailure(
        '변경할 수강 형태를 선택해주세요.',
      );
    }

    if (targetType == 'flex') {
      if (flexBaseRightCount == null || flexBaseRightCount <= 0) {
        throw const StudentNextSemesterTypeFailure(
          '수업권 개수는 1개 이상이어야 합니다.',
        );
      }
      if (flexDurationMinutes == null ||
          flexDurationMinutes <= 0 ||
          flexDurationMinutes % 15 != 0) {
        throw const StudentNextSemesterTypeFailure(
          '수업 길이는 15분 단위로 설정해주세요.',
        );
      }
    }

    try {
      final result = await _client.rpc(
        'set_next_semester_student_type',
        params: {
          'p_student_id': studentId,
          'p_target_type': targetType,
          'p_flex_base_right_count':
              targetType == 'flex' ? flexBaseRightCount : null,
          'p_flex_duration_minutes':
              targetType == 'flex' ? flexDurationMinutes : null,
          'p_regular_schedules':
              targetType == 'regular' ? regularSchedules : null,
        },
      );

      if (result is! Map) {
        throw const StudentNextSemesterTypeFailure(
          '다음 학기 수강 형태 변경 결과를 확인하지 못했습니다.',
        );
      }

      final row = Map<String, dynamic>.from(result);
      return NextSemesterStudentTypeChangeResult(
        changed: row['changed'] == true,
        currentStudentType: row['currentStudentType'].toString(),
        plannedStudentType: row['plannedStudentType'].toString(),
        nextSemesterCode: row['nextSemesterCode'].toString(),
        nextSemesterStartsOn:
            DateTime.parse(row['nextSemesterStartsOn'].toString()),
        regularScheduleCount:
            (row['regularScheduleCount'] as num?)?.toInt() ?? 0,
        flexBaseRightCount:
            (row['flexBaseRightCount'] as num?)?.toInt(),
        flexDurationMinutes:
            (row['flexDurationMinutes'] as num?)?.toInt(),
      );
    } on StudentNextSemesterTypeFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentNextSemesterTypeFailure(
        _friendlyMessage(error.message),
      );
    } catch (_) {
      throw const StudentNextSemesterTypeFailure(
        '다음 학기 수강 형태를 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  String _friendlyMessage(String message) {
    if (message.contains('FORESTRING_AUTH_REQUIRED')) {
      return '로그인이 필요합니다.';
    }
    if (message.contains('FORESTRING_STAFF_REQUIRED') ||
        message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
      return '이 학생의 수강 형태를 변경할 권한이 없습니다.';
    }
    if (message.contains('FORESTRING_STUDENT_NOT_FOUND')) {
      return '학생 정보를 찾지 못했습니다.';
    }
    if (message.contains('FORESTRING_ACTIVE_STUDENT_REQUIRED')) {
      return '현재 재원 중인 학생만 변경할 수 있습니다.';
    }
    if (message.contains('FORESTRING_CURRENT_SEMESTER_NOT_FOUND') ||
        message.contains('FORESTRING_NEXT_SEMESTER_NOT_FOUND')) {
      return '현재 학기와 다음 학기 정보를 확인해주세요.';
    }
    if (message.contains('FORESTRING_NEXT_TYPE_CHANGE_AFTER_SEMESTER_START')) {
      return '다음 학기가 이미 시작되어 수강 형태를 변경할 수 없습니다.';
    }
    if (message.contains('FORESTRING_NEXT_TYPE_CHANGE_WITHDRAWAL_CONFLICT')) {
      return '다음 학기 중 퇴원 예정인 학생은 수강 형태를 변경할 수 없습니다. 퇴원 예약을 먼저 확인해주세요.';
    }
    if (message.contains('FORESTRING_INVALID_FLEX_RIGHT_COUNT')) {
      return '수업권 개수는 1개 이상이어야 합니다.';
    }
    if (message.contains('FORESTRING_INVALID_FLEX_DURATION')) {
      return '수업 길이는 15분 단위로 설정해주세요.';
    }
    if (message.contains('FORESTRING_NEXT_REGULAR_SCHEDULES_REQUIRED')) {
      return '다음 학기에 사용할 정규 수업 요일과 시간을 한 개 이상 설정해주세요.';
    }
    if (message.contains('FORESTRING_NEXT_REGULAR_TEACHER_ASSIGNMENT_REQUIRED')) {
      return '다음 학기 전체 기간의 담당 선생님을 먼저 지정해주세요.';
    }
    if (message.contains('FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL')) {
      return '담당 선생님의 퇴사 예정일과 다음 학기가 겹칩니다. 담당 선생님을 먼저 확인해주세요.';
    }
    if (message.contains('FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS')) {
      return '선택한 정규 수업 시간이 담당 선생님의 근무시간 밖입니다.';
    }
    if (message.contains('FORESTRING_REGULAR_OCCURRENCE_BLOCKED') ||
        message.contains('FORESTRING_REGULAR_RECONCILIATION_BLOCKED')) {
      return '선택한 정규 수업 시간이 담당 선생님의 예약 불가 시간과 겹칩니다.';
    }
    if (message.contains('FORESTRING_REGULAR_MATERIALIZATION_TIME_CONFLICT') ||
        message.contains('FORESTRING_REGULAR_SERIES_TIME_CONFLICT') ||
        message.contains('TIME_CONFLICT')) {
      return '선택한 시간에 이미 다른 수업이 있어 정규 일정을 만들 수 없습니다.';
    }
    if (message.contains('FORESTRING_REGULAR_SLOT_NOT_FOUR_OCCURRENCES') ||
        message.contains('FORESTRING_REGULAR_RECONCILIATION_COUNT_MISMATCH') ||
        message.contains('FORESTRING_SEMESTER_NOT_FOUR_TEACHING_WEEKS')) {
      return '다음 학기의 수업 횟수를 정상적으로 구성할 수 없습니다. 학기와 휴원일 설정을 확인해주세요.';
    }
    if (message.contains('FORESTRING_DUPLICATE_REGULAR_SCHEDULE')) {
      return '같은 요일·시간·수업 길이의 정규 일정이 중복되어 있습니다.';
    }
    if (message.contains('FORESTRING_NEXT_TYPE_CHANGE_CARRYOVER_UNSAFE') ||
        message.contains('FORESTRING_NEXT_TYPE_CHANGE_DERIVED_RIGHT_UNSAFE') ||
        message.contains('FORESTRING_NEXT_TYPE_CHANGE_MAKEUP_RIGHT_UNSAFE') ||
        message.contains('FORESTRING_NEXT_TYPE_CHANGE_LEGACY_CREDIT_UNSAFE')) {
      return '다음 학기 수업권이 이미 보강·이월 등 다른 수업에 사용되어 자동 전환할 수 없습니다. 관련 수업권을 먼저 확인해주세요.';
    }
    if (message.contains('FORESTRING_NEXT_TYPE_CHANGE_REGULAR_MATERIALIZATION_UNSAFE') ||
        message.contains('FORESTRING_NEXT_TYPE_CHANGE_FLEX_MATERIALIZATION_UNSAFE')) {
      return '다음 학기 이후 수업에 이미 개별 변경·취소 또는 사용 이력이 있어 자동 전환할 수 없습니다. 해당 일정을 먼저 확인해주세요.';
    }
    if (message.contains('FORESTRING_NEXT_TYPE_CHANGE_COMPLETED_PLAN_UNSAFE')) {
      return '이미 완료된 학기 정보가 포함되어 수강 형태를 변경할 수 없습니다.';
    }
    if (message.contains('FORESTRING_NEXT_TYPE_CHANGE_BRANCH_TRANSFER_UNSAFE')) {
      return '지점 변경 이력이 포함된 미래 학기는 자동 전환할 수 없습니다.';
    }
    if (message.contains('FORESTRING_COMPLETED_PLAN_IMMUTABLE')) {
      return '이미 완료된 학기 계획은 변경할 수 없습니다.';
    }
    if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED') ||
        message.contains('FORESTRING_ACTIVE_USER_REQUIRED')) {
      return '현재 계정은 이 작업을 수행할 수 없습니다.';
    }
    return '다음 학기 수강 형태를 변경하지 못했습니다. 학생의 다음 학기 일정과 수업권을 확인해주세요.';
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  int _parseMinutes(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 +
        (int.tryParse(parts[1]) ?? 0);
  }
}
