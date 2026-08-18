import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'auth_controller.dart';
import '../../teachers/presentation/create_teacher_smoke_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final controller = context.read<AuthController>();

    final success = await controller.signIn(
      name: _nameController.text,
      pin: _pinController.text,
    );

    if (!mounted || !success) {
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Forestring v3'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: auth.isSignedIn
                  ? _SignedInView(
                      userId: auth.user?.id ?? '',
                      onSignOut: auth.signOut,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '로그인',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '이름과 4자리 PIN을 입력해주세요.',
                        ),
                        const SizedBox(height: 32),
                        TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '이름',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          obscureText: true,
                          maxLength: 4,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(
                              4,
                            ),
                          ],
                          onSubmitted: (_) => _login(),
                          decoration: const InputDecoration(
                            labelText: 'PIN',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (auth.errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            auth.errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: auth.isLoading ? null : _login,
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('로그인'),
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

class _SignedInView extends StatelessWidget {
  const _SignedInView({
    required this.userId,
    required this.onSignOut,
  });

  final String userId;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 64,
        ),
        const SizedBox(height: 16),
        Text(
          'Supabase 로그인 성공',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        SelectableText(
          'Auth UID\n$userId',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
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
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () async {
            await onSignOut();
          },
          child: const Text('로그아웃'),
        ),
      ],
    );
  }
}
