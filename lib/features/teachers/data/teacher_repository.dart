import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherFailure implements Exception {
  const TeacherFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManagedTeacherWorkHour {
  const ManagedTeacherWorkHour({
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  final int weekday;
  final String startTime;
  final String endTime;
}

class ManagedTeacher {
  const ManagedTeacher({
    required this.id,
    required this.displayName,
    required this.branchId,
    required this.branchName,
    required this.profileIsActive,
    required this.workHours,
    required this.assignedStudentCount,
    this.withdrawalDate,
  });

  final String id;
  final String displayName;
  final String? branchId;
  final String branchName;
  final bool profileIsActive;
  final List<ManagedTeacherWorkHour> workHours;
  final int assignedStudentCount;
  final DateTime? withdrawalDate;

  bool get isActive => profileIsActive;
  bool get hasScheduledWithdrawal => isActive && withdrawalDate != null;

  String get statusLabel {
    if (!isActive) return '퇴사';
    if (hasScheduledWithdrawal) return '퇴사 예정';
    return '재직';
  }
}

class TeacherWorkHourInput {
  const TeacherWorkHourInput({
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  final int weekday;
  final String startTime;
  final String endTime;

  Map<String, dynamic> toJson() {
    return {
      'weekday': weekday,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

class CreatedTeacher {
  const CreatedTeacher({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;
}

class TeacherRepository {
  TeacherRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ManagedTeacher>> fetchTeachers({
    String? branchId,
  }) async {
    try {
      final profileRows = branchId == null
          ? await _client
              .from('profiles')
              .select('id, display_name, branch_id, is_active')
              .eq('role', 'teacher')
              .eq('is_review_account', false)
              .order('display_name')
          : await _client
              .from('profiles')
              .select('id, display_name, branch_id, is_active')
              .eq('role', 'teacher')
              .eq('is_review_account', false)
              .eq('branch_id', branchId)
              .order('display_name');

      final profiles = (profileRows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      if (profiles.isEmpty) {
        return const [];
      }

      final teacherIds = profiles.map((row) => row['id'] as String).toList();
      final branchIds = profiles
          .map((row) => row['branch_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final results = await Future.wait([
        _client
            .from('teachers')
            .select('id, withdrawal_date')
            .inFilter('id', teacherIds),
        _client
            .from('teacher_work_hours')
            .select('teacher_id, weekday, start_time, end_time')
            .inFilter('teacher_id', teacherIds),
        _client
            .from('teacher_student_assignments')
            .select('teacher_id, student_id, starts_on, ends_on')
            .inFilter('teacher_id', teacherIds),
        if (branchIds.isEmpty)
          Future.value(<dynamic>[])
        else
          _client
              .from('branches')
              .select('id, name')
              .inFilter('id', branchIds)
              .order('name'),
      ]);

      final teacherRows = (results[0] as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final workHourRows = (results[1] as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final assignmentRows = (results[2] as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final branchRows = (results[3] as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      final withdrawalByTeacher = <String, DateTime?>{
        for (final row in teacherRows)
          row['id'] as String: row['withdrawal_date'] == null
              ? null
              : DateTime.parse(row['withdrawal_date'].toString()),
      };
      final branchNames = <String, String>{
        for (final row in branchRows)
          row['id'] as String: row['name'].toString(),
      };
      final workHoursByTeacher = <String, List<ManagedTeacherWorkHour>>{};

      for (final row in workHourRows) {
        final teacherId = row['teacher_id'] as String;
        workHoursByTeacher.putIfAbsent(teacherId, () => []).add(
              ManagedTeacherWorkHour(
                weekday: (row['weekday'] as num).toInt(),
                startTime: _shortTime(row['start_time']),
                endTime: _shortTime(row['end_time']),
              ),
            );
      }

      for (final workHours in workHoursByTeacher.values) {
        workHours.sort((a, b) {
          final weekdayCompare = a.weekday.compareTo(b.weekday);
          return weekdayCompare != 0
              ? weekdayCompare
              : a.startTime.compareTo(b.startTime);
        });
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final activeStudentsByTeacher = <String, Set<String>>{};

      for (final row in assignmentRows) {
        final startsOn = DateTime.parse(row['starts_on'].toString());
        final endsOn = row['ends_on'] == null
            ? null
            : DateTime.parse(row['ends_on'].toString());
        final isCurrent = !startsOn.isAfter(today) &&
            (endsOn == null || !endsOn.isBefore(today));
        if (!isCurrent) continue;

        final teacherId = row['teacher_id'] as String;
        activeStudentsByTeacher
            .putIfAbsent(teacherId, () => <String>{})
            .add(row['student_id'] as String);
      }

      return profiles.map((profile) {
        final id = profile['id'] as String;
        final branchId = profile['branch_id'] as String?;

        return ManagedTeacher(
          id: id,
          displayName: profile['display_name'].toString(),
          branchId: branchId,
          branchName: branchId == null
              ? '지점 미지정'
              : (branchNames[branchId] ?? '지점 확인 필요'),
          profileIsActive: profile['is_active'] == true,
          workHours: List.unmodifiable(workHoursByTeacher[id] ?? const []),
          assignedStudentCount: activeStudentsByTeacher[id]?.length ?? 0,
          withdrawalDate: withdrawalByTeacher[id],
        );
      }).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
    } on PostgrestException catch (error) {
      throw TeacherFailure(
        '선생님 목록을 불러오지 못했습니다.\n${error.message}',
      );
    } catch (error) {
      throw TeacherFailure(
        '선생님 목록을 불러오지 못했습니다.\n$error',
      );
    }
  }

  Future<CreatedTeacher> createTeacher({
    required String name,
    required String pin,
    required String branchId,
    required List<TeacherWorkHourInput> workHours,
  }) async {
    final normalizedName = name.normalizeName();

    if (normalizedName.isEmpty) {
      throw const TeacherFailure(
        '선생님 이름을 입력해주세요.',
      );
    }

    if (branchId.isEmpty) {
      throw const TeacherFailure(
        '지점을 선택해주세요.',
      );
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const TeacherFailure(
        'PIN은 4자리 숫자로 입력해주세요.',
      );
    }

    final session = _client.auth.currentSession;

    if (session == null) {
      throw const TeacherFailure(
        '로그인이 필요합니다.',
      );
    }

    try {
      final response = await _client.functions.invoke(
        'master-create-teacher',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: {
          'name': normalizedName,
          'pin': pin,
          'branchId': branchId,
          'workHours': workHours.map((item) => item.toJson()).toList(),
        },
      );

      final data = response.data;

      if (data is! Map) {
        throw const TeacherFailure(
          '서버 응답 형식이 올바르지 않습니다.',
        );
      }

      final teacherId = data['teacherId'];
      final displayName = data['displayName'];

      if (teacherId is! String || teacherId.isEmpty) {
        final message = data['message'];

        throw TeacherFailure(
          message is String ? message : '선생님 생성에 실패했습니다.',
        );
      }

      return CreatedTeacher(
        id: teacherId,
        displayName: displayName is String ? displayName : normalizedName,
      );
    } on TeacherFailure {
      rethrow;
    } catch (error) {
      throw TeacherFailure(
        '선생님 생성 요청에 실패했습니다.\n$error',
      );
    }
  }
}

String _shortTime(dynamic value) {
  final raw = value.toString();
  return raw.length >= 5 ? raw.substring(0, 5) : raw;
}

extension on String {
  String normalizeName() {
    return trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }
}
