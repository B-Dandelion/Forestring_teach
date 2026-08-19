import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'auth_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
  });

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

    await context.read<AuthController>().signIn(
          name: _nameController.text,
          pin: _pinController.text,
        );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Forestring v3',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
            ),
            child: Padding(
              padding: const EdgeInsets.all(
                24,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '로그인',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  const Text(
                    '이름과 4자리 PIN을 입력해주세요.',
                  ),
                  const SizedBox(
                    height: 32,
                  ),
                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '이름',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
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
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      auth.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(
                    height: 16,
                  ),
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
                        : const Text(
                            '로그인',
                          ),
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
