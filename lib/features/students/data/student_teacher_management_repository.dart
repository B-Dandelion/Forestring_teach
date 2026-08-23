import 'package:supabase_flutter/supabase_flutter.dart';

class StudentTeacherManagementFailure implements Exception {
  const StudentTeacherManagementFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManagedTeacherOption {
  const ManagedTeacherOption({
    required this.id,
    required this.displayName,
    required this.branchId,
  });

  final String id;
  final String displayName;
  final String branchId;
}

class StudentTeacherManagementRepository {
  StudentTeacherManagementRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ManagedTeacherOption>> fetchBranchTeachers(String branchId) async {
    try {
      final rows = await _client
          .from('profiles')
          .select('id, display_name, branch_id, role, is_active')
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .eq('is_review_account', false)
          .inFilter('role', ['teacher', 'manager'])
          .order('display_name');

      return rows
          .map(
            (raw) => ManagedTeacherOption(
              id: raw['id'] as String,
              displayName: raw['display_name'].toString(),
              branchId: raw['branch_id'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw StudentTeacherManagementFailure(
        '선생님 목록을 불러오지 못했습니다.\n${error.message}',
      );
    } catch (error) {
      throw StudentTeacherManagementFailure(
        '선생님 목록을 불러오지 못했습니다.\n$error',
      );
    }
  }

  Future<Map<String, dynamic>> changeStudentTeacher({
    required String studentId,
    required String teacherId,
    required DateTime effectiveOn,
    required String? currentTeacherId,
    required bool isFlex,
  }) async {
    final date = _dateOnly(effectiveOn);

    try {
      if (currentTeacherId == null) {
        if (!isFlex) {
          throw const StudentTeacherManagementFailure(
            '정규 학생의 기존 담당 선생님 배정이 없습니다.\n'
            '먼저 학생의 정규 일정 상태를 확인해주세요.',
          );
        }

        final result = await _client.rpc(
          'assign_student_teacher',
          params: {
            'p_student_id': studentId,
            'p_teacher_id': teacherId,
            'p_starts_on': date,
          },
        );

        return {
          'changed': true,
          'assignmentId': result,
          'teacherId': teacherId,
          'effectiveOn': date,
        };
      }

      final result = await _client.rpc(
        'change_student_teacher',
        params: {
          'p_student_id': studentId,
          'p_teacher_id': teacherId,
          'p_effective_on': date,
        },
      );

      if (result is! Map) {
        throw const StudentTeacherManagementFailure(
          '담당 선생님 변경 결과를 확인하지 못했습니다.',
        );
      }

      return Map<String, dynamic>.from(result);
    } on StudentTeacherManagementFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentTeacherManagementFailure(
        _friendlyDatabaseMessage(error.message),
      );
    } catch (error) {
      throw StudentTeacherManagementFailure(
        '담당 선생님을 변경하지 못했습니다.\n$error',
      );
    }
  }

  String _dateOnly(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _friendlyDatabaseMessage(String message) {
    if (message.contains('FORESTRING_BACKDATED_TEACHER_CHANGE_FORBIDDEN')) {
      return '과거 날짜로 담당 선생님을 변경할 수 없습니다.';
    }
    if (message.contains('FORESTRING_BRANCH_MISMATCH') ||
        message.contains('FORESTRING_MANAGER_BRANCH')) {
      return '같은 지점의 선생님만 담당 선생님으로 지정할 수 있습니다.';
    }
    if (message.contains('FORESTRING_FUTURE_TEACHER_ASSIGNMENT_EXISTS')) {
      return '이미 예정된 담당 선생님 변경이 있습니다. 기존 변경 일정을 먼저 확인해주세요.';
    }
    if (message.contains('FORESTRING_CURRENT_TEACHER_ASSIGNMENT_NOT_FOUND')) {
      return '현재 담당 선생님 배정을 찾지 못했습니다.';
    }
    if (message.contains('FORESTRING_ASSIGNMENT_PERIOD_OVERLAP')) {
      return '담당 선생님 배정 기간이 기존 배정과 겹칩니다.';
    }
    if (message.contains('FORESTRING_TEACHER_INACTIVE') ||
        message.contains('FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL')) {
      return '선택한 선생님은 해당 날짜에 담당 선생님으로 지정할 수 없습니다.';
    }
    if (message.contains('FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS')) {
      return '기존 정규 수업 시간이 새 선생님의 근무시간 밖입니다.';
    }
    if (message.contains('TIME_CONFLICT') ||
        message.contains('FORESTRING_REGULAR_INITIAL_SETUP_CONFLICT')) {
      return '새 선생님의 기존 수업과 시간이 겹칩니다.';
    }
    if (message.contains('FORESTRING_TEACHER_CHANGE_FORBIDDEN')) {
      return '담당 선생님 변경 권한이 없습니다.';
    }
    if (message.contains('FORESTRING_')) {
      return '담당 선생님을 변경하지 못했습니다. ($message)';
    }
    return '담당 선생님을 변경하지 못했습니다.';
  }
}
