import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../data/student_management_repository.dart';
import '../data/student_next_semester_type_repository.dart';

Future<bool?> showStudentNextSemesterTypeDialog({
  required BuildContext context,
  required ManagedStudent student,
}) {
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => StudentNextSemesterTypeDialog(student: student),
  );
}

class StudentNextSemesterTypeDialog extends StatefulWidget {
  const StudentNextSemesterTypeDialog({
    super.key,
    required this.student,
  });

  final ManagedStudent student;

  @override
  State<StudentNextSemesterTypeDialog> createState() =>
      _StudentNextSemesterTypeDialogState();
}

class _StudentNextSemesterTypeDialogState
    extends State<StudentNextSemesterTypeDialog> {
  final _repository = StudentNextSemesterTypeRepository();
  final _rightCountController = TextEditingController();

  NextSemesterStudentTypePlan? _plan;
  List<NextSemesterTeacherWorkWindow> _workHours = const [];
  final List<_NextRegularScheduleDraft> _regularSchedules = [];

  String _targetType = 'regular';
  int _flexDurationMinutes = 30;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rightCountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final plan = await _repository.fetchPlan(widget.student.id);
      if (!mounted) return;

      _targetType = plan.plannedStudentType;
      final count = plan.flexBaseRightCount ?? plan.defaultFlexBaseRightCount;
      _rightCountController.text = count.toString();
      _flexDurationMinutes =
          plan.flexDurationMinutes ?? plan.defaultFlexDurationMinutes;

      setState(() => _plan = plan);
      await _loadWorkHoursIfNeeded(plan);
    } on StudentNextSemesterTypeFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadWorkHoursIfNeeded(
    NextSemesterStudentTypePlan plan,
  ) async {
    if (plan.regularScheduleCount > 0 || plan.teacherId == null) {
      if (mounted) {
        setState(() => _workHours = const []);
      }
      return;
    }

    try {
      final workHours = await _repository.fetchTeacherWorkHours(
        teacherId: plan.teacherId!,
        onDate: plan.nextSemesterStartsOn,
      );
      if (!mounted) return;

      setState(() {
        _workHours = workHours;
        if (_regularSchedules.isEmpty && workHours.isNotEmpty) {
          final first = workHours.first;
          final availableMinutes = first.endMinutes - first.startMinutes;
          final duration = availableMinutes >= 30 ? 30 : 15;
          _regularSchedules.add(
            _NextRegularScheduleDraft(
              weekday: first.weekday,
              startMinutes: first.startMinutes,
              durationMinutes: duration,
            ),
          );
        }
      });
    } on StudentNextSemesterTypeFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    }
  }

  Future<void> _changeTarget(String value) async {
    if (_saving || value == _targetType) return;
    setState(() {
      _targetType = value;
      _errorMessage = null;
    });

    final plan = _plan;
    if (plan != null && value == 'regular') {
      await _loadWorkHoursIfNeeded(plan);
    }
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null || _saving || !plan.canChange) return;

    int? flexCount;
    if (_targetType == 'flex') {
      flexCount = int.tryParse(_rightCountController.text.trim());
      if (flexCount == null || flexCount <= 0) {
        setState(() => _errorMessage = '수업권 개수를 1개 이상 입력해주세요.');
        return;
      }
    }

    List<Map<String, dynamic>>? regularSchedules;
    if (_targetType == 'regular' && plan.regularScheduleCount == 0) {
      if (plan.teacherId == null || !plan.teacherAssignmentCoversSemester) {
        setState(() {
          _errorMessage = '다음 학기 전체 기간의 담당 선생님을 먼저 지정해주세요.';
        });
        return;
      }
      if (_regularSchedules.isEmpty) {
        setState(() => _errorMessage = '정규 수업 일정을 한 개 이상 추가해주세요.');
        return;
      }
      if (_regularSchedules.any((draft) => draft.startMinutes % 15 != 0)) {
        setState(() => _errorMessage = '정규 수업 시작 시간은 15분 단위로 선택해주세요.');
        return;
      }

      final signatures = <String>{};
      for (final draft in _regularSchedules) {
        if (!signatures.add(draft.signature)) {
          setState(() => _errorMessage = '같은 정규 수업 일정이 중복되어 있습니다.');
          return;
        }
      }

      regularSchedules = _regularSchedules
          .map((draft) => draft.toJson())
          .toList(growable: false);
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await _repository.save(
        studentId: widget.student.id,
        targetType: _targetType,
        flexBaseRightCount: flexCount,
        flexDurationMinutes:
            _targetType == 'flex' ? _flexDurationMinutes : null,
        regularSchedules: regularSchedules,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StudentNextSemesterTypeFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _loading
              ? const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              : plan == null
                  ? _buildLoadFailure()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '다음 학기 수강 형태',
                                style: forestringTextStyle.copyWith(
                                  color: primaryColor,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.of(context).pop(false),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.student.displayName,
                          style: forestringTextStyle.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _semesterCard(plan),
                                const SizedBox(height: 14),
                                if (!plan.canChange) ...[
                                  _warningCard(
                                    '다음 학기 시작 전이며 퇴원 일정과 겹치지 않을 때만 수강 형태를 변경할 수 있습니다.',
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (_errorMessage != null) ...[
                                  _errorCard(_errorMessage!),
                                  const SizedBox(height: 12),
                                ],
                                _sectionTitle('다음 학기 수강 형태'),
                                const SizedBox(height: 8),
                                SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'regular',
                                      label: Text('정규'),
                                      icon: Icon(Icons.event_repeat_outlined),
                                    ),
                                    ButtonSegment(
                                      value: 'flex',
                                      label: Text('자율 예약'),
                                      icon: Icon(Icons.confirmation_number_outlined),
                                    ),
                                  ],
                                  selected: {_targetType},
                                  onSelectionChanged:
                                      _saving || !plan.canChange
                                          ? null
                                          : (values) =>
                                              _changeTarget(values.first),
                                ),
                                const SizedBox(height: 14),
                                if (_targetType == 'flex')
                                  _buildFlexSettings(plan)
                                else
                                  _buildRegularSettings(plan),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.of(context).pop(false),
                                child: const Text('취소'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed:
                                    _saving || !plan.canChange ? null : _save,
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryColor,
                                ),
                                child: Text(_saving ? '저장 중...' : '다음 학기에 적용'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildLoadFailure() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '다음 학기 수강 형태',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        _errorCard(_errorMessage ?? '정보를 불러오지 못했습니다.'),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _load,
          style: FilledButton.styleFrom(backgroundColor: primaryColor),
          child: const Text('다시 시도'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('닫기'),
        ),
      ],
    );
  }

  Widget _semesterCard(NextSemesterStudentTypePlan plan) {
    final dateFormat = DateFormat('yyyy.MM.dd');
    final hasDifferentPlan = plan.currentStudentType != plan.plannedStudentType;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${plan.nextSemesterCode} 학기',
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${dateFormat.format(plan.nextSemesterStartsOn)} ~ '
            '${dateFormat.format(plan.nextSemesterEndsOn)}',
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasDifferentPlan
                ? '현재 ${plan.currentTypeLabel} → 다음 학기 ${plan.plannedTypeLabel} 예정'
                : '현재와 다음 학기 모두 ${plan.currentTypeLabel}',
            style: forestringTextStyle.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '현재 학기에는 영향을 주지 않습니다. 다음 학기 시작일부터 적용되며, 학기 시작 전까지 다시 변경할 수 있습니다.',
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlexSettings(NextSemesterStudentTypePlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('자율 예약 설정'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _rightCountController,
          enabled: !_saving && plan.canChange,
          decoration: _decoration('학기 수업권 개수'),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          initialValue: _flexDurationMinutes,
          decoration: _decoration('수업 길이'),
          items: _durationItems(),
          onChanged: _saving || !plan.canChange
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _flexDurationMinutes = value);
                  }
                },
        ),
        const SizedBox(height: 10),
        _infoCard(
          '자율 예약 학생은 정규 시간표 없이 발급된 수업권으로 담당 선생님의 예약 가능 시간에 수업을 예약합니다.',
        ),
      ],
    );
  }

  Widget _buildRegularSettings(NextSemesterStudentTypePlan plan) {
    if (plan.regularScheduleCount > 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('정규 수업 설정'),
          const SizedBox(height: 8),
          _infoCard(
            '현재 등록된 정규 일정 ${plan.regularScheduleCount}개를 다음 학기에도 사용합니다. '
            '수강 형태를 저장한 뒤 정규 일정 관리에서 다음 학기 일정을 확인할 수 있습니다.',
          ),
        ],
      );
    }

    if (plan.teacherId == null || !plan.teacherAssignmentCoversSemester) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('정규 수업 설정'),
          const SizedBox(height: 8),
          _warningCard(
            '정규 학생으로 전환하려면 다음 학기 전체 기간의 담당 선생님이 먼저 지정되어 있어야 합니다. '
            '담당 선생님 변경에서 ${DateFormat('yyyy.MM.dd').format(plan.nextSemesterStartsOn)}부터 적용되도록 설정해주세요.',
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('정규 수업 설정'),
        const SizedBox(height: 6),
        Text(
          '담당 선생님: ${plan.teacherName ?? '확인 필요'}',
          style: forestringTextStyle.copyWith(
            color: secondaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (_workHours.isNotEmpty) ...[
          const SizedBox(height: 8),
          _infoCard('다음 학기 시작일 기준 근무시간\n${_workHoursLabel()}'),
        ],
        const SizedBox(height: 12),
        ...List.generate(
          _regularSchedules.length,
          (index) => _regularScheduleCard(index, plan),
        ),
        OutlinedButton.icon(
          onPressed: _saving || !plan.canChange
              ? null
              : () {
                  final first = _workHours.isEmpty ? null : _workHours.first;
                  setState(() {
                    _regularSchedules.add(
                      _NextRegularScheduleDraft(
                        weekday: first?.weekday ?? 1,
                        startMinutes: first?.startMinutes ?? 600,
                        durationMinutes: 30,
                      ),
                    );
                  });
                },
          icon: const Icon(Icons.add),
          label: const Text('정규 수업 추가'),
        ),
      ],
    );
  }

  Widget _regularScheduleCard(
    int index,
    NextSemesterStudentTypePlan plan,
  ) {
    final draft = _regularSchedules[index];
    final availableWeekdays = _workHours
        .map((window) => window.weekday)
        .toSet()
        .toList()
      ..sort();
    if (!availableWeekdays.contains(draft.weekday)) {
      availableWeekdays.add(draft.weekday);
      availableWeekdays.sort();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: primaryColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: draft.weekday,
                    decoration: _decoration('요일'),
                    items: availableWeekdays
                        .map(
                          (weekday) => DropdownMenuItem(
                            value: weekday,
                            child: Text(_weekdayLabel(weekday)),
                          ),
                        )
                        .toList(),
                    onChanged: _saving || !plan.canChange
                        ? null
                        : (value) {
                            if (value == null) return;
                            final firstForDay = _workHours
                                .where((window) => window.weekday == value)
                                .firstOrNull;
                            setState(() {
                              draft.weekday = value;
                              if (firstForDay != null) {
                                draft.startMinutes = firstForDay.startMinutes;
                              }
                            });
                          },
                  ),
                ),
                if (_regularSchedules.length > 1) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '삭제',
                    onPressed: _saving || !plan.canChange
                        ? null
                        : () => setState(
                              () => _regularSchedules.removeAt(index),
                            ),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving || !plan.canChange
                        ? null
                        : () => _pickTime(draft),
                    icon: const Icon(Icons.access_time),
                    label: Text(_formatMinutes(draft.startMinutes)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: draft.durationMinutes,
                    decoration: _decoration('수업 길이'),
                    items: _durationItems(),
                    onChanged: _saving || !plan.canChange
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => draft.durationMinutes = value);
                            }
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime(_NextRegularScheduleDraft draft) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: draft.startMinutes ~/ 60,
        minute: draft.startMinutes % 60,
      ),
    );
    if (picked == null || !mounted) return;

    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      draft.startMinutes = minutes;
      _errorMessage = minutes % 15 == 0
          ? null
          : '정규 수업 시작 시간은 15분 단위로 선택해주세요.';
    });
  }

  List<DropdownMenuItem<int>> _durationItems() {
    return const [15, 30, 45, 60, 75, 90]
        .map(
          (minutes) => DropdownMenuItem(
            value: minutes,
            child: Text('$minutes분'),
          ),
        )
        .toList();
  }

  String _workHoursLabel() {
    return _workHours
        .map(
          (window) =>
              '${_weekdayLabel(window.weekday)} '
              '${_formatMinutes(window.startMinutes)}~${_formatMinutes(window.endMinutes)}',
        )
        .join(' · ');
  }

  String _weekdayLabel(int weekday) {
    return switch (weekday) {
      1 => '월요일',
      2 => '화요일',
      3 => '수요일',
      4 => '목요일',
      5 => '금요일',
      6 => '토요일',
      7 => '일요일',
      _ => '요일 확인 필요',
    };
  }

  String _formatMinutes(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: forestringTextStyle.copyWith(
        color: primaryColor,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    );
  }

  Widget _infoCard(String message) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.14)),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: Colors.black87,
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _warningCard(String message) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: forestringTextStyle.copyWith(
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.22)),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: Colors.redAccent,
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}

class _NextRegularScheduleDraft {
  _NextRegularScheduleDraft({
    required this.weekday,
    required this.startMinutes,
    required this.durationMinutes,
  });

  int weekday;
  int startMinutes;
  int durationMinutes;

  String get signature => '$weekday|$startMinutes|$durationMinutes';

  Map<String, dynamic> toJson() {
    final hour = (startMinutes ~/ 60).toString().padLeft(2, '0');
    final minute = (startMinutes % 60).toString().padLeft(2, '0');
    return {
      'weekday': weekday,
      'startTime': '$hour:$minute',
      'durationMinutes': durationMinutes,
    };
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
