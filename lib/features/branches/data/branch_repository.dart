import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/academy_branch.dart';

class BranchFailure implements Exception {
  const BranchFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class BranchRepository {
  BranchRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<AcademyBranch>> fetchBranches() async {
    try {
      final rows = await _client
          .from('branches')
          .select(
            'id, name, is_active',
          )
          .order(
            'name',
            ascending: true,
          );

      return rows
          .map(
            (row) => AcademyBranch.fromJson(
              row,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw BranchFailure(
        '지점 목록을 불러오지 못했습니다.\n'
        '${error.message}',
      );
    }
  }

  Future<String> createBranch({
    required String name,
  }) async {
    final normalizedName = name.trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );

    if (normalizedName.isEmpty) {
      throw const BranchFailure(
        '지점명을 입력해주세요.',
      );
    }

    try {
      final result = await _client.rpc(
        'create_branch',
        params: {
          'p_name': normalizedName,
        },
      );

      if (result is! String || result.isEmpty) {
        throw const BranchFailure(
          '지점 생성 결과를 확인하지 못했습니다.',
        );
      }

      return result;
    } on BranchFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.message.contains(
        'FORESTRING_BRANCH_NAME_ALREADY_EXISTS',
      )) {
        throw const BranchFailure(
          '이미 같은 이름의 지점이 있습니다.',
        );
      }

      if (error.message.contains(
        'FORESTRING_MASTER_REQUIRED',
      )) {
        throw const BranchFailure(
          '전체 관리자만 지점을 생성할 수 있습니다.',
        );
      }

      throw BranchFailure(
        '지점을 생성하지 못했습니다.\n'
        '${error.message}',
      );
    }
  }

  Future<BranchManagementDetails> fetchBranchDetails({
    required String branchId,
  }) async {
    try {
      final result = await _client.rpc(
        'get_branch_management_details',
        params: {
          'p_branch_id': branchId,
        },
      );

      return _detailsFromResult(result);
    } on BranchFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '지점 정보를 불러오지 못했습니다.',
      );
    }
  }

  Future<BranchManagementDetails> renameBranch({
    required String branchId,
    required String name,
  }) async {
    final normalizedName = name.trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );

    if (normalizedName.isEmpty) {
      throw const BranchFailure('지점명을 입력해주세요.');
    }

    try {
      final result = await _client.rpc(
        'rename_branch',
        params: {
          'p_branch_id': branchId,
          'p_name': normalizedName,
        },
      );

      return _detailsFromResult(result);
    } on BranchFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '지점명을 변경하지 못했습니다.',
      );
    }
  }

  Future<BranchManagementDetails> setBranchActive({
    required String branchId,
    required bool isActive,
  }) async {
    try {
      final result = await _client.rpc(
        'set_branch_active',
        params: {
          'p_branch_id': branchId,
          'p_is_active': isActive,
        },
      );

      return _detailsFromResult(result);
    } on BranchFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: isActive
            ? '지점을 다시 활성화하지 못했습니다.'
            : '지점을 비활성화하지 못했습니다.',
      );
    }
  }

  BranchManagementDetails _detailsFromResult(dynamic result) {
    if (result is! Map) {
      throw const BranchFailure('지점 관리 결과를 확인하지 못했습니다.');
    }

    return BranchManagementDetails.fromJson(
      Map<String, dynamic>.from(result),
    );
  }

  BranchFailure _failureFromPostgrest(
    PostgrestException error, {
    required String fallback,
  }) {
    final message = error.message;

    if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED')) {
      return const BranchFailure('현재 계정은 더 이상 사용할 수 없습니다.');
    }
    if (message.contains('FORESTRING_MASTER_REQUIRED')) {
      return const BranchFailure('전체 관리자만 지점을 관리할 수 있습니다.');
    }
    if (message.contains('FORESTRING_BRANCH_NOT_FOUND')) {
      return const BranchFailure('지점을 찾을 수 없습니다.');
    }
    if (message.contains('FORESTRING_INVALID_BRANCH_NAME')) {
      return const BranchFailure('지점명은 1~100자로 입력해주세요.');
    }
    if (message.contains('FORESTRING_BRANCH_NAME_ALREADY_EXISTS')) {
      return const BranchFailure('이미 같은 이름의 지점이 있습니다.');
    }
    if (message.contains('FORESTRING_BRANCH_DEACTIVATION_BLOCKED')) {
      return const BranchFailure(
        '활성 계정이나 남은 일정이 있어 지점을 비활성화할 수 없습니다.',
      );
    }

    return BranchFailure('$fallback\n$message');
  }
}
