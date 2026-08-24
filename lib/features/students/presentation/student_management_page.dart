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
import 'student_lesson_history_page.dart';
import 'student_regular_schedule_page.dart';
import 'student_teacher_change_dialog.dart';
import 'student_withdrawal_dialog.dart';

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
    final color = student.isActive
        ? (student.hasScheduledWithdrawal ? Colors.orange.shade700 : primaryColor)
        : Colors.black45;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        student.statusLabel,
        style: forestringTextStyle.copyWith(
          color: color,
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
                if (student.isFlex)
                  _detailRow(
                    '현재 수업권',
                    student.flexBaseRightCount == null
                        ? '설정 확인 필요'
                        : '${student.flexBaseRightCount}개',
                  ),
                if (student.withdrawalDate != null)
                  _detailRow(
                    student.isActive ? '퇴원 예정일' : '퇴원일',
                    DateFormat('yyyy.MM.dd').format(student.withdrawalDate!),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await Future<void>.delayed(
                      const Duration(milliseconds: 220),
                    );
                    if (!mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StudentLessonHistoryPage(
                          student: student,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('수업 일정 · 이력'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: const BorderSide(color: primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
                if (student.isActive) ...[
                  const SizedBox(height: 8),
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
                  ] else if (student.isFlex) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await Future<void>.delayed(
                          const Duration(milliseconds: 220),
                        );
                        if (!mounted) return;
                        await _showFlexRightCountDialog(student);
                      },
                      icon: const Icon(Icons.confirmation_number_outlined),
                      label: const Text('수업권 설정 변경'),
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
                      await _showNameEditDialog(student);
                    },
                    icon: const Icon(Icons.drive_file_rename_outline),
                    label: const Text('이름 수정'),
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
                  const SizedBox(height: 8),
                  if (student.withdrawalIsDue)
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await Future<void>.delayed(
                          const Duration(milliseconds: 220),
                        );
                        if (!mounted) return;
                        await _finalizeWithdrawal(student);
                      },
                      icon: const Icon(Icons.person_off_outlined),
                      label: const Text('퇴원 확정'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    )
                  else ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await Future<void>.delayed(
                          const Duration(milliseconds: 220),
                        );
                        if (!mounted) return;
                        await _openWithdrawal(student);
                      },
                      icon: const Icon(Icons.person_off_outlined),
                      label: Text(
                        student.hasScheduledWithdrawal
                            ? '퇴원 예정일 변경'
                            : '퇴원 처리',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                    if (student.hasScheduledWithdrawal) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await Future<void>.delayed(
                            const Duration(milliseconds: 220),
                          );
                          if (!mounted) return;
                          await _cancelWithdrawal(student);
                        },
                        icon: const Icon(Icons.undo_rounded),
                        label: const Text('퇴원 예약 취소'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black54,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ],
                  ],
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

  Future<void> _openWithdrawal(ManagedStudent student) async {
    final result = await showStudentWithdrawalDialog(
      context: context,
      student: student,
      repository: _repository,
    );

    if (!mounted || result == null) return;

    await _loadStudents();
    if (!mounted) return;

    final message = result.finalized
        ? '퇴원 처리가 완료되었습니다. 미래 수업 ${result.deletedLessonCount}개가 정리되었습니다.'
        : '${DateFormat('yyyy.MM.dd').format(result.withdrawalDate)} 퇴원 예정으로 저장되었습니다.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _finalizeWithdrawal(ManagedStudent student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('퇴원 확정'),
        content: Text(
          '${student.displayName} 학생의 퇴원을 확정합니다.\n\n'
          '퇴원일 이후 수업은 제거되고 남아 있는 사용 가능한 수강권은 회수되며, 학생 계정은 비활성화됩니다. 과거 수업 기록은 유지됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('퇴원 확정'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    try {
      final result = await _repository.finalizeWithdrawal(
        studentId: student.id,
      );
      if (!mounted) return;

      await _loadStudents();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '퇴원 처리가 완료되었습니다. 미래 수업 ${result.deletedLessonCount}개가 정리되었습니다.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cancelWithdrawal(ManagedStudent student) async {
    final date = student.withdrawalDate;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('퇴원 예약 취소'),
        content: Text(
          date == null
              ? '${student.displayName} 학생의 퇴원 예약을 취소할까요?'
              : '${student.displayName} 학생의 ${DateFormat('yyyy.MM.dd').format(date)} 퇴원 예약을 취소할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('아니요'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            child: const Text('예약 취소'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    try {
      await _repository.cancelWithdrawal(studentId: student.id);
      if (!mounted) return;

      await _loadStudents();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('퇴원 예약이 취소되었습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showNameEditDialog(ManagedStudent student) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _StudentNameEditDialog(
        student: student,
        repository: _repository,
      ),
    );

    if (!mounted || changed != true) return;
    await _loadStudents();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이름이 변경되었습니다.'),
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

  Future<void> _showFlexRightCountDialog(ManagedStudent student) async {
    final result = await showDialog<FlexRightCountChangeResult>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _FlexRightCountDialog(
        student: student,
        repository: _repository,
      ),
    );

    if (!mounted || result == null) return;
    await _loadStudents();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '수업권이 ${result.newBaseRightCount}개로 변경되었습니다. '
          '취소 가능 ${result.newCancellationLimit}회 · '
          '이월 상한 ${result.newCarryoverCap}개',
        ),
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

class _StudentNameEditDialog extends StatefulWidget {
  const _StudentNameEditDialog({
    required this.student,
    required this.repository,
  });

  final ManagedStudent student;
  final StudentManagementRepository repository;

  @override
  State<_StudentNameEditDialog> createState() =>
      _StudentNameEditDialogState();
}

class _StudentNameEditDialogState extends State<_StudentNameEditDialog> {
  late final TextEditingController _nameController;

  bool _saving = false;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.student.displayName);
    _nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _nameController.text.length,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final currentName = widget.student.displayName
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    if (name.isEmpty) {
      setState(() => _validationMessage = '이름을 입력해주세요.');
      return;
    }
    if (name.length > 100) {
      setState(() => _validationMessage = '이름은 100자 이하로 입력해주세요.');
      return;
    }
    if (name == currentName) {
      setState(() => _validationMessage = '현재 이름과 동일합니다.');
      return;
    }

    setState(() {
      _saving = true;
      _validationMessage = null;
    });

    try {
      await widget.repository.updateStudentName(
        studentId: widget.student.id,
        name: name,
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
      title: const Text('학생 이름 수정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '이름을 변경하면 학생이 로그인할 때 사용하는 이름도 함께 변경됩니다.',
              style: forestringTextStyle.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              enabled: !_saving,
              autofocus: true,
              maxLength: 100,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_saving) _save();
              },
              decoration: const InputDecoration(
                labelText: '학생 이름',
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

class _FlexRightCountDialog extends StatefulWidget {
  const _FlexRightCountDialog({
    required this.student,
    required this.repository,
  });

  final ManagedStudent student;
  final StudentManagementRepository repository;

  @override
  State<_FlexRightCountDialog> createState() =>
      _FlexRightCountDialogState();
}

class _FlexRightCountDialogState extends State<_FlexRightCountDialog> {
  late final TextEditingController _countController;

  bool _saving = false;
  String? _validationMessage;

  int? get _enteredCount => int.tryParse(_countController.text.trim());

  @override
  void initState() {
    super.initState();
    _countController = TextEditingController(
      text: widget.student.flexBaseRightCount?.toString() ?? '',
    )..addListener(_onCountChanged);
  }

  @override
  void dispose() {
    _countController
      ..removeListener(_onCountChanged)
      ..dispose();
    super.dispose();
  }

  void _onCountChanged() {
    if (mounted) setState(() => _validationMessage = null);
  }

  Future<void> _save() async {
    final currentCount = widget.student.flexBaseRightCount;
    final newCount = _enteredCount;

    if (currentCount == null) {
      setState(() {
        _validationMessage = '현재 학기의 자율 수업권 설정을 찾지 못했습니다.';
      });
      return;
    }
    if (newCount == null || newCount <= 0) {
      setState(() => _validationMessage = '수업권 개수를 1개 이상 입력해주세요.');
      return;
    }
    if (newCount == currentCount) {
      setState(() => _validationMessage = '현재 수업권 개수와 동일합니다.');
      return;
    }

    if (newCount < currentCount) {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (confirmContext) => AlertDialog(
          title: const Text('수업권 감액 확인'),
          content: Text(
            '${widget.student.displayName} 학생의 수업권을 '
            '$currentCount개에서 $newCount개로 줄일까요?\n\n'
            '아직 예약·사용·취소 이력이 없는 수업권만 회수됩니다. '
            '회수할 수 없는 수업권이 포함되면 변경 전체가 취소됩니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(confirmContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text('감액'),
            ),
          ],
        ),
      );

      if (!mounted || confirmed != true) return;
    }

    setState(() {
      _saving = true;
      _validationMessage = null;
    });

    try {
      final result = await widget.repository.changeFlexBaseRightCount(
        studentId: widget.student.id,
        newBaseRightCount: newCount,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
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
    final currentCount = widget.student.flexBaseRightCount;
    final enteredCount = _enteredCount;
    final cancellationLimit =
        enteredCount == null ? null : (enteredCount ~/ 4) * 2;
    final carryoverCap = enteredCount == null ? null : enteredCount ~/ 4;
    final isDecrease = currentCount != null &&
        enteredCount != null &&
        enteredCount < currentCount;
    final currentSettingLabel = currentCount == null
        ? '현재 설정: 확인 필요'
        : [
            '현재 설정: 수업권 $currentCount개',
            if (widget.student.flexDurationMinutes != null)
              '${widget.student.flexDurationMinutes}분',
          ].join(' · ');

    return AlertDialog(
      title: const Text('자율 수업권 변경'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.student.displayName} · 현재 학기',
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                currentSettingLabel,
                style: forestringTextStyle.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _countController,
                enabled: !_saving && currentCount != null,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_saving) _save();
                },
                decoration: const InputDecoration(
                  labelText: '변경할 수업권 개수',
                  suffixText: '개',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _policyBox(
                enteredCount == null || enteredCount <= 0
                    ? '수업권 개수를 입력하면 변경 후 취소 가능 횟수와 '
                        '이월 상한을 확인할 수 있습니다.'
                    : '변경 후 취소 가능 $cancellationLimit회 · '
                        '이월 상한 $carryoverCap개\n'
                        '취소 가능 횟수는 2 × floor(수업권 ÷ 4)이며, '
                        '같은 수업권을 다시 취소해도 매번 차감됩니다.',
              ),
              if (isDecrease) ...[
                const SizedBox(height: 10),
                _policyBox(
                  '감액은 번호가 뒤인 미사용 수업권부터 회수합니다. '
                  '예약·사용·취소 이력이 있거나, 새 취소 한도가 이미 '
                  '사용한 횟수보다 작아지면 저장되지 않습니다.',
                  isWarning: true,
                ),
              ],
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
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _saving || currentCount == null ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: primaryColor),
          child: Text(_saving ? '변경 중...' : '변경'),
        ),
      ],
    );
  }

  Widget _policyBox(String message, {bool isWarning = false}) {
    final color = isWarning ? Colors.orange.shade800 : primaryColor;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: Colors.black87,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}
