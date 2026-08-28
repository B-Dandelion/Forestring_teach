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
      throw TeacherFailure(
        _failureMessage(
          error.message,
          fallback: '근무시간을 불러오지 못했습니다.',
        ),
      );
    } catch (_) {
      throw const TeacherFailure(
        '근무시간을 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
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
      throw TeacherFailure(
        _failureMessage(
          error.message,
          fallback: '근무시간을 변경하지 못했습니다.',
        ),
      );
    } catch (_) {
      throw const TeacherFailure(
        '근무시간을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
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

String _failureMessage(
  String message, {
  required String fallback,
}) {
  String? userMessage;

  if (message.contains('FORESTRING_AUTH_REQUIRED')) {
    userMessage = '로그인이 필요합니다.';
  } else if (message.contains('FORESTRING_ACTIVE_USER_REQUIRED') ||
      message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED')) {
    userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_REQUIRED')) {
    userMessage = '근무시간을 관리할 권한이 없습니다.';
  } else if (message.contains('FORESTRING_TEACHER_NOT_FOUND')) {
    userMessage = '선생님 정보를 찾을 수 없습니다.';
  } else if (message.contains('FORESTRING_TEACHER_BRANCH_REQUIRED')) {
    userMessage = '선생님의 지점 정보를 확인해주세요.';
  } else if (message.contains('FORESTRING_ACTIVE_TEACHER_REQUIRED')) {
    userMessage = '재직 중인 선생님의 근무시간만 변경할 수 있습니다.';
  } else if (message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
    userMessage = '다른 지점 선생님의 근무시간은 변경할 수 없습니다.';
  } else if (message.contains('FORESTRING_BACKDATED_WORK_HOURS_CHANGE_FORBIDDEN')) {
    userMessage = '지난 날짜부터 적용되는 근무시간은 변경할 수 없습니다.';
  } else if (message.contains('FORESTRING_WORK_HOURS_OVERLAP')) {
    userMessage = '같은 요일에 서로 겹치는 근무시간이 있습니다.';
  } else if (message.contains('FORESTRING_INVALID_WORK_HOURS_RANGE')) {
    userMessage = '종료시간은 시작시간보다 뒤여야 합니다.';
  } else if (message.contains('FORESTRING_WORK_HOURS_NOT_ON_15_MINUTE_GRID')) {
    userMessage = '근무시간은 15분 단위로 입력해주세요.';
  } else if (message.contains('FORESTRING_WORK_HOURS_EFFECTIVE_DATE_REQUIRED')) {
    userMessage = '근무시간 적용 시작일을 선택해주세요.';
  } else if (message.contains('FORESTRING_WORK_HOURS_ARRAY_REQUIRED') ||
      message.contains('FORESTRING_INVALID_WORK_HOURS_FORMAT')) {
    userMessage = '근무시간 입력 형식이 올바르지 않습니다.';
  }

  return _withErrorCode(userMessage ?? fallback, message);
}

String _withErrorCode(String userMessage, String rawMessage) {
  final match = RegExp(r'FORESTRING_[A-Z0-9_]+').firstMatch(rawMessage);
  final code = match?.group(0);
  if (code == null) return userMessage;
  return '$userMessage\n오류 코드: $code';
}
