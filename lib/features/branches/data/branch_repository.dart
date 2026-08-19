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
}
