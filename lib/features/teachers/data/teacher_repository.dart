import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherFailure implements Exception {
  const TeacherFailure(this.message);

  final String message;

  @override
  String toString() => message;
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

extension on String {
  String normalizeName() {
    return trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }
}
