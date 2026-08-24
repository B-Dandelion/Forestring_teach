import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/managed_semester.dart';

class SemesterFailure implements Exception {
  const SemesterFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class SemesterRepository {
  SemesterRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ManagedSemester>> fetchSemesters() async {
    try {
      final results = await Future.wait([
        _client
            .from('semesters')
            .select('id, code, starts_on, ends_on')
            .order('starts_on'),
        _client
            .from('branch_semester_overrides')
            .select('branch_id, semester_id, starts_on, ends_on')
            .order('starts_on'),
      ]);

      final overrideRows = (results[1] as List)
          .map(
            (raw) => SemesterBranchOverride.fromJson(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList();

      final overridesBySemester = <String, List<SemesterBranchOverride>>{};
      for (final override in overrideRows) {
        overridesBySemester
            .putIfAbsent(override.semesterId, () => [])
            .add(override);
      }

      return (results[0] as List)
          .map(
            (raw) {
              final row = Map<String, dynamic>.from(raw as Map);
              final id = row['id'] as String;
              return ManagedSemester.fromJson(
                row,
                branchOverrides: overridesBySemester[id] ?? const [],
              );
            },
          )
          .toList();
    } on PostgrestException catch (error) {
      throw SemesterFailure(
        '학기 정보를 불러오지 못했습니다.\n${error.message}',
      );
    } catch (error) {
      throw SemesterFailure('학기 정보를 불러오지 못했습니다.\n$error');
    }
  }

  Future<void> createSemester({
    required String code,
    required DateTime startsOn,
    required DateTime endsOn,
  }) async {
    try {
      await _client.rpc(
        'upsert_semester',
        params: {
          'p_semester_id': null,
          'p_code': code.trim(),
          'p_starts_on': _dateText(startsOn),
          'p_ends_on': _dateText(endsOn),
        },
      );
    } on PostgrestException catch (error) {
      throw SemesterFailure(_message(error.message));
    }
  }

  Future<void> updateSemesterCode({
    required ManagedSemester semester,
    required String code,
  }) async {
    try {
      await _client.rpc(
        'upsert_semester',
        params: {
          'p_semester_id': semester.id,
          'p_code': code.trim(),
          'p_starts_on': _dateText(semester.startsOn),
          'p_ends_on': _dateText(semester.endsOn),
        },
      );
    } on PostgrestException catch (error) {
      throw SemesterFailure(_message(error.message));
    }
  }

  Future<void> applySemesterCalendarChanges(
    List<SemesterCalendarChange> changes,
  ) async {
    if (changes.isEmpty) return;

    try {
      await _client.rpc(
        'apply_semester_calendar_batch',
        params: {
          'p_changes': changes.map((change) => change.toJson()).toList(),
        },
      );
    } on PostgrestException catch (error) {
      throw SemesterFailure(_message(error.message));
    }
  }

  Future<void> applyBranchSemesterChanges({
    required String branchId,
    required List<BranchSemesterChange> changes,
  }) async {
    if (changes.isEmpty) return;

    try {
      await _client.rpc(
        'apply_branch_semester_overrides_batch',
        params: {
          'p_branch_id': branchId,
          'p_changes': changes.map((change) => change.toJson()).toList(),
        },
      );
    } on PostgrestException catch (error) {
      throw SemesterFailure(_message(error.message));
    }
  }

  Future<void> deleteSemester(String semesterId) async {
    try {
      await _client.rpc(
        'delete_semester',
        params: {'p_semester_id': semesterId},
      );
    } on PostgrestException catch (error) {
      throw SemesterFailure(_message(error.message));
    }
  }

  String _message(String message) {
    if (message.contains('FORESTRING_MASTER_REQUIRED') ||
        message.contains('FORESTRING_CALENDAR_MASTER_REQUIRED')) {
      return '전체 관리자만 기본 학기 일정을 변경할 수 있습니다.';
    }
    if (message.contains('FORESTRING_SEMESTER_CODE_REQUIRED')) {
      return '학기 이름을 입력해주세요.';
    }
    if (message.contains('FORESTRING_SEMESTER_CODE_ALREADY_EXISTS')) {
      return '이미 사용 중인 학기 이름입니다.';
    }
    if (message.contains('FORESTRING_INVALID_SEMESTER_RANGE')) {
      return '학기 시작일과 종료일을 확인해주세요.';
    }
    if (message.contains('FORESTRING_INVALID_SEMESTER_WEEK_STRUCTURE') ||
        message.contains('FORESTRING_INVALID_SEMESTER_OVERRIDE_WEEK_STRUCTURE')) {
      return '학기 기간은 4주 이상이며 7일 단위여야 합니다.';
    }
    if (message.contains('FORESTRING_SEMESTER_OVERLAP')) {
      return '다른 학기와 기간이 겹칩니다.';
    }
    if (message.contains('FORESTRING_SEMESTER_CALENDAR_NOT_CONTIGUOUS') ||
        message.contains('FORESTRING_BRANCH_SEMESTER_CALENDAR_NOT_CONTIGUOUS')) {
      return '학기 사이에 빈 날짜나 겹치는 날짜가 생기지 않도록 기간을 조정해주세요.';
    }
    if (message.contains('FORESTRING_MATERIALIZED_SEMESTER_DATES_IMMUTABLE')) {
      return '이미 수업이 생성된 학기의 기간은 변경할 수 없습니다.';
    }
    if (message.contains('FORESTRING_MATERIALIZED_BRANCH_SEMESTER_IMMUTABLE')) {
      return '이미 수업이 생성된 지점 학기의 기간은 변경할 수 없습니다.';
    }
    if (message.contains('FORESTRING_EXISTING_CLOSURE_OUTSIDE_EFFECTIVE_SEMESTER')) {
      return '기존 휴원 기간이 새 학기 범위를 벗어납니다. 휴원 기간을 먼저 조정해주세요.';
    }
    if (message.contains('FORESTRING_REDUNDANT_SEMESTER_OVERRIDE')) {
      return '기본 학기와 동일한 기간은 지점별 설정으로 저장할 필요가 없습니다.';
    }
    if (message.contains('FORESTRING_SEMESTER_HAS_DEPENDENCIES')) {
      return '수업, 휴원 또는 학생 학기 데이터가 연결된 학기는 삭제할 수 없습니다.';
    }
    if (message.contains('FORESTRING_SEMESTER_NOT_FOUND')) {
      return '학기 정보를 찾을 수 없습니다.';
    }
    if (message.contains('FORESTRING_BRANCH_NOT_FOUND')) {
      return '지점 정보를 찾을 수 없습니다.';
    }
    if (message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
      return '이 지점의 학기 일정을 변경할 권한이 없습니다.';
    }
    if (message.contains('FORESTRING_')) {
      return '학기 설정을 저장하지 못했습니다. ($message)';
    }
    return '학기 설정을 저장하지 못했습니다.';
  }
}

String _dateText(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
