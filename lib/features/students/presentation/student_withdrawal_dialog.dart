import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../data/student_management_repository.dart';

Future<StudentWithdrawalResult?> showStudentWithdrawalDialog({
  required BuildContext context,
  required ManagedStudent student,
  required StudentManagementRepository repository,
}) {
  return showDialog<StudentWithdrawalResult>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => _StudentWithdrawalDialog(
      student: student,
      repository: repository,
    ),
  );
}

class _StudentWithdrawalDialog extends StatefulWidget {
  const _StudentWithdrawalDialog({
    required this.student,
    required this.repository,
  });

  final ManagedStudent student;
  final StudentManagementRepository repository;

  @override
  State<_StudentWithdrawalDialog> createState() =>
      _StudentWithdrawalDialogState();
}

class _StudentWithdrawalDialogState extends State<_StudentWithdrawalDialog> {
  late DateTime _withdrawalDate;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _withdrawalDate = widget.student.withdrawalDate ??
        DateTime(now.year, now.month, now.day);
  }

  bool get _isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(
      _withdrawalDate.year,
      _withdrawalDate.month,
      _withdrawalDate.day,
    );
    return selected == today;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _withdrawalDate.isBefore(today) ? today : _withdrawalDate,
      firstDate: today,
      lastDate: DateTime(today.year + 3, 12, 31),
      helpText: '퇴원일 선택',
      cancelText: '취소',
      confirmText: '선택',
    );

    if (selected == null || !mounted) return;
    setState(() => _withdrawalDate = selected);
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.repository.scheduleWithdrawal(
        studentId: widget.student.id,
        withdrawalDate: _withdrawalDate,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('yyyy.MM.dd').format(_withdrawalDate);

    return AlertDialog(
      title: Text(
        widget.student.withdrawalDate == null ? '수강생 퇴원 처리' : '퇴원 예정일 변경',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.student.displayName} · ${widget.student.branchName}',
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _saving ? null : _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '퇴원일',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(dateText),
                ),
              ),
              const SizedBox(height: 14),
              _messageBox(
                _isToday
                    ? '오늘을 선택하면 즉시 퇴원 처리됩니다. 오늘 00:00 이후의 수업은 제거되고, 남아 있는 사용 가능한 수강권은 회수되며 학생 계정은 비활성화됩니다. 과거 수업 기록은 유지됩니다.'
                    : '$dateText 퇴원 예정으로 저장되며, 해당 날짜부터의 예정 수업은 바로 시간표에서 정리되어 다른 수업 예약이 가능해집니다. 퇴원 예약을 취소하거나 날짜를 뒤로 변경하면 가능한 수업은 기존 시간으로 복원되고, 이미 다른 수업이 있는 시간은 수업권으로 남습니다.',
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _messageBox(_errorMessage!, isError: true),
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
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.redAccent,
          ),
          child: Text(
            _saving
                ? '처리 중...'
                : _isToday
                    ? '오늘 퇴원'
                    : '퇴원 예약',
          ),
        ),
      ],
    );
  }

  Widget _messageBox(String message, {bool isError = false}) {
    final color = isError ? Colors.redAccent : primaryColor;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: isError ? Colors.redAccent : Colors.black87,
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}
