import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../data/manager_repository.dart';

class ManagerDeparturePage extends StatefulWidget {
  const ManagerDeparturePage({
    super.key,
    required this.manager,
  });

  final ManagedManager manager;

  @override
  State<ManagerDeparturePage> createState() => _ManagerDeparturePageState();
}

class _ManagerDeparturePageState extends State<ManagerDeparturePage> {
  final _repository = ManagerRepository();

  ManagerDepartureState? _departure;
  DateTime? _selectedDate;
  bool _loading = false;
  bool _saving = false;
  String? _errorMessage;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isDue {
    final date = _departure?.withdrawalDate;
    return date != null && !date.isAfter(_today);
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.manager.withdrawalDate;
    if (widget.manager.isActive && widget.manager.withdrawalDate != null) {
      _loadDeparture();
    }
  }

  Future<void> _loadDeparture() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final departure = await _repository.fetchDepartureState(widget.manager.id);
      if (!mounted) return;
      setState(() {
        _departure = departure;
        _selectedDate = departure.withdrawalDate;
      });
    } on ManagerFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseDate() async {
    final initial = _selectedDate == null || _selectedDate!.isBefore(_today)
        ? _today
        : _selectedDate!;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _today,
      lastDate: DateTime(_today.year + 3, 12, 31),
      helpText: '퇴사 예정일 선택',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (selected != null && mounted) {
      setState(() => _selectedDate = selected);
    }
  }

  Future<void> _saveDeparture() async {
    final date = _selectedDate;
    if (date == null || _saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: Text(_departure == null ? '퇴사 예약' : '퇴사 예정일 변경'),
        content: Text(
          '${DateFormat('yyyy년 M월 d일').format(date)}부터 '
          '${widget.manager.displayName} 지점장은 로그인하거나 근무할 수 없습니다.\n\n'
          '수업을 담당하고 있다면 예정일까지 담당 학생과 일정을 정리해주세요.',
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
            child: Text(_departure == null ? '예약' : '변경'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final departure = await _repository.scheduleDeparture(
        managerId: widget.manager.id,
        withdrawalDate: date,
      );
      if (!mounted) return;
      setState(() => _departure = departure);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퇴사 예정일을 저장했습니다.')),
      );
    } on ManagerFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelDeparture() async {
    if (_departure == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: const Text('퇴사 예약 취소'),
        content: const Text('예약된 퇴사를 취소할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('예약 취소'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _repository.cancelDeparture(widget.manager.id);
      if (!mounted) return;
      setState(() {
        _departure = null;
        _selectedDate = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퇴사 예약을 취소했습니다.')),
      );
    } on ManagerFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finalizeDeparture() async {
    if (!_isDue || _departure == null || !_departure!.canFinalize || _saving) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: const Text('퇴사 확정'),
        content: Text(
          '${widget.manager.displayName} 지점장의 계정을 비활성화할까요?\n\n'
          '과거 수업과 관리 기록은 삭제되지 않습니다.',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('퇴사 확정', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _repository.finalizeDeparture(widget.manager.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ManagerFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
      await _loadDeparture();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: const ForestringAppBar(title: '지점장 퇴사 관리'),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 36),
              children: [
                Text(
                  widget.manager.displayName,
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 23,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.manager.branchName,
                  style: forestringTextStyle.copyWith(color: Colors.black54),
                ),
                const SizedBox(height: 22),
                if (!widget.manager.isActive)
                  _infoCard('이미 비활성화된 지점장 계정입니다.')
                else if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _chooseDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _selectedDate == null
                          ? '퇴사 예정일 선택'
                          : DateFormat('yyyy.MM.dd').format(_selectedDate!),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _selectedDate == null || _saving ? null : _saveDeparture,
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(_departure == null ? '퇴사 예약' : '예정일 저장'),
                  ),
                  if (_departure != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      '퇴사 전 정리 현황',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _blockerCard(_departure!),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: _isDue || _saving ? null : _cancelDeparture,
                      child: const Text('퇴사 예약 취소'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _isDue && _departure!.canFinalize && !_saving
                          ? _finalizeDeparture
                          : null,
                      icon: const Icon(Icons.person_off_outlined),
                      label: const Text('퇴사 확정 및 계정 비활성화'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ],
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _infoCard(_errorMessage!, isError: true),
                ],
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

  Widget _blockerCard(ManagerDepartureState state) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          _blockerRow('담당 학생 관계', state.assignmentCount),
          const Divider(height: 1),
          _blockerRow('정규 일정', state.seriesCount),
          const Divider(height: 1),
          _blockerRow('예정 수업', state.scheduledLessonCount),
        ],
      ),
    );
  }

  Widget _blockerRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(child: Text(label, style: forestringTextStyle)),
          Text(
            '$count개',
            style: forestringTextStyle.copyWith(
              color: count == 0 ? primaryColor : Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String text, {bool isError = false}) {
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
