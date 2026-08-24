import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/semester_repository.dart';
import '../domain/managed_semester.dart';
import 'semester_default_closure_page.dart';
import 'semester_detail_page.dart';

class SemesterManagementPage extends StatefulWidget {
  const SemesterManagementPage({super.key});

  @override
  State<SemesterManagementPage> createState() =>
      _SemesterManagementPageState();
}

class _SemesterManagementPageState extends State<SemesterManagementPage> {
  final _repository = SemesterRepository();
  final _branchRepository = BranchRepository();

  List<ManagedSemester> _semesters = const [];
  List<AcademyBranch> _branches = const [];
  String _filter = 'current_upcoming';
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

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

  List<ManagedSemester> get _visibleSemesters {
    final result = _semesters.where((semester) {
      return switch (_filter) {
        'current_upcoming' => !semester.isPast,
        'past' => semester.isPast,
        _ => true,
      };
    }).toList();

    result.sort(
      _filter == 'past'
          ? (a, b) => b.startsOn.compareTo(a.startsOn)
          : (a, b) => a.startsOn.compareTo(b.startsOn),
    );
    return result;
  }

  Future<void> _openDetail(ManagedSemester semester) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SemesterDetailPage(semesterId: semester.id),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openDefaultClosures(ManagedSemester semester) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SemesterDefaultClosurePage(semester: semester),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openCreate() async {
    if (_semesters.isEmpty) {
      _showMessage('기준이 될 기존 학기가 없습니다. 데이터 상태를 먼저 확인해주세요.');
      return;
    }

    final last = _semesters.last;
    final startsOn = last.endsOn.add(const Duration(days: 1));
    var code = _nextCode(last.code);
    var weekCount = 4;

    final draft = await showDialog<_SemesterCreateDraft>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final endsOn = startsOn.add(Duration(days: weekCount * 7 - 1));
          return AlertDialog(
            backgroundColor: neutralIvory,
            title: Text(
              '다음 학기 추가',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      initialValue: code,
                      decoration: const InputDecoration(
                        labelText: '학기 이름',
                        hintText: '예: 2028-01',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => code = value,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      value: weekCount,
                      decoration: const InputDecoration(
                        labelText: '학기 길이',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var weeks = 4; weeks <= 8; weeks++)
                          DropdownMenuItem(
                            value: weeks,
                            child: Text('$weeks주'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => weekCount = value);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    _DatePreview(startsOn: startsOn, endsOn: endsOn),
                    const SizedBox(height: 10),
                    Text(
                      '새 학기는 마지막 학기 다음 날부터 이어서 생성됩니다. '
                      '세부 경계는 생성 후 학기 상세에서 조정할 수 있습니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  final normalizedCode = code.trim();
                  if (normalizedCode.isEmpty) {
                    _showMessage('학기 이름을 입력해주세요.');
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    _SemesterCreateDraft(
                      code: normalizedCode,
                      weekCount: weekCount,
                    ),
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: primaryColor),
                child: const Text('추가'),
              ),
            ],
          );
        },
      ),
    );

    if (draft == null || !mounted) return;
    final endsOn = startsOn.add(Duration(days: draft.weekCount * 7 - 1));

    try {
      await _repository.createSemester(
        code: draft.code,
        startsOn: startsOn,
        endsOn: endsOn,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      _showMessage('새 학기를 추가했습니다.');
    } on SemesterFailure catch (error) {
      if (mounted) _showMessage(error.message);
    }
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
    final visible = _visibleSemesters;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '학기 관리',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _openCreate,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(
          '학기 추가',
          style: forestringTextStyle.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            children: [
              _SummaryCard(
                semesterCount: _semesters.length,
                branchCount: _branches.where((branch) => branch.isActive).length,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _filter,
                decoration: InputDecoration(
                  labelText: '표시 범위',
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: primaryColor.withValues(alpha: 0.18),
                    ),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'current_upcoming',
                    child: Text('현재 · 예정 학기'),
                  ),
                  DropdownMenuItem(value: 'past', child: Text('지난 학기')),
                  DropdownMenuItem(value: 'all', child: Text('전체')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _filter = value);
                },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorCard(message: _errorMessage!),
              ],
              const SizedBox(height: 14),
              if (_loading && _semesters.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Text(
                    '표시할 학기가 없습니다.',
                    textAlign: TextAlign.center,
                    style: forestringTextStyle.copyWith(color: Colors.black54),
                  ),
                )
              else ...[
                Text(
                  '${visible.length}개 학기',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ...visible.map(_semesterCard),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _semesterCard(ManagedSemester semester) {
    final statusColor = semester.isCurrent
        ? primaryColor
        : semester.isPast
            ? Colors.black45
            : Colors.blueGrey.shade700;
    final status = semester.isCurrent
        ? '현재'
        : semester.isPast
            ? '종료'
            : '예정';

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
        onTap: () => _openDetail(semester),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: primaryColor,
                ),
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
                            _semesterLabel(semester.code),
                            overflow: TextOverflow.ellipsis,
                            style: forestringTextStyle.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
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
                    const SizedBox(height: 5),
                    Text(
                      '${_formatDate(semester.startsOn)} ~ '
                      '${_formatDate(semester.endsOn)} · ${semester.weekCount}주',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    if (semester.branchOverrides.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '지점별 기간 ${semester.branchOverrides.length}곳 적용',
                        style: forestringTextStyle.copyWith(
                          color: primaryColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: '기본 휴원 설정',
                onPressed: () => _openDefaultClosures(semester),
                icon: const Icon(Icons.event_available_outlined),
                color: primaryColor,
              ),
              const Icon(Icons.chevron_right, color: primaryColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _SemesterCreateDraft {
  const _SemesterCreateDraft({
    required this.code,
    required this.weekCount,
  });

  final String code;
  final int weekCount;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.semesterCount,
    required this.branchCount,
  });

  final int semesterCount;
  final int branchCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '기본 학기 일정과 기본 휴원은 모든 지점에 적용됩니다. '
        '학기 카드의 휴원 아이콘에서 기본 휴원을 설정하고, '
        '학기 상세에서는 필요한 지점만 별도 기간과 휴원을 설정할 수 있습니다.\n'
        '등록된 학기 $semesterCount개 · 운영 지점 $branchCount곳',
        style: forestringTextStyle.copyWith(fontSize: 13, height: 1.45),
      ),
    );
  }
}

class _DatePreview extends StatelessWidget {
  const _DatePreview({
    required this.startsOn,
    required this.endsOn,
  });

  final DateTime startsOn;
  final DateTime endsOn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: Text(
        '${_formatDate(startsOn)} ~ ${_formatDate(endsOn)}',
        style: forestringTextStyle.copyWith(
          color: primaryColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
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

String _nextCode(String code) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(code.trim());
  if (match == null) return '';

  var year = int.parse(match.group(1)!);
  var month = int.parse(match.group(2)!) + 1;
  if (month > 12) {
    year += 1;
    month = 1;
  }
  return '$year-${month.toString().padLeft(2, '0')}';
}

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
