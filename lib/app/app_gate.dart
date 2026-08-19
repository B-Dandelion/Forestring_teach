import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/auth/domain/current_profile.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/branches/presentation/branch_management_page.dart';
import '../features/managers/presentation/create_manager_smoke_page.dart';
import '../features/managers/presentation/manager_rls_smoke_panel.dart';
import '../features/teachers/presentation/create_teacher_smoke_page.dart';
import '../features/students/presentation/create_student_smoke_page.dart';

class AppGate extends StatelessWidget {
  const AppGate({
    super.key,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final auth = context.watch<AuthController>();

    if (auth.isInitializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final profile = auth.profile;

    if (!auth.isSignedIn || profile == null) {
      return const LoginPage();
    }

    return switch (profile.role) {
      AppRole.master => _MasterEntry(
        profile: profile,
      ),
      AppRole.manager => _ManagerEntry(
        profile: profile,
      ),
      AppRole.teacher => _TeacherEntry(
        profile: profile,
      ),
      AppRole.student => _StudentBlockedEntry(
        profile: profile,
      ),
    };
  }
}

class _MasterEntry extends StatelessWidget {
  const _MasterEntry({
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(
      BuildContext context,
      ) {
    return _RoleScaffold(
      profile: profile,
      title: '전체 관리자',
      message: '모든 지점과 선생님, 학생, 수업을 관리할 수 있습니다.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const BranchManagementPage(),
              ),
            );
          },
          icon: const Icon(
            Icons.storefront_outlined,
          ),
          label: const Text(
            '지점 관리',
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CreateTeacherSmokePage(),
              ),
            );
          },
          child: const Text(
            '선생님 생성 Smoke Test',
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CreateManagerSmokePage(),
              ),
            );
          },
          icon: const Icon(
            Icons.manage_accounts_outlined,
          ),
          label: const Text(
            '지점장 생성 Smoke Test',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    CreateStudentSmokePage(
                      actorProfile: profile,
                    ),
              ),
            );
          },
          icon: const Icon(
            Icons.person_add_alt_1_outlined,
          ),
          label: const Text(
            '학생 생성 Smoke Test',
          ),
        ),
      ],
    );
  }
}

class _ManagerEntry extends StatelessWidget {
  const _ManagerEntry({
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(
      BuildContext context,
      ) {
    return _RoleScaffold(
      profile: profile,
      title: '지점 관리자',
      message: profile.branchId == null
          ? '아직 지점이 배정되지 않은 관리자입니다.'
          : '본인 지점의 선생님, 학생, 수업을 관리합니다.',
      actions: [
        FilledButton.icon(
          onPressed: profile.branchId == null
              ? null
              : () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    CreateStudentSmokePage(
                      actorProfile:
                      profile,
                    ),
              ),
            );
          },
          icon: const Icon(
            Icons.person_add_alt_1_outlined,
          ),
          label: const Text(
            '학생 생성 Smoke Test',
          ),
        ),
        const SizedBox(
          height: 20,
        ),
        const ManagerRlsSmokePanel(),
      ],
    );
  }
}

class _TeacherEntry extends StatelessWidget {
  const _TeacherEntry({
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(
      BuildContext context,
      ) {
    return _RoleScaffold(
      profile: profile,
      title: '선생님',
      message: profile.branchId == null
          ? '현재 테스트 계정에는 아직 지점이 배정되지 않았습니다.'
          : '담당 학생과 수업을 관리합니다.',
    );
  }
}

class _StudentBlockedEntry extends StatelessWidget {
  const _StudentBlockedEntry({
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(
      BuildContext context,
      ) {
    return _RoleScaffold(
      profile: profile,
      title: '접근할 수 없습니다',
      message: '학생 계정은 학생용 포레스트링 앱을 이용해주세요.',
    );
  }
}

class _RoleScaffold extends StatelessWidget {
  const _RoleScaffold({
    required this.profile,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  final CurrentProfile profile;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(
      BuildContext context,
      ) {
    final auth = context.read<AuthController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Forestring v3',
        ),
        actions: [
          TextButton(
            onPressed: auth.signOut,
            child: const Text(
              '로그아웃',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 520,
            ),

            // RLS 결과가 길어져도 화면이 터지지 않도록
            // 기존 Column 대신 스크롤 가능하게 처리.
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(
                    height: 80,
                  ),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    '${profile.displayName}님',
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    message,
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(
                      height: 32,
                    ),
                    ...actions,
                  ],
                  const SizedBox(
                    height: 40,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}