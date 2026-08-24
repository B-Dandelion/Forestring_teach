import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/manager_repository.dart';

class ManagerCreatePage extends StatefulWidget {
  const ManagerCreatePage({super.key});

  @override
  State<ManagerCreatePage> createState() => _ManagerCreatePageState();
}

class _ManagerCreatePageState extends State<ManagerCreatePage> {
  final _repository = ManagerRepository();
  final _branchRepository = BranchRepository();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();

  List<AcademyBranch> _branches = const [];
  String? _branchId;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

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
      _loading = true;
      _errorMessage = null;
    });
    try {
      final branches = (await _branchRepository.fetchBranches())
          .where((branch) => branch.isActive)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _branches = branches;
        if (_branchId == null && branches.isNotEmpty) {
          _branchId = branches.first.id;
        }
      });
    } on BranchFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final branchId = _branchId;
    if (branchId == null) {
      setState(() => _errorMessage = '지점을 선택해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await _repository.createManager(
        name: _nameController.text,
        pin: _pinController.text,
        branchId: branchId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ManagerFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: const ForestringAppBar(title: '지점장 등록'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 36),
          children: [
            Text(
              '새 지점장',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 24,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '이름, 로그인 PIN, 담당 지점만 설정하면 바로 계정이 생성됩니다.',
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_branches.isEmpty)
              _messageCard('등록 가능한 운영 지점이 없습니다.')
            else ...[
              DropdownButtonFormField<String>(
                value: _branchId,
                decoration: _decoration('담당 지점'),
                items: _branches
                    .map(
                      (branch) => DropdownMenuItem(
                        value: branch.id,
                        child: Text(branch.name),
                      ),
                    )
                    .toList(),
                onChanged: _saving ? null : (value) => setState(() => _branchId = value),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                decoration: _decoration('지점장 이름'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pinController,
                enabled: !_saving,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: const [],
                decoration: _decoration('4자리 PIN').copyWith(
                  counterText: '',
                ),
                onChanged: (value) {
                  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits != value) {
                    _pinController.value = TextEditingValue(
                      text: digits.length > 4 ? digits.substring(0, 4) : digits,
                      selection: TextSelection.collapsed(
                        offset: digits.length > 4 ? 4 : digits.length,
                      ),
                    );
                  }
                },
                onSubmitted: (_) => _saving ? null : _save(),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _messageCard(_errorMessage!, isError: true),
            ],
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _loading || _saving || _branches.isEmpty ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('지점장 등록'),
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _messageCard(String text, {bool isError = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? Colors.red.withValues(alpha: 0.06)
            : secondaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: forestringTextStyle.copyWith(
          color: isError ? Colors.red.shade700 : Colors.black54,
        ),
      ),
    );
  }
}
