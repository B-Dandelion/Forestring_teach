import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../data/teacher_repository.dart';
import 'teacher_work_hours_editor.dart';

class TeacherWorkHoursEditPage extends StatefulWidget {
  const TeacherWorkHoursEditPage({
    super.key,
    required this.teacher,
    this.title = '근무시간 변경',
    this.allowEmpty = true,
  });

  final ManagedTeacher teacher;
  final String title;
  final bool allowEmpty;

  @override
  State<TeacherWorkHoursEditPage> createState() =>
      _TeacherWorkHoursEditPageState();
}

class _TeacherWorkHoursEditPageState extends State<TeacherWorkHoursEditPage> {
  final _repository = TeacherRepository();

  late List<TeacherWorkHourDraft> _workHours;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _workHours = widget.teacher.workHours
        .map(TeacherWorkHourDraft.fromManaged)
        .toList(growable: false);
  }

  Future<void> _save() async {
    if (_saving) return;

    final validationMessage = validateTeacherWorkHours(
      _workHours,
      allowEmpty: widget.allowEmpty,
    );
    if (validationMessage != null) {
      setState(() => _errorMessage = validationMessage);
      return;
    }

    if (widget.allowEmpty &&
        _workHours.isEmpty &&
        widget.teacher.workHours.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('근무시간 전체 삭제'),
          content: const Text(
            '등록된 근무시간을 모두 삭제하면 새로운 수업 예약 가능 시간이 없어집니다. '
            '이미 등록된 수업은 유지됩니다. 계속하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('전체 삭제'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final changed = await _repository.replaceTeacherWorkHours(
        teacherId: widget.teacher.id,
        workHours: _workHours
            .map((workHour) => workHour.toInput())
            .toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context).pop(changed);
    } on TeacherFailure catch (error) {
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
      appBar: ForestringAppBar(title: widget.title),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.teacher.displayName,
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.teacher.branchName,
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '변경한 시간은 이후 예약 가능 시간 계산에 사용됩니다. '
                '이미 등록된 수업 시간은 자동으로 변경되지 않습니다.',
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 13,
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _errorCard(_errorMessage!),
            ],
            const SizedBox(height: 16),
            TeacherWorkHoursEditor(
              values: _workHours,
              enabled: !_saving,
              allowEmpty: widget.allowEmpty,
              onChanged: (values) {
                setState(() {
                  _workHours = values;
                  _errorMessage = null;
                });
              },
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_saving ? '저장 중...' : '근무시간 저장'),
            ),
            const SizedBox(height: 20),
          ],
        ),
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
}
