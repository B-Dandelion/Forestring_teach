import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../../teachers/presentation/teacher_work_hours_editor.dart';
import '../data/manager_repository.dart';

class ManagerCreatePage extends StatefulWidget {
  const ManagerCreatePage({super.key});

  @override
  State<ManagerCreatePage> createState() => _ManagerCreatePageState();
}

class _ManagerCreatePageState extends State<ManagerCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  final _repository = ManagerRepository();
  final _branchRepository = BranchRepository();

  List<AcademyBranch> _branches = const [];
  List<TeacherWorkHourDraft> _workHours = const [
    TeacherWorkHourDraft(),
  ];
  String? _branchId;
  bool _teachesLessons = false;
  bool _loading = true;
  bool _saving = false;
  bool _showPin = false;
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
    _pinConfirmController.dispose();
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
        _branchId = branches.isEmpty ? null : branches.first.id;
      });
    } on BranchFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_saving || !_formKey.currentState!.validate()) return;

    final branchId = _branchId;
    if (branchId == null || branchId.isEmpty) {
      setState(() => _errorMessage = '지점을 선택해주세요.');
      return;
    }

    if (_teachesLessons) {
      final workHourError = validateTeacherWorkHours(_workHours);
      if (workHourError != null) {
        setState(() => _errorMessage = workHourError);
        return;
      }
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final manager = await _repository.createManager(
        name: _nameController.text,
        pin: _pinController.text,
        branchId: branchId,
        workHours: _teachesLessons
            ? _workHours
                .map((draft) {
                  final input = draft.toInput();
                  return ManagerWorkHourInput(
                    weekday: input.weekday,
                    startTime: input.startTime,
                    endTime: input.endTime,
                  );
                })
                .toList(growable: false)
            : const [],
      );

      if (!mounted) return;

      String? branchName;
      for (final branch in _branches) {
        if (branch.id == branchId) {
          branchName = branch.name;
          break;
        }
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('지점장 등록 완료'),
          content: Text(
            '${manager.displayName} 지점장 계정이 등록되었습니다.\n\n'
            '지점: ${branchName ?? '-'}\n'
            '수업 담당: ${_teachesLessons ? '사용' : '미사용'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_errorMessage != null) ...[
                    _errorCard(_errorMessage!),
                    const SizedBox(height: 12),
                  ],
                  if (_branches.isEmpty) ...[
                    _emptyBranches(),
                    const SizedBox(height: 16),
                  ],
                  _sectionTitle('계정 정보'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _branchId,
                    decoration: _decoration('지점'),
                    items: _branches
                        .map(
                          (branch) => DropdownMenuItem(
                            value: branch.id,
                            child: Text(branch.name),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _branchId = value),
                    validator: (value) =>
                        value == null ? '지점을 선택해주세요.' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nameController,
                    decoration: _decoration('지점장 이름'),
                    enabled: !_saving,
                    maxLength: 100,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty) return '지점장 이름을 입력해주세요.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _pinController,
                    decoration: _pinDecoration('PIN (4자리 숫자)'),
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    obscureText: !_showPin,
                    maxLength: 4,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    validator: (value) =>
                        value == null || !RegExp(r'^\d{4}$').hasMatch(value)
                            ? '4자리 숫자를 입력해주세요.'
                            : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _pinConfirmController,
                    decoration: _pinDecoration('PIN 확인'),
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    obscureText: !_showPin,
                    maxLength: 4,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onFieldSubmitted: (_) {
                      if (!_saving && !_teachesLessons) _submit();
                    },
                    validator: (value) {
                      if (value == null || !RegExp(r'^\d{4}$').hasMatch(value)) {
                        return 'PIN을 한 번 더 입력해주세요.';
                      }
                      if (value != _pinController.text) {
                        return 'PIN이 일치하지 않습니다.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle('수업 정보'),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '수업도 담당합니다',
                      style: forestringTextStyle.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      '근무시간을 등록하면 학생 배정과 수업 일정 관리 기능을 사용할 수 있습니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    value: _teachesLessons,
                    activeColor: primaryColor,
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() {
                              _teachesLessons = value;
                              _errorMessage = null;
                              if (value && _workHours.isEmpty) {
                                _workHours = const [TeacherWorkHourDraft()];
                              }
                            });
                          },
                  ),
                  if (_teachesLessons) ...[
                    const SizedBox(height: 8),
                    Text(
                      '요일별 근무시간을 15분 단위로 등록합니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TeacherWorkHoursEditor(
                      values: _workHours,
                      enabled: !_saving,
                      onChanged: (values) {
                        setState(() {
                          _workHours = values;
                          _errorMessage = null;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed:
                        _saving || _branches.isEmpty ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_saving ? '등록 중...' : '지점장 등록'),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: forestringTextStyle.copyWith(
        color: primaryColor,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _emptyBranches() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '등록 가능한 활성 지점이 없습니다.',
            style: forestringTextStyle,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _loadBranches,
            child: const Text('지점 다시 불러오기'),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(color: Colors.redAccent),
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      counterText: '',
      border: const OutlineInputBorder(),
      isDense: true,
    );
  }

  InputDecoration _pinDecoration(String label) {
    return _decoration(label).copyWith(
      suffixIcon: IconButton(
        tooltip: _showPin ? 'PIN 숨기기' : 'PIN 보기',
        onPressed: _saving
            ? null
            : () => setState(() => _showPin = !_showPin),
        icon: Icon(
          _showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    );
  }
}
