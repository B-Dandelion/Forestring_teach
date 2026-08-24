import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/semester_repository.dart';
import '../domain/managed_semester.dart';

class SemesterDetailPage extends StatefulWidget {
  const SemesterDetailPage({
    super.key,
    required this.semesterId,
  });

  final String semesterId;

  @override
  State<SemesterDetailPage> createState() => _SemesterDetailPageState();
}

class _SemesterDetailPageState extends State<SemesterDetailPage> {
  final _repository = SemesterRepository();
  final _branchRepository = BranchRepository();

  List<ManagedSemester> _semesters = const [];
  List<AcademyBranch> _branches = const [];
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  String? _errorMessage;

  ManagedSemester? get _semester {
    for (final semester in _semesters) {
      if (semester.id == widget.semesterId) return semester;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _repository.fetchSemesters(),
        _branchRepository.fetchBranches(),
      ]);
      if (!mounted) return;

      final semesters = (results[0] as List<ManagedSemester>).toList()
        ..sort((a, b) => a.startsOn.compareTo(b.startsOn));
      final branches = (results[1] as List<AcademyBranch>).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _semesters = semesters;
        _branches = branches;
      });
    } on SemesterFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on BranchFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editCode() async {
    final semester = _semester;
    if (semester == null || _saving) return;

    final controller = TextEditingController(text: semester.code);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: Text(
          '학기 이름 수정',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '학기 이름',
            hintText: '예: 2026-09',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('학기 이름을 입력해주세요.')),
                );
                return;
              }
              Navigator.of(dialogContext).pop(true);
            },
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) {
      controller.dispose();
      return;
    }

    final code = controller.text.trim();
    controller.dispose();
    if (code == semester.code) return;

    await _runSave(() async {
      await _repository.updateSemesterCode(
        semester: semester,
        code: code,
      );
    }, successMessage: '학기 이름을 변경했습니다.');
  }

  Future<void> _editGlobalRange() async {
    final semester = _semester;
    if (semester == null || _saving) return;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      initialDateRange: DateTimeRange(
        start: semester.startsOn,
        end: semester.endsOn,
      ),
      helpText: '기본 학기 기간 변경',
      cancelText: '취소',
      confirmText: '선택',
    );

    if (picked == null || !mounted) return;
    final start = _dateOnly(picked.start);
    final end = _dateOnly(picked.end);

    final changes = _buildGlobalChanges(
      semesterId: semester.id,
      startsOn: start,
      endsOn: end,
    );
    if (changes == null) return;
    if (changes.isEmpty) {
      _showMessage('변경된 기간이 없습니다.');
      return;
    }

    final confirmed = await _confirmBoundaryChanges(
      title: '기본 학기 기간 변경',
      changes: changes,
      branchId: null,
    );
    if (confirmed != true || !mounted) return;

    await _runSave(
      () => _repository.applySemesterCalendarChanges(changes),
      successMessage: '기본 학기 기간을 변경했습니다.',
    );
  }

  Future<void> _editBranchRange(AcademyBranch branch) async {
    final semester = _semester;
    if (semester == null || _saving) return;

    final currentStart = semester.effectiveStart(branch.id);
    final currentEnd = semester.effectiveEnd(branch.id);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      initialDateRange: DateTimeRange(
        start: currentStart,
        end: currentEnd,
      ),
      helpText: '${branch.name} 학기 기간',
      cancelText: '취소',
      confirmText: '선택',
    );

    if (picked == null || !mounted) return;

    final changes = _buildBranchChanges(
      branchId: branch.id,
      semesterId: semester.id,
      startsOn: _dateOnly(picked.start),
      endsOn: _dateOnly(picked.end),
    );
    if (changes == null) return;
    if (changes.isEmpty) {
      _showMessage('변경된 기간이 없습니다.');
      return;
    }

    final previewChanges = _branchPreviewChanges(branch.id, changes);
    final confirmed = await _confirmBoundaryChanges(
      title: '${branch.name} 기간 변경',
      changes: previewChanges,
      branchId: branch.id,
    );
    if (confirmed != true || !mounted) return;

    await _runSave(
      () => _repository.applyBranchSemesterChanges(
        branchId: branch.id,
        changes: changes,
      ),
      successMessage: '${branch.name} 학기 기간을 변경했습니다.',
    );
  }

  Future<void> _resetBranchRange(AcademyBranch branch) async {
    final semester = _semester;
    if (semester == null || semester.overrideFor(branch.id) == null || _saving) {
      return;
    }

    final changes = _buildBranchChanges(
      branchId: branch.id,
      semesterId: semester.id,
      startsOn: semester.startsOn,
      endsOn: semester.endsOn,
    );
    if (changes == null || changes.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('기본 기간으로 복원'),
        content: Text(
          '${branch.name}의 별도 학기 기간을 해제하고 기본 학기 일정을 사용합니다.\n\n'
          '앞·뒤 학기의 지점별 경계도 필요한 경우 함께 정리됩니다.',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            child: const Text('복원'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runSave(
      () => _repository.applyBranchSemesterChanges(
        branchId: branch.id,
        changes: changes,
      ),
      successMessage: '${branch.name}이(가) 기본 학기 일정을 사용하도록 변경했습니다.',
    );
  }

  List<SemesterCalendarChange>? _buildGlobalChanges({
    required String semesterId,
    required DateTime startsOn,
    required DateTime endsOn,
  }) {
    final index = _semesters.indexWhere((semester) => semester.id == semesterId);
    if (index < 0) return null;

    final selected = _semesters[index];
    if (!_validRange(startsOn, endsOn)) {
      _showMessage('학기 기간은 4주 이상이며 7일 단위여야 합니다.');
      return null;
    }

    final desired = <String, _Bounds>{
      selected.id: _Bounds(startsOn, endsOn),
    };

    if (startsOn != selected.startsOn && index > 0) {
      final previous = _semesters[index - 1];
      desired[previous.id] = _Bounds(
        previous.startsOn,
        startsOn.subtract(const Duration(days: 1)),
      );
    }
    if (endsOn != selected.endsOn && index < _semesters.length - 1) {
      final next = _semesters[index + 1];
      desired[next.id] = _Bounds(
        endsOn.add(const Duration(days: 1)),
        next.endsOn,
      );
    }

    for (final bounds in desired.values) {
      if (!_validRange(bounds.start, bounds.end)) {
        _showMessage(
          '이 경계로 변경하면 인접 학기가 4주 미만이거나 7일 단위가 아니게 됩니다. '
          '학기 경계는 주 단위로 조정해주세요.',
        );
        return null;
      }
    }

    final result = <SemesterCalendarChange>[];
    for (final semester in _semesters) {
      final bounds = desired[semester.id];
      if (bounds == null) continue;
      if (bounds.start == semester.startsOn && bounds.end == semester.endsOn) {
        continue;
      }
      result.add(
        SemesterCalendarChange(
          semesterId: semester.id,
          code: semester.code,
          startsOn: bounds.start,
          endsOn: bounds.end,
        ),
      );
    }
    return result;
  }

  List<BranchSemesterChange>? _buildBranchChanges({
    required String branchId,
    required String semesterId,
    required DateTime startsOn,
    required DateTime endsOn,
  }) {
    final index = _semesters.indexWhere((semester) => semester.id == semesterId);
    if (index < 0) return null;

    if (!_validRange(startsOn, endsOn)) {
      _showMessage('학기 기간은 4주 이상이며 7일 단위여야 합니다.');
      return null;
    }

    final selected = _semesters[index];
    final currentStart = selected.effectiveStart(branchId);
    final currentEnd = selected.effectiveEnd(branchId);

    final desired = <String, _Bounds>{
      selected.id: _Bounds(startsOn, endsOn),
    };

    if (startsOn != currentStart && index > 0) {
      final previous = _semesters[index - 1];
      desired[previous.id] = _Bounds(
        previous.effectiveStart(branchId),
        startsOn.subtract(const Duration(days: 1)),
      );
    }
    if (endsOn != currentEnd && index < _semesters.length - 1) {
      final next = _semesters[index + 1];
      desired[next.id] = _Bounds(
        endsOn.add(const Duration(days: 1)),
        next.effectiveEnd(branchId),
      );
    }

    for (final bounds in desired.values) {
      if (!_validRange(bounds.start, bounds.end)) {
        _showMessage(
          '이 경계로 변경하면 인접 학기가 4주 미만이거나 7일 단위가 아니게 됩니다. '
          '지점별 학기 경계도 주 단위로 조정해주세요.',
        );
        return null;
      }
    }

    final result = <BranchSemesterChange>[];
    for (final semester in _semesters) {
      final bounds = desired[semester.id];
      if (bounds == null) continue;

      final currentEffectiveStart = semester.effectiveStart(branchId);
      final currentEffectiveEnd = semester.effectiveEnd(branchId);
      if (bounds.start == currentEffectiveStart &&
          bounds.end == currentEffectiveEnd) {
        continue;
      }

      final equalsGlobal = bounds.start == semester.startsOn &&
          bounds.end == semester.endsOn;
      final existingOverride = semester.overrideFor(branchId);

      if (equalsGlobal) {
        if (existingOverride != null) {
          result.add(BranchSemesterChange.delete(semester.id));
        }
      } else {
        result.add(
          BranchSemesterChange.upsert(
            semesterId: semester.id,
            startsOn: bounds.start,
            endsOn: bounds.end,
          ),
        );
      }
    }
    return result;
  }

  List<SemesterCalendarChange> _branchPreviewChanges(
    String branchId,
    List<BranchSemesterChange> changes,
  ) {
    final result = <SemesterCalendarChange>[];
    for (final change in changes) {
      final semester = _semesters.firstWhere(
        (item) => item.id == change.semesterId,
      );
      if (change.delete) {
        result.add(
          SemesterCalendarChange(
            semesterId: semester.id,
            code: semester.code,
            startsOn: semester.startsOn,
            endsOn: semester.endsOn,
          ),
        );
      } else {
        result.add(
          SemesterCalendarChange(
            semesterId: semester.id,
            code: semester.code,
            startsOn: change.startsOn!,
            endsOn: change.endsOn!,
          ),
        );
      }
    }
    return result;
  }

  Future<bool?> _confirmBoundaryChanges({
    required String title,
    required List<SemesterCalendarChange> changes,
    required String? branchId,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: Text(
          title,
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  changes.length > 1
                      ? '학기 사이가 끊기지 않도록 인접 학기 경계도 함께 변경됩니다.'
                      : '선택한 학기 기간을 변경합니다.',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                ...changes.map(
                  (change) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _semesterLabel(change.code),
                          style: forestringTextStyle.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_formatDate(change.startsOn)} ~ '
                          '${_formatDate(change.endsOn)}',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (branchId == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '이미 수업이 생성된 학기 경계는 변경되지 않습니다.',
                    style: forestringTextStyle.copyWith(
                      color: Colors.orange.shade800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            child: const Text('변경'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSemester() async {
    final semester = _semester;
    if (semester == null || _saving || _semesters.last.id != semester.id) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('학기 삭제'),
        content: Text(
          '${_semesterLabel(semester.code)}을(를) 삭제합니다.\n\n'
          '수업, 휴원, 학생 학기 데이터 등이 연결되어 있으면 삭제되지 않습니다.',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _repository.deleteSemester(semester.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SemesterFailure catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runSave(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await action();
      if (!mounted) return;
      _changed = true;
      await _load();
      if (!mounted) return;
      _showMessage(successMessage);
    } on SemesterFailure catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _validRange(DateTime start, DateTime end) {
    final days = end.difference(start).inDays + 1;
    return !end.isBefore(start) && days >= 28 && days % 7 == 0;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semester = _semester;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop || !_changed) return;
      },
      child: Scaffold(
        backgroundColor: neutralIvory,
        appBar: ForestringAppBar(
          title: '학기 상세',
          actions: [
            IconButton(
              tooltip: '새로고침',
              onPressed: _loading || _saving ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: _loading && semester == null
              ? const Center(child: CircularProgressIndicator())
              : semester == null
                  ? Center(
                      child: Text(
                        _errorMessage ?? '학기 정보를 찾을 수 없습니다.',
                        style: forestringTextStyle,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                      children: [
                        _headerCard(semester),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          _errorCard(_errorMessage!),
                        ],
                        const SizedBox(height: 18),
                        _sectionTitle('기본 학기 설정'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : _editCode,
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('학기 이름 수정'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : _editGlobalRange,
                                  icon: const Icon(Icons.date_range_outlined),
                                  label: const Text('기간 변경'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '기간을 바꾸면 학기 사이에 빈 날짜가 생기지 않도록 앞·뒤 학기 경계도 함께 조정됩니다.',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black45,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _sectionTitle('지점별 기간'),
                        const SizedBox(height: 4),
                        Text(
                          '기본 일정과 다른 지점만 별도 기간을 설정합니다.',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._branches.map((branch) => _branchCard(semester, branch)),
                        if (_semesters.isNotEmpty &&
                            _semesters.last.id == semester.id) ...[
                          const SizedBox(height: 22),
                          _sectionTitle('학기 삭제'),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _saving ? null : _deleteSemester,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('마지막 학기 삭제'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade700),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ],
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _headerCard(ManagedSemester semester) {
    final statusColor = semester.isCurrent
        ? primaryColor
        : semester.isPast
            ? Colors.black45
            : Colors.blueGrey.shade700;
    final status = semester.isCurrent
        ? '현재 학기'
        : semester.isPast
            ? '종료된 학기'
            : '예정 학기';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _semesterLabel(semester.code),
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: forestringTextStyle.copyWith(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatDate(semester.startsOn)} ~ ${_formatDate(semester.endsOn)}',
            style: forestringTextStyle.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 3),
          Text(
            '${semester.weekCount}주 · 지점별 별도 기간 ${semester.branchOverrides.length}곳',
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _branchCard(ManagedSemester semester, AcademyBranch branch) {
    final override = semester.overrideFor(branch.id);
    final start = semester.effectiveStart(branch.id);
    final end = semester.effectiveEnd(branch.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: override == null
              ? Colors.black12
              : primaryColor.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    branch.name,
                    style: forestringTextStyle.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (override == null ? Colors.black45 : primaryColor)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    override == null ? '기본 기간' : '별도 기간',
                    style: forestringTextStyle.copyWith(
                      color: override == null ? Colors.black54 : primaryColor,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_formatDate(start)} ~ ${_formatDate(end)} · '
              '${end.difference(start).inDays ~/ 7 + 1}주',
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _editBranchRange(branch),
                    child: Text(override == null ? '별도 기간 설정' : '기간 변경'),
                  ),
                ),
                if (override != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : () => _resetBranchRange(branch),
                      child: const Text('기본값으로 복원'),
                    ),
                  ),
                ],
              ],
            ),
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
        fontSize: 17,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(13),
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
}

class _Bounds {
  const _Bounds(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _semesterLabel(String code) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(code.trim());
  if (match == null) return code;
  return '${match.group(1)}년 ${int.parse(match.group(2)!)}월 학기';
}

String _formatDate(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year.$month.$day';
}
