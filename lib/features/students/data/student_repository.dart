import 'package:supabase_flutter/supabase_flutter.dart';

class StudentFailure implements Exception {
  const StudentFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

enum StudentType {
  regular,
  flex,
}

extension StudentTypeX on StudentType {
  String get value {
    return switch (this) {
      StudentType.regular => 'regular',
      StudentType.flex => 'flex',
    };
  }

  String get label {
    return switch (this) {
      StudentType.regular => '정규 학생',
      StudentType.flex => '자율 예약 학생',
    };
  }
}

class CreatedStudent {
  const CreatedStudent({
    required this.id,
    required this.displayName,
    required this.branchId,
    required this.studentType,
  });

  final String id;
  final String displayName;
  final String branchId;
  final StudentType studentType;
}

class StudentRepository {
  StudentRepository({
    SupabaseClient? client,
  }) : _client =
            client ??
            Supabase.instance.client;

  final SupabaseClient _client;

  Future<CreatedStudent> createStudent({
    required String name,
    required String pin,
    required String branchId,
    required StudentType studentType,
  }) async {
    final normalizedName = name
        .trim()
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        );

    if (normalizedName.isEmpty) {
      throw const StudentFailure(
        '학생 이름을 입력해주세요.',
      );
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const StudentFailure(
        'PIN은 4자리 숫자로 입력해주세요.',
      );
    }

    if (branchId.isEmpty) {
      throw const StudentFailure(
        '지점을 선택해주세요.',
      );
    }

    final session =
        _client.auth.currentSession;

    if (session == null) {
      throw const StudentFailure(
        '로그인이 필요합니다.',
      );
    }

    try {
      final response =
          await _client.functions.invoke(
        'staff-create-student',
        headers: {
          'Authorization':
              'Bearer ${session.accessToken}',
        },
        body: {
          'name': normalizedName,
          'pin': pin,
          'branchId': branchId,
          'studentType':
              studentType.value,
        },
      );

      final data = response.data;

      if (data is! Map) {
        throw const StudentFailure(
          '서버 응답 형식이 올바르지 않습니다.',
        );
      }

      final studentId =
          data['studentId'];

      if (studentId is! String ||
          studentId.isEmpty) {
        final message =
            data['message'];

        throw StudentFailure(
          message is String
              ? message
              : '학생 생성에 실패했습니다.',
        );
      }

      final returnedType =
          data['studentType'];

      return CreatedStudent(
        id: studentId,
        displayName:
            data['displayName'] is String
                ? data['displayName']
                : normalizedName,
        branchId:
            data['branchId'] is String
                ? data['branchId']
                : branchId,
        studentType:
            returnedType == 'flex'
                ? StudentType.flex
                : StudentType.regular,
      );
    } on StudentFailure {
      rethrow;
    } catch (error) {
      throw StudentFailure(
        '학생 생성 요청에 실패했습니다.\n$error',
      );
    }
  }
}
