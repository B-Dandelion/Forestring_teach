import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/branch_closure.dart';
import '../domain/managed_semester.dart';

class SemesterDefaultClosurePage extends StatefulWidget {
  const SemesterDefaultClosurePage({super.key, required this.semester});

  final ManagedSemester semester;

  @override
  State<SemesterDefaultClosurePage> createState() =>
      _SemesterDefaultClosurePageState();
}

class _SemesterDefaultClosurePageState
    extends State<SemesterDefaultClosurePage> {
  final _repository = BranchRepository();
  List<DefaultClosure> _closures = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _repository.fetchDefaultClosuresForSemester(
        semesterId: widget.semester.id,
      );
      if (mounted) setState(() => _closures = rows);
    } on BranchFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(BranchClosureKind kind, [DefaultClosure? closure]) async {
    if (_saving) return;
    final semester = widget.semester;
    var start = closure?.startsOn ?? _initialDate(semester, kind);
    var end = closure?.endsOn ??
        (kind == BranchClosureKind.instructionalBreak
            ? start.add(const Duration(days: 6))
            : start);
    var reason = closure?.reason ?? '';
    String? error;

    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final days = end.difference(start).inDays + 1;
          return AlertDialog(
            backgroundColor: neutralIvory,
            title: Text(
              closure == null ? '기본 ${kind.label} 추가' : '기본 ${kind.label} 수정',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 370,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '모든 지점에 기본 적용',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_date(semester.startsOn)} ~ ${_date(semester.endsOn)}',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: dialogContext,
                          firstDate: semester.startsOn,
                          lastDate: semester.endsOn,
                          initialDateRange: DateTimeRange(start: start, end: end),
                          helpText: '${kind.label} 선택',
                        );
                        if (picked == null) return;
                        setDialogState(() {
                          start = _onlyDate(picked.start);
                          end = _onlyDate(picked.end);
                          error = null;
                        });
                      },
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(
                        start == end ? _date(start) : '${_date(start)} ~ ${_date(end)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kind == BranchClosureKind.instructionalBreak
                          ? '$days일 · 7일 단위'
                          : (days == 1 ? '하루 휴원' : '$days일 휴원'),
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      initialValue: reason,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: '사유 (선택)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => reason = value,
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: forestringTextStyle.copyWith(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
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
                  final count = end.difference(start).inDays + 1;
                  if (kind == BranchClosureKind.instructionalBreak &&
                      (count < 7 || count % 7 != 0)) {
                    setDialogState(() => error = '휴원 주간은 7일 단위로 선택해주세요.');
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                },
                style: FilledButton.styleFrom(backgroundColor: primaryColor),
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );
    if (save != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _repository.saveDefaultClosure(
        defaultClosureId: closure?.id,
        semesterId: semester.id,
        startsOn: start,
        endsOn: end,
        kind: kind,
        reason: reason,
      );
      await _load();
      if (mounted) _message('기본 휴원 일정을 저장했습니다.');
    } on BranchFailure catch (e) {
      if (mounted) _message(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(DefaultClosure closure) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('기본 휴원 삭제'),
        content: Text(
          '기본값을 따르는 모든 지점에서 함께 제거됩니다.\n'
          '지점별로 변경한 휴원은 유지됩니다.',
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
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _repository.deleteDefaultClosure(defaultClosureId: closure.id);
      await _load();
      if (mounted) _message('기본 휴원 일정을 삭제했습니다.');
    } on BranchFailure catch (e) {
      if (mounted) _message(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '기본 휴원 설정',
        actions: [
          IconButton(
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          children: [
            Text(
              _semesterLabel(widget.semester.code),
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 21,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '여기서 설정한 휴원은 모든 지점의 기본값입니다. '
              '지점별로 따로 수정한 일정만 이 기본값을 따르지 않습니다.',
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _edit(
                              BranchClosureKind.instructionalBreak,
                            ),
                    icon: const Icon(Icons.calendar_view_week_outlined),
                    label: const Text('휴원 주간 추가'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _edit(BranchClosureKind.ordinary),
                    icon: const Icon(Icons.event_busy_outlined),
                    label: const Text('휴원일 추가'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 50),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(
                _error!,
                style: forestringTextStyle.copyWith(color: Colors.redAccent),
              )
            else if (_closures.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 45),
                child: Text(
                  '등록된 기본 휴원 일정이 없습니다.',
                  textAlign: TextAlign.center,
                  style: forestringTextStyle.copyWith(color: Colors.black54),
                ),
              )
            else
              ..._closures.map(_card),
          ],
        ),
      ),
    );
  }

  Widget _card(DefaultClosure closure) {
    final isBreak = closure.kind == BranchClosureKind.instructionalBreak;
    final range = closure.startsOn == closure.endsOn
        ? _date(closure.startsOn)
        : '${_date(closure.startsOn)} ~ ${_date(closure.endsOn)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        onTap: () => _edit(closure.kind, closure),
        leading: Icon(
          isBreak
              ? Icons.calendar_view_week_outlined
              : Icons.event_busy_outlined,
          color: primaryColor,
        ),
        title: Text(
          range,
          style: forestringTextStyle.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: closure.reason?.trim().isNotEmpty == true
            ? Text(
                closure.reason!.trim(),
                style: forestringTextStyle.copyWith(fontSize: 12),
              )
            : null,
        trailing: IconButton(
          tooltip: '삭제',
          onPressed: _saving ? null : () => _delete(closure),
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

DateTime _onlyDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _initialDate(ManagedSemester semester, BranchClosureKind kind) {
  final now = _onlyDate(DateTime.now());
  var date = now.isBefore(semester.startsOn) || now.isAfter(semester.endsOn)
      ? semester.startsOn
      : now;
  if (kind == BranchClosureKind.instructionalBreak &&
      date.add(const Duration(days: 6)).isAfter(semester.endsOn)) {
    date = semester.endsOn.subtract(const Duration(days: 6));
  }
  return date;
}

String _semesterLabel(String code) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(code.trim());
  return match == null
      ? code
      : '${match.group(1)}년 ${int.parse(match.group(2)!)}월 학기';
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.'
    '${value.day.toString().padLeft(2, '0')}';