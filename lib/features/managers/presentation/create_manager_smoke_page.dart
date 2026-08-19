import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/manager_repository.dart';

class CreateManagerSmokePage extends StatefulWidget {
  const CreateManagerSmokePage({
    super.key,
  });

  @override
  State<CreateManagerSmokePage> createState() => _CreateManagerSmokePageState();
}

class _CreateManagerSmokePageState extends State<CreateManagerSmokePage> {
  final _nameController = TextEditingController();

  final _pinController = TextEditingController();

  final _repository = ManagerRepository();

  final _branchRepository = BranchRepository();

  List<AcademyBranch> _branches = const [];

  String? _branchId;

  bool _isLoading = false;
  bool _isLoadingBranches = true;

  String? _resultMessage;

  @override
  void initState() {
    super.initState();

    _loadBranches();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();

    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _isLoadingBranches = true;
    });

    try {
      final branches = await _branchRepository.fetchBranches();

      if (!mounted) {
        return;
      }

      final activeBranches = branches
          .where(
            (branch) => branch.isActive,
          )
          .toList();

      setState(() {
        _branches = activeBranches;

        if (activeBranches.isNotEmpty) {
          _branchId = activeBranches.first.id;
        }

        _resultMessage = null;
      });
    } on BranchFailure catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _resultMessage = '지점 목록 조회 실패\n'
            '${error.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBranches = false;
        });
      }
    }
  }

  Future<void> _createManager() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final branchId = _branchId;

    if (branchId == null || branchId.isEmpty) {
      setState(() {
        _resultMessage = '지점을 선택해주세요.';
      });

      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });

    try {
      final manager = await _repository.createManager(
        name: _nameController.text,
        pin: _pinController.text,
        branchId: branchId,
      );

      if (!mounted) {
        return;
      }

      String? branchName;

      for (final branch in _branches) {
        if (branch.id == branchId) {
          branchName = branch.name;
          break;
        }
      }

      setState(() {
        _resultMessage = '생성 성공\n'
            '지점: ${branchName ?? '-'}\n'
            '지점장: ${manager.displayName}\n'
            '${manager.id}';

        _pinController.clear();
      });
    } on ManagerFailure catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _resultMessage = '생성 실패\n'
            '${error.message}';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '지점장 생성 Smoke Test',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(
            24,
          ),
          children: [
            const Text(
              '실제 Supabase DB에 지점장 계정을 생성합니다.',
            ),
            const SizedBox(
              height: 24,
            ),
            if (_isLoadingBranches)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(
                    16,
                  ),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_branches.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '등록된 활성 지점이 없습니다.',
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  OutlinedButton(
                    onPressed: _loadBranches,
                    child: const Text(
                      '지점 다시 불러오기',
                    ),
                  ),
                ],
              )
            else
              DropdownButtonFormField<String>(
                value: _branchId,
                decoration: const InputDecoration(
                  labelText: '지점',
                  border: OutlineInputBorder(),
                ),
                items: _branches
                    .map(
                      (branch) => DropdownMenuItem<String>(
                        value: branch.id,
                        child: Text(
                          branch.name,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _branchId = value;
                  });
                },
              ),
            const SizedBox(
              height: 16,
            ),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '지점장 이름',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(
                  4,
                ),
              ],
              decoration: const InputDecoration(
                labelText: '4자리 PIN',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            const SizedBox(
              height: 24,
            ),
            FilledButton(
              onPressed: _isLoading || _isLoadingBranches || _branches.isEmpty
                  ? null
                  : _createManager,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      '테스트 지점장 생성',
                    ),
            ),
            if (_resultMessage != null) ...[
              const SizedBox(
                height: 24,
              ),
              SelectableText(
                _resultMessage!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
