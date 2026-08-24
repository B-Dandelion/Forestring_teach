import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../data/branch_repository.dart';
import '../domain/branch_closure.dart';

class BranchClosurePage extends StatefulWidget {
  const BranchClosurePage({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.initialKind,
  });

  final String branchId;
  final String branchName;
  final BranchClosureKind initialKind;

  @override
  State<BranchClosurePage> createState() => _BranchClosurePageState();
}

class _BranchClosurePageState extends State<BranchClosurePage> {
  final _repository = BranchRepository();

  List<BranchClosure> _closures = const [];
  List<AcademySemester> _semesters = const [];
  late BranchClosureKind _kind;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _repository.fetchBranchClosures(branchId: widget.branchId),
        _repository.fetchSemesters(),
      ]);

      if (!mounted) return;
      setState(() {
        _closures = results[0] as List<BranchClosure>;
        _semesters = results[1] as List<AcademySemester>;
      });
    } on BranchFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<BranchClosure> get _visibleClosures => _closures
      .where((closure) => closure.kind == _kind)
      .toList()
    ..sort((a, b) => b.startsOn.compareTo(a.startsOn));

  Future<void> _openEditor([BranchClosure? closure]) async {
    if (_saving) return;

    final today = _dateOnly(DateTime.now());
    DateTime start = closure?.startsOn ?? today;
    DateTime end = closure?.endsOn ??
        (_kind == BranchClosureKind.instructionalBreak
            ? today.add(const Duration(days: 6))
            : today);
    final reasonController = TextEditingController(text: closure?.reason ?? '');

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> chooseRange() async {
              final picked = await showDateRangePicker(
                context: dialogContext,
                firstDate: DateTime(2025, 1, 1),
                lastDate: DateTime(DateTime.now().year + 5, 12, 31),
                initialDateRange: DateTimeRange(start: start, end: end),
                helpText: _kind == BranchClosureKind.instructionalBreak
                    ? '휴원 주간 선택'
                    : '휴원일 선택',
                cancelText: '취소',
                confirmText: '선택',
              );

              if (picked == null) return;
              setDialogState(() {
                start = _dateOnly(picked.start);
                end = _dateOnly(picked.end);
              });
            }

            final days = end.difference(start).inDays + 1;
            final semester = _kind == BranchClosureKind.instructionalBreak
                ? _findSemester(start, end)
                : null;

            return AlertDialog(
              backgroundColor: neutralIvory,
              title: Text(
                closure == null
                    ? (_kind == BranchClosureKind.instructionalBreak
                        ? '휴원 주간 추가'
                        : '휴원일 추가')
                    : (_kind == BranchClosureKind.instructionalBreak
                        ? '휴원 주간 수정'
                        : '휴원일 수정'),
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: chooseRange,
                        icon: const Icon(Icons.date_range_outlined),
                        label: Text('${_formatDate(start)} ~ ${_formatDate(end)}'),
                      ),
                      const SizedBox(height: 8),
                      if (_kind == BranchClosureKind.instructionalBreak)
                        Text(
                          semester == null
                              ? '선택한 기간이 하나의 학기 안에 포함되어야 합니다.'
                              : '${semester.code} · $days일',
                          style: forestringTextStyle.copyWith(
                            fontSize: 13,
                            color: semester == null
                                ? Colors.red.shade700
                                : Colors.black54,
                          ),
                        )
                      else
                        Text(
                          days == 1 ? '하루 휴원' : '$days일 휴원',
                          style: forestringTextStyle.copyWith(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: reasonController,
                        style: forestringTextStyle,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: '사유 (선택)',
                          hintText: '예: 여름 휴원, 시설 점검',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_kind == BranchClosureKind.instructionalBreak) ...[
                        const SizedBox(height: 4),
                        Text(
                          '휴원 주간은 7일 단위로만 저장됩니다.',
                          style: forestringTextStyle.copyWith(
                            fontSize: 12,
                            color: Colors.black45,
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
                  onPressed: () {
                    if (_kind == BranchClosureKind.instructionalBreak) {
                      if (days < 7 || days % 7 != 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('휴원 주간은 7일 단위로 선택해주세요.')),
                        );
                        return;
                      }
                      if (semester == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('선택한 기간에 해당하는 학기를 찾지 못했습니다.')),
                        );
                        return;
                      }
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  style: FilledButton.styleFrom(backgroundColor: primaryColor),
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSave != true || !mounted) {
      reasonController.dispose();
      return;
    }

    final semester = _kind == BranchClosureKind.instructionalBreak
        ? _findSemester(start, end)
        : null;

    setState(() => _saving = true);
    try {
      await _repository.saveClosure(
        closureId: closure?.id,
        branchId: widget.branchId,
        semesterId: semester?.id,
        startsOn: start,
        endsOn: end,
        kind: _kind,
        reason: reasonController.text,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            closure == null ? '휴원 일정을 추가했습니다.' : '휴원 일정을 수정했습니다.',
          ),
        ),
      );
    } on BranchFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      reasonController.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(BranchClosure closure) async {
    if (_saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: const Text('휴원 일정 삭제'),
        content: Text(
          '${_formatDate(closure.startsOn)} ~ ${_formatDate(closure.endsOn)} 휴원 일정을 삭제할까요?',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('삭제', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _repository.deleteClosure(closureId: closure.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('휴원 일정을 삭제했습니다.')),
      );
    } on BranchFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  AcademySemester? _findSemester(DateTime start, DateTime end) {
    for (final semester in _semesters) {
      if (semester.contains(start, end)) return semester;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '휴원 관리',
        actions: [
          IconButton(
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _openEditor(),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(
          _kind == BranchClosureKind.instructionalBreak ? '휴원 주간 추가' : '휴원일 추가',
          style: forestringTextStyle.copyWith(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.branchName,
                        style: forestringTextStyle.copyWith(
                          color: primaryColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SegmentedButton<BranchClosureKind>(
                        segments: const [
                          ButtonSegment(
                            value: BranchClosureKind.instructionalBreak,
                            label: Text('휴원 주간'),
                            icon: Icon(Icons.calendar_view_week_outlined),
                          ),
                          ButtonSegment(
                            value: BranchClosureKind.ordinary,
                            label: Text('휴원일'),
                            icon: Icon(Icons.event_busy_outlined),
                          ),
                        ],
                        selected: {_kind},
                        onSelectionChanged: (selection) {
                          setState(() => _kind = selection.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _kind == BranchClosureKind.instructionalBreak
                            ? '정규 수업 생성에서 제외할 7일 단위 휴원 기간입니다.'
                            : '공휴일, 시설 점검 등 하루 또는 임의 기간의 휴원을 등록합니다.',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black54,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildBody()),
              ],
            ),
            if (_saving)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x22000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: forestringTextStyle,
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }

    final closures = _visibleClosures;
    if (closures.isEmpty) {
      return Center(
        child: Text(
          _kind == BranchClosureKind.instructionalBreak
              ? '등록된 휴원 주간이 없습니다.'
              : '등록된 휴원일이 없습니다.',
          style: forestringTextStyle.copyWith(color: Colors.black54),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        itemCount: closures.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final closure = closures[index];
          final days = closure.endsOn.difference(closure.startsOn).inDays + 1;

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
              title: Text(
                closure.startsOn == closure.endsOn
                    ? _formatDate(closure.startsOn)
                    : '${_formatDate(closure.startsOn)} ~ ${_formatDate(closure.endsOn)}',
                style: forestringTextStyle.copyWith(
                  fontWeight: FontWeight.w500,
                  color: primaryColor,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  [
                    '$days일',
                    if (closure.reason != null && closure.reason!.trim().isNotEmpty)
                      closure.reason!.trim(),
                  ].join(' · '),
                  style: forestringTextStyle.copyWith(fontSize: 13),
                ),
              ),
              onTap: () => _openEditor(closure),
              trailing: IconButton(
                onPressed: () => _delete(closure),
                icon: const Icon(Icons.delete_outline),
                color: Colors.red.shade600,
                tooltip: '삭제',
              ),
            ),
          );
        },
      ),
    );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year.$month.$day';
}
