import 'package:supabase_flutter/supabase_flutter.dart';

import 'teacher_repository.dart';

class TeacherWorkHoursScheduleRepository {
  TeacherWorkHoursScheduleRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ManagedTeacherWorkHour>> fetchForDate({
    required String teacherId,
    required DateTime onDate,
  }) async {
    try {
      final data = await _client.rpc(
        'get_teacher_work_hours_for_date',
        params: {
          'p_teacher_id': teacherId,
          'p_on_date': _dateOnly(onDate),
        },
      );

      if (data is! Map) {
        throw const TeacherFailure(
          '근무시간 조회 결과를 확인하지 못했습니다.',
        );
      }

      final rawHours = data['hours'];
      if (rawHours is! List) {
        return const [];
      }

      final hours = rawHours
          .map(
            (raw) {
              final row = Map<String, dynamic>.from(raw as Map);
              return ManagedTeacherWorkHour(
                weekday: (row['weekday'] as num).toInt(),
                startTime: row['startTime'].toString(),
                endTime: row['endTime'].toString(),
              );
            },
          )
          .toList();

      hours.sort((a, b) {
        final weekday = a.weekday.compareTo(b.weekday);
        return weekday != 0
            ? weekday
            : a.startTime.compareTo(b.startTime);
      });

      return hours;
    } on TeacherFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw TeacherFailure(_failureMessage(error.message));
    } catch (error) {
      throw TeacherFailure('근무시간을 불러오지 못했습니다.\n$error');
    }
  }

  Future<bool> replace({
    required String teacherId,
    required DateTime effectiveOn,
    required List<TeacherWorkHourInput> workHours,
  }) async {
    try {
      final data = await _client.rpc(
        'replace_teacher_work_hours_effective',
        params: {
          'p_teacher_id': teacherId,
          'p_effective_on': _dateOnly(effectiveOn),
          'p_segments': workHours.map((item) => item.toJson()).toList(),
        },
      );

      if (data is! Map) {
        throw const TeacherFailure(
          '근무시간 저장 결과를 확인하지 못했습니다.',
        );
      }

      return data['changed'] == true;
    } on TeacherFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw TeacherFailure(_failureMessage(error.message));
    } catch (error) {
      throw TeacherFailure('근무시간을 변경하지 못했습니다.\n$error');
    }
  }
}

String _dateOnly(DateTime value) {
  final local = DateTime(value.year, value.month, value.day);
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _failureMessage(String message) {
  if (message.contains('FORESTRING_AUTH_REQUIRED')) {
    return '로그인이 필요합니다.';
  }
  if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED')) {
    return '현재 계정은 더 이상 사용할 수 없습니다.';
  }
  if (message.contains('FORESTRING_STAFF_REQUIRED')) {
    return '근무시간을 관리할 권한이 없습니다.';
  }
  if (message.contains('FORESTRING_TEACHER_NOT_FOUND')) {
    return '선생님 정보를 찾을 수 없습니다.';
  }
  if (message.contains('FORESTRING_TEACHER_BRANCH_REQUIRED')) {
    return '선생님의 지점 정보가 필요합니다.';
  }
  if (message.contains('FORESTRING_ACTIVE_TEACHER_REQUIRED')) {
    return '재직 중인 선생님의 근무시간만 변경할 수 있습니다.';
  }
  if (message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
    return '지점 관리자는 자기 지점 선생님의 근무시간만 변경할 수 있습니다.';
  }
  if (message.contains('FORESTRING_BACKDATED_WORK_HOURS_CHANGE_FORBIDDEN')) {
    return '지난 날짜부터 적용되는 근무시간은 변경할 수 없습니다.';
  }
  if (message.contains('FORESTRING_WORK_HOURS_OVERLAP')) {
    return '같은 요일에 서로 겹치는 근무시간이 있습니다.';
  }
  if (message.contains('FORESTRING_INVALID_WORK_HOURS_RANGE')) {
    return '종료시간은 시작시간보다 뒤여야 합니다.';
  }
  if (message.contains('FORESTRING_WORK_HOURS_NOT_ON_15_MINUTE_GRID')) {
    return '근무시간은 15분 단위로 입력해주세요.';
  }
  if (message.contains('FORESTRING_WORK_HOURS_EFFECTIVE_DATE_REQUIRED')) {
    return '근무시간 적용 시작일을 선택해주세요.';
  }
  if (message.contains('FORESTRING_WORK_HOURS_ARRAY_REQUIRED') ||
      message.contains('FORESTRING_INVALID_WORK_HOURS_FORMAT')) {
    return '근무시간 입력 형식이 올바르지 않습니다.';
  }

  return '근무시간을 처리하지 못했습니다.';
}
