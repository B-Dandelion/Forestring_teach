import 'package:supabase_flutter/supabase_flutter.dart';

class ManagerFailure implements Exception {
  const ManagerFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManagerWorkHourInput {
  const ManagerWorkHourInput({
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

class CreatedManager {
  const CreatedManager({
    required this.id,
    required this.displayName,
    required this.branchId,
    required this.canTeach,
  });

  final String id;
  final String displayName;
  final String branchId;
  final bool canTeach;
}

class ManagerRepository {
  ManagerRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<CreatedManager> createManager({
    required String name,
    required String pin,
    required String branchId,
    required bool canTeach,
    required List<ManagerWorkHourInput> workHours,
  }) async {
    final normalizedName = name.trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );

    if (normalizedName.isEmpty) {
      throw const ManagerFailure(
        '지점장 이름을 입력해주세요.',
      );
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const ManagerFailure(
        'PIN은 4자리 숫자로 입력해주세요.',
      );
    }

    if (branchId.isEmpty) {
      throw const ManagerFailure(
        '지점을 선택해주세요.',
      );
    }

    if (!canTeach && workHours.isNotEmpty) {
      throw const ManagerFailure(
        '수업 기능이 꺼진 지점장에게는 수업 근무시간을 설정할 수 없습니다.',
      );
    }

    final session = _client.auth.currentSession;

    if (session == null) {
      throw const ManagerFailure(
        '로그인이 필요합니다.',
      );
    }

    try {
      final response = await _client.functions.invoke(
        'master-create-manager',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: {
          'name': normalizedName,
          'pin': pin,
          'branchId': branchId,
          'canTeach': canTeach,
          'workHours': workHours
              .map(
                (item) => item.toJson(),
              )
              .toList(),
        },
      );

      final data = response.data;

      if (data is! Map) {
        throw const ManagerFailure(
          '서버 응답 형식이 올바르지 않습니다.',
        );
      }

      final managerId = data['managerId'];

      if (managerId is! String || managerId.isEmpty) {
        final message = data['message'];

        throw ManagerFailure(
          message is String ? message : '지점장 생성에 실패했습니다.',
        );
      }

      return CreatedManager(
        id: managerId,
        displayName: data['displayName'] is String
            ? data['displayName']
            : normalizedName,
        branchId: data['branchId'] is String ? data['branchId'] : branchId,
        canTeach: data['canTeach'] == true,
      );
    } on ManagerFailure {
      rethrow;
    } catch (error) {
      throw ManagerFailure(
        '지점장 생성 요청에 실패했습니다.\n$error',
      );
    }
  }
}
