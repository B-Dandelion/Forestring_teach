import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/student_management_repository.dart';
import 'student_create_page.dart';
import 'student_regular_schedule_page.dart';
import 'student_teacher_change_dialog.dart';

class StudentManagementPage extends StatefulWidget {
  const StudentManagementPage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  State<StudentManagementPage> createState() => _StudentManagementPageState();
}

class _StudentManagementPageState extends State<StudentManagementPage> {
  static const _allBranches = '__all__';

  final _repository = StudentManagementRepository();
  final _branchRepository = BranchRepository();
  final _searchController = TextEditingController();

  List<AcademyBranch> _branches = const [];
  List<ManagedStudent> _students = const [];

  String? _branchId;
  String _typeFilter = 'all';
  String _statusFilter = 'active';
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final branches = (await _branchRepository.fetchBranches())
          .where((branch) => branch.isActive)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final branchId = widget.profile.isManager ? widget.profile.branchId : null;

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _branchId = branchId;
      });

      await _loadStudents();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadStudents() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final students = await _repository.fetchStudents(branchId: _branchId);
      if (!mounted) return;
      setState(() => _students = students);
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _students = const [];
        _errorMessage = error.message;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<ManagedStudent> get _visibleStudents {
    final query = _searchController.text.trim().toLowerCase();

    return _students.where((student) {
      if (_typeFilter != 'all' && student.studentType != _typeFilter) {
        return false;
      }
      if (_statusFilter == 'active' && !student.isActive) {
        return false;
      }
      if (_statusFilter == 'withdrawn' && student.isActive) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }

      return student.displayName.toLowerCase().contains(query) ||
          (student.teacherName ?? '').toLowerCase().contains(query) ||
          student.branchName.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openRegistration() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentCreatePage(profile: widget.profile),
      ),
    );

    if (mounted) {
      await _loadStudents();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleStudents = _visibleStudents;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '수강생 관리',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _loadStudents,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        onPressed: _openRegistration,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(
          '수강생 등록',
          style: forestringTextStyle.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStudents,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            children: [
              _buildFilters(),
              const SizedBox(height: 14),
              if (_errorMessage != null) ...[
                _errorCard(_errorMessage!),
                const SizedBox(height: 12),
              ],
              if (_loading && _students.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visibleStudents.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(
                    child: Text(
                      '조건에 맞는 수강생이 없습니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),
                )
              else ...[
                Text(
                  '${visibleStudents.length}명',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ...visibleStudents.map(_studentCard),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '수강생 이름 검색',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (widget.profile.isMaster) ...[
          DropdownButtonFormField<String>(
            value: _branchId ?? _allBranches,
            decoration: _filterDecoration('지점'),
            items: [
              const DropdownMenuItem(
                value: _allBranches,
                child: Text('전체 지점'),
              ),
              ..._branches.map(
                (branch) => DropdownMenuItem(
                  value: branch.id,
                  child: Text(branch.name),
                ),
              ),
            ],
            onChanged: _loading
                ? null
                : (value) async {
                    setState(() {
                      _branchId = value == _allBranches ? null : value;
                    });
                    await _loadStudents();
                  },
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _typeFilter,
                decoration: _filterDecoration('수강 형태'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('전체')),
                  DropdownMenuItem(value: 'regular', child: Text('정규')),
                  DropdownMenuItem(value: 'flex', child: Text('자율 예약')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _typeFilter = value);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _statusFilter,
                decoration: _filterDecoration('상태'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('전체')),
                  DropdownMenuItem(value: 'active', child: Text('재원')),
                  DropdownMenuItem(value: 'withdrawn', child: Text('퇴원')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _statusFilter = value);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _filterDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.18)),
      ),
    );
  }

  Widget _studentCard(ManagedStudent student) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetails(student),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline, color: primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            student.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: forestringTextStyle.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusBadge(student),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${student.typeLabel} · ${student.branchName}',
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      student.teacherName == null
                          ? '담당 선생님 미배정'
                          : '${student.teacherName} 선생님',
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: secondaryColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(ManagedStudent student) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: student.isActive
            ? primaryColor.withValues(alpha: 0.09)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        student.statusLabel,
        style: forestringTextStyle.copyWith(
          color: student.isActive ? primaryColor : Colors.black45,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _showDetails(ManagedStudent student) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: neutralIvory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              24 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  student.displayName,
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 23,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                _detailRow('수강 형태', student.typeLabel),
                _detailRow('상태', student.statusLabel),
                _detailRow('지점', student.branchName),
                _detailRow(
                  '담당 선생님',
                  student.teacherName == null
                      ? '미배정'
                      : '${student.teacherName} 선생님',
                ),
                if (student.withdrawalDate != null)
                  _detailRow(
                    '퇴원일',
                    DateFormat('yyyy.MM.dd').format(student.withdrawalDate!),
                  ),
                if (student.isActive) ...[
                  const SizedBox(height: 16),
                  if (student.isRegular) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await Future<void>.delayed(
                          const Duration(milliseconds: 220),
                        );
                        if (!mounted) return;
                        await _openRegularScheduleManagement(student);
                      },
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: const Text('정규 일정 관리'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        side: const BorderSide(color: primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await Future<void>.delayed(
                        const Duration(milliseconds: 220),
                      );
                      if (!mounted) return;
                      await _openTeacherChange(student);
                    },
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: Text(
                      student.teacherId == null
                          ? '담당 선생님 지정'
                          : '담당 선생님 변경',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: const BorderSide(color: primaryColor),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await Future<void>.delayed(
                        const Duration(milliseconds: 220),
                      );
                      if (!mounted) return;
                      await _showPinResetDialog(student);
                    },
                    icon: const Icon(Icons.lock_reset_outlined),
                    label: const Text('PIN 재설정'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: const BorderSide(color: primaryColor),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  style: FilledButton.styleFrom(backgroundColor: primaryColor),
                  child: const Text('확인'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openRegularScheduleManagement(ManagedStudent student) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentRegularSchedulePage(student: student),
      ),
    );

    if (mounted) {
      await _loadStudents();
    }
  }

  Future<void> _openTeacherChange(ManagedStudent student) async {
    final changed = await showStudentTeacherChangeDialog(
      context: context,
      student: student,
    );

    if (!mounted || changed != true) return;

    await _loadStudents();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('담당 선생님 변경이 저장되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showPinResetDialog(ManagedStudent student) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _PinResetDialog(
        student: student,
        repository: _repository,
      ),
    );

    if (!mounted || changed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PIN이 변경되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: forestringTextStyle.copyWith(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.22)),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: Colors.redAccent,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _PinResetDialog extends StatefulWidget {
  const _PinResetDialog({
    required this.student,
    required this.repository,
  });

  final ManagedStudent student;
  final StudentManagementRepository repository;

  @override
  State<_PinResetDialog> createState() => _PinResetDialogState();
}

class _PinResetDialogState extends State<_PinResetDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _saving = false;
  String? _validationMessage;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pinController.text.trim();
    final confirmPin = _confirmController.text.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _validationMessage = 'PIN은 4자리 숫자로 입력해주세요.');
      return;
    }
    if (pin != confirmPin) {
      setState(() => _validationMessage = 'PIN 확인 값이 일치하지 않습니다.');
      return;
    }

    setState(() {
      _saving = true;
      _validationMessage = null;
    });

    try {
      await widget.repository.resetStudentPin(
        studentId: widget.student.id,
        pin: pin,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PIN 재설정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.student.displayName} 학생의 로그인 PIN을 변경합니다.',
              style: forestringTextStyle.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              enabled: !_saving,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '새 PIN (4자리)',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmController,
              enabled: !_saving,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '새 PIN 확인',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _validationMessage!,
                style: forestringTextStyle.copyWith(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: primaryColor),
          child: Text(_saving ? '변경 중...' : '변경'),
        ),
      ],
    );
  }
}
