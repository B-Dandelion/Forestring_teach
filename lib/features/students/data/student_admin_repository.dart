import 'package:supabase_flutter/supabase_flutter.dart';

class StudentAdminFailure implements Exception {
  const StudentAdminFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class StudentAdminTeacher {
  const StudentAdminTeacher({
    required this.id,
    required this.displayName,
    required this.branchId,
  });

  final String id;
  final String displayName;
  final String branchId;
}

class StudentSemesterOption {
  const StudentSemesterOption({
    required this.id,
    required this.code,
    required this.startsOn,
    required this.endsOn,
  });

  final String id;
  final String code;
  final DateTime startsOn;
  final DateTime endsOn;

  String get label {
    final parts = code.split('-');
    if (parts.length == 2) {
      final month = int.tryParse(parts[1]);
      if (month != null) {
        return '${parts[0]}년 $month월 학기';
      }
    }
    return '$code 학기';
  }
}

class StudentAdminRepository {
  StudentAdminRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<StudentAdminTeacher>> fetchTeachers(String branchId) async {
    try {
      final rows = await _client
          .from('profiles')
          .select('id, display_name, branch_id, role, is_active')
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .inFilter('role', ['teacher', 'manager'])
          .order('display_name');

      return (rows as List)
          .where((raw) => (raw as Map)['branch_id'] != null)
          .map(
            (raw) {
              final row = Map<String, dynamic>.from(raw as Map);
              return StudentAdminTeacher(
                id: row['id'] as String,
                displayName: row['display_name'] as String,
                branchId: row['branch_id'] as String,
              );
            },
          )
          .toList();
    } on PostgrestException catch (error) {
      throw StudentAdminFailure('선생님 목록을 불러오지 못했습니다.\n${error.message}');
    }
  }

  Future<List<StudentSemesterOption>> fetchSemesters(String branchId) async {
    try {
      final semesterRows = await _client
          .from('semesters')
          .select('id, code, starts_on, ends_on')
          .order('starts_on');

      List<dynamic> overrideRows = const [];
      try {
        overrideRows = await _client
            .from('branch_semester_overrides')
            .select('semester_id, starts_on, ends_on')
            .eq('branch_id', branchId);
      } on PostgrestException {
        overrideRows = const [];
      }

      final overrides = <String, Map<String, dynamic>>{
        for (final raw in overrideRows)
          (raw as Map)['semester_id'] as String: Map<String, dynamic>.from(raw),
      };

      final today = DateTime.now();
      final localToday = DateTime(today.year, today.month, today.day);
      final result = <StudentSemesterOption>[];

      for (final raw in semesterRows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id'] as String;
        final override = overrides[id];
        final startsOn = DateTime.parse(
          (override?['starts_on'] ?? row['starts_on']).toString(),
        );
        final endsOn = DateTime.parse(
          (override?['ends_on'] ?? row['ends_on']).toString(),
        );

        if (endsOn.isBefore(localToday)) {
          continue;
        }

        result.add(
          StudentSemesterOption(
            id: id,
            code: row['code'].toString(),
            startsOn: startsOn,
            endsOn: endsOn,
          ),
        );
      }

      return result;
    } on PostgrestException catch (error) {
      throw StudentAdminFailure('학기 목록을 불러오지 못했습니다.\n${error.message}');
    }
  }

  Future<String> createRegularStudentAccount({
    required String name,
    required String pin,
    required String branchId,
  }) async {
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedName.isEmpty) {
      throw const StudentAdminFailure('학생 이름을 입력해주세요.');
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const StudentAdminFailure('비밀번호는 4자리 숫자로 입력해주세요.');
    }

    try {
      final response = await _client.functions.invoke(
        'staff-create-student',
        body: {
          'name': normalizedName,
          'pin': pin,
          'branchId': branchId,
          'studentType': 'regular',
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map) {
        throw StudentAdminFailure(
          data is Map && data['message'] != null
              ? data['message'].toString()
              : '학생 계정을 생성하지 못했습니다.',
        );
      }

      final studentId = data['studentId']?.toString();
      if (studentId == null || studentId.isEmpty) {
        throw const StudentAdminFailure('생성된 학생 계정을 확인하지 못했습니다.');
      }
      return studentId;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw StudentAdminFailure(details['message'].toString());
      }
      throw const StudentAdminFailure('학생 계정을 생성하지 못했습니다.');
    }
  }

  Future<Map<String, dynamic>> initializeRegularSemester({
    required String studentId,
    required String teacherId,
    required String semesterId,
    required List<Map<String, dynamic>> schedules,
  }) async {
    try {
      final result = await _client.rpc(
        'initialize_regular_student_semester',
        params: {
          'p_student_id': studentId,
          'p_teacher_id': teacherId,
          'p_semester_id': semesterId,
          'p_schedules': schedules,
        },
      );

      if (result is! Map) {
        throw const StudentAdminFailure('정규 일정 생성 결과를 확인하지 못했습니다.');
      }
      return Map<String, dynamic>.from(result);
    } on PostgrestException catch (error) {
      throw StudentAdminFailure(_friendlyDatabaseMessage(error.message));
    }
  }

  String _friendlyDatabaseMessage(String message) {
    if (message.contains('FORESTRING_REGULAR_INITIAL_SETUP_ALREADY_EXISTS')) {
      return '이미 이 학기의 정규 일정이 설정되어 있습니다.';
    }
    if (message.contains('FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS')) {
      return '선택한 정규 시간이 선생님 근무시간 밖입니다.';
    }
    if (message.contains('FORESTRING_REGULAR_INITIAL_SETUP_CONFLICT') ||
        message.contains('TIME_CONFLICT')) {
      return '겹치는 정규 일정 또는 수업이 있습니다.';
    }
    if (message.contains('FORESTRING_SEMESTER_NOT_FOUR_TEACHING_WEEKS')) {
      return '선택한 학기의 수업 주차 설정을 확인해주세요.';
    }
    if (message.contains('FORESTRING_MANAGER_BRANCH')) {
      return '본인 지점의 학생만 등록할 수 있습니다.';
    }
    if (message.contains('FORESTRING_')) {
      return '정규 학생 설정을 완료하지 못했습니다. ($message)';
    }
    return '정규 학생 설정을 완료하지 못했습니다.';
  }
}
