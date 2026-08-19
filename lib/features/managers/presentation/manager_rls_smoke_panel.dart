import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManagerRlsSmokePanel extends StatefulWidget {
  const ManagerRlsSmokePanel({
    super.key,
  });

  @override
  State<ManagerRlsSmokePanel> createState() => _ManagerRlsSmokePanelState();
}

class _ManagerRlsSmokePanelState extends State<ManagerRlsSmokePanel> {
  bool _isLoading = false;
  String? _result;

  Future<void> _runTest() async {
    setState(() {
      _isLoading = true;
      _result = null;
    });

    try {
      final client = Supabase.instance.client;

      final currentUserId = client.auth.currentUser?.id;

      if (currentUserId == null) {
        throw Exception('로그인 세션이 없습니다.');
      }

      // ------------------------------------------------------
      // RLS가 적용된 실제 client 조회
      // service_role 아님.
      // ------------------------------------------------------

      final branchRaw = await client.from('branches').select(
            'id, name',
          );

      final profileRaw = await client.from('profiles').select(
            'id, display_name, role, branch_id',
          );

      final teacherRaw = await client.from('teachers').select(
            'id',
          );

      final studentRaw = await client.from('students').select(
            'id',
          );

      final lessonRaw = await client.from('lessons').select(
            'id',
          );

      final branches = List<Map<String, dynamic>>.from(
        branchRaw,
      );

      final profiles = List<Map<String, dynamic>>.from(
        profileRaw,
      );

      final teachers = List<Map<String, dynamic>>.from(
        teacherRaw,
      );

      final students = List<Map<String, dynamic>>.from(
        studentRaw,
      );

      final lessons = List<Map<String, dynamic>>.from(
        lessonRaw,
      );

      final profileById = <String, Map<String, dynamic>>{};

      for (final profile in profiles) {
        final id = profile['id'];

        if (id is String) {
          profileById[id] = profile;
        }
      }

      final branchNames = branches
          .map(
            (branch) => branch['name']?.toString() ?? '(이름 없음)',
          )
          .join(', ');

      final visibleProfiles = profiles.map(
        (profile) {
          final name = profile['display_name']?.toString() ?? '(이름 없음)';

          final role = profile['role']?.toString() ?? '?';

          final isMe = profile['id'] == currentUserId;

          return '$name [$role]'
              '${isMe ? ' ← 나' : ''}';
        },
      ).join('\n');

      final visibleTeachers = teachers.map(
        (teacher) {
          final id = teacher['id']?.toString();

          final profile = id == null ? null : profileById[id];

          final name = profile?['display_name']?.toString() ?? '(프로필 이름 조회 불가)';

          final role = profile?['role']?.toString() ?? '?';

          return '$name [$role]';
        },
      ).join('\n');

      // 현재 테스트 환경에는 지점이 2개 이상 존재하므로
      // manager가 1개 지점만 본다면 기본 branch RLS PASS.
      final branchRlsPass = branches.length == 1;

      final buffer = StringBuffer();

      buffer.writeln(
        branchRlsPass ? '✅ RLS 기본 판정: PASS' : '❌ RLS 기본 판정: FAIL',
      );

      buffer.writeln();
      buffer.writeln(
        '현재 사용자 UUID',
      );
      buffer.writeln(
        currentUserId,
      );

      buffer.writeln();
      buffer.writeln(
        '조회 가능한 지점 (${branches.length})',
      );
      buffer.writeln(
        branchNames.isEmpty ? '(없음)' : branchNames,
      );

      buffer.writeln();
      buffer.writeln(
        '조회 가능한 프로필 (${profiles.length})',
      );
      buffer.writeln(
        visibleProfiles.isEmpty ? '(없음)' : visibleProfiles,
      );

      buffer.writeln();
      buffer.writeln(
        '조회 가능한 수업 담당자 (${teachers.length})',
      );
      buffer.writeln(
        visibleTeachers.isEmpty ? '(없음)' : visibleTeachers,
      );

      buffer.writeln();
      buffer.writeln(
        '조회 가능한 학생: ${students.length}명',
      );

      buffer.writeln(
        '조회 가능한 수업: ${lessons.length}개',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _result = buffer.toString();
      });
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _result = '❌ Supabase 조회 실패\n'
            '${error.message}\n'
            'code: ${error.code}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _result = '❌ 테스트 실패\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(
          height: 32,
        ),
        const Divider(),
        const SizedBox(
          height: 16,
        ),
        const Text(
          '임시 RLS 권한 테스트',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        const Text(
          '현재 로그인한 계정 권한으로 Supabase를 직접 조회합니다.',
        ),
        const SizedBox(
          height: 16,
        ),
        OutlinedButton(
          onPressed: _isLoading ? null : _runTest,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'RLS 권한 테스트 실행',
                ),
        ),
        if (_result != null) ...[
          const SizedBox(
            height: 20,
          ),
          SelectableText(
            _result!,
          ),
        ],
      ],
    );
  }
}
