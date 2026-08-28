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
  }) : _client = client ?? Supabase.instance.client;

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

    final session = _client.auth.currentSession;

    if (session == null) {
      throw const StudentFailure(
        '로그인이 필요합니다.',
      );
    }

    try {
      final response = await _client.functions.invoke(
        'staff-create-student',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: {
          'name': normalizedName,
          'pin': pin,
          'branchId': branchId,
          'studentType': studentType.value,
        },
      );

      final data = response.data;

      if (data is! Map) {
        throw const StudentFailure(
          '학생 생성 서버 응답을 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
        );
      }

      final studentId = data['studentId'];

      if (studentId is! String || studentId.isEmpty) {
        final message = data['message'];

        throw StudentFailure(
          message is String ? message : '학생 계정을 생성하지 못했습니다.',
        );
      }

      final returnedType = data['studentType'];

      return CreatedStudent(
        id: studentId,
        displayName: data['displayName'] is String
            ? data['displayName'] as String
            : normalizedName,
        branchId: data['branchId'] is String
            ? data['branchId'] as String
            : branchId,
        studentType:
            returnedType == 'flex' ? StudentType.flex : StudentType.regular,
      );
    } on StudentFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw StudentFailure(details['message'].toString());
      }
      throw const StudentFailure(
        '학생 생성 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const StudentFailure(
        '학생 계정을 생성하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }
}
