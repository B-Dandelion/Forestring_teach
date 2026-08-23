import 'package:supabase_flutter/supabase_flutter.dart';

class StudentManagementFailure implements Exception {
  const StudentManagementFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManagedStudent {
  const ManagedStudent({
    required this.id,
    required this.displayName,
    required this.branchId,
    required this.branchName,
    required this.studentType,
    required this.status,
    required this.profileIsActive,
    this.teacherId,
    this.teacherName,
    this.withdrawalDate,
  });

  final String id;
  final String displayName;
  final String? branchId;
  final String branchName;
  final String studentType;
  final String status;
  final bool profileIsActive;
  final String? teacherId;
  final String? teacherName;
  final DateTime? withdrawalDate;

  bool get isRegular => studentType == 'regular';
  bool get isFlex => studentType == 'flex';
  bool get isActive => status == 'active' && profileIsActive;

  String get typeLabel => isFlex ? '자율 예약 학생' : '정규 학생';
  String get statusLabel => isActive ? '재원' : '퇴원';
}

class StudentManagementRepository {
  StudentManagementRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ManagedStudent>> fetchStudents({
    String? branchId,
  }) async {
    try {
      final profileRows = branchId == null
          ? await _client
              .from('profiles')
              .select('id, display_name, branch_id, is_active')
              .eq('role', 'student')
              .eq('is_review_account', false)
              .order('display_name')
          : await _client
              .from('profiles')
              .select('id, display_name, branch_id, is_active')
              .eq('role', 'student')
              .eq('is_review_account', false)
              .eq('branch_id', branchId)
              .order('display_name');

      final profiles = (profileRows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      if (profiles.isEmpty) {
        return const [];
      }

      final studentIds = profiles.map((row) => row['id'] as String).toList();
      final branchIds = profiles
          .map((row) => row['branch_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final results = await Future.wait([
        _client
            .from('students')
            .select('id, status, withdrawal_date, student_type')
            .inFilter('id', studentIds),
        _client
            .from('teacher_student_assignments')
            .select('student_id, teacher_id, branch_id, starts_on, ends_on')
            .inFilter('student_id', studentIds)
            .order('starts_on', ascending: false),
        if (branchIds.isEmpty)
          Future.value(<dynamic>[])
        else
          _client
              .from('branches')
              .select('id, name')
              .inFilter('id', branchIds)
              .order('name'),
      ]);

      final studentRows = (results[0] as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final assignmentRows = (results[1] as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final branchRows = (results[2] as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      final studentsById = <String, Map<String, dynamic>>{
        for (final row in studentRows) row['id'] as String: row,
      };
      final branchNames = <String, String>{
        for (final row in branchRows)
          row['id'] as String: row['name'].toString(),
      };

      final today = DateTime.now();
      final localToday = DateTime(today.year, today.month, today.day);
      final activeAssignmentByStudent = <String, Map<String, dynamic>>{};

      for (final row in assignmentRows) {
        final studentId = row['student_id'] as String;
        if (activeAssignmentByStudent.containsKey(studentId)) {
          continue;
        }

        final startsOn = DateTime.parse(row['starts_on'].toString());
        final endsOn = row['ends_on'] == null
            ? null
            : DateTime.parse(row['ends_on'].toString());

        final hasStarted = !startsOn.isAfter(localToday);
        final hasNotEnded = endsOn == null || !endsOn.isBefore(localToday);
        if (hasStarted && hasNotEnded) {
          activeAssignmentByStudent[studentId] = row;
        }
      }

      final teacherIds = activeAssignmentByStudent.values
          .map((row) => row['teacher_id'] as String)
          .toSet()
          .toList();

      final teacherNames = <String, String>{};
      if (teacherIds.isNotEmpty) {
        final teacherRows = await _client
            .from('profiles')
            .select('id, display_name')
            .inFilter('id', teacherIds)
            .eq('is_review_account', false)
            .order('display_name');

        for (final raw in teacherRows as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          teacherNames[row['id'] as String] = row['display_name'].toString();
        }
      }

      return profiles.map((profile) {
        final id = profile['id'] as String;
        final student = studentsById[id];
        final assignment = activeAssignmentByStudent[id];
        final teacherId = assignment?['teacher_id'] as String?;
        final branchId = profile['branch_id'] as String?;
        final withdrawalRaw = student?['withdrawal_date'];

        return ManagedStudent(
          id: id,
          displayName: profile['display_name'].toString(),
          branchId: branchId,
          branchName: branchId == null
              ? '지점 미지정'
              : (branchNames[branchId] ?? '지점 확인 필요'),
          studentType: student?['student_type']?.toString() ?? 'regular',
          status: student?['status']?.toString() ?? 'active',
          profileIsActive: profile['is_active'] == true,
          teacherId: teacherId,
          teacherName: teacherId == null ? null : teacherNames[teacherId],
          withdrawalDate: withdrawalRaw == null
              ? null
              : DateTime.parse(withdrawalRaw.toString()),
        );
      }).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
    } on PostgrestException catch (error) {
      throw StudentManagementFailure(
        '수강생 목록을 불러오지 못했습니다.\n${error.message}',
      );
    } catch (error) {
      throw StudentManagementFailure(
        '수강생 목록을 불러오지 못했습니다.\n$error',
      );
    }
  }
}
