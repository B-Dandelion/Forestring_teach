import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/lesson_repository.dart';
import '../domain/lesson.dart';

class MakeupLessonCreatePage extends StatefulWidget {
  const MakeupLessonCreatePage({
    super.key,
    required this.profile,
    required this.branches,
    required this.students,
    required this.teachers,
    this.initialBranchId,
    this.initialStudentId,
    this.initialDate,
  });

  final CurrentProfile profile;
  final List<AcademyBranch> branches;
  final List<VisibleStudent> students;
  final List<VisibleTeacher> teachers;
  final String? initialBranchId;
  final String? initialStudentId;
  final DateTime? initialDate;

  @override
  State<MakeupLessonCreatePage> createState() =>
      _MakeupLessonCreatePageState();
}

class _MakeupLessonCreatePageState extends State<MakeupLessonCreatePage> {
  final _repository = LessonRepository();

  String? _branchId;
  String? _studentId;
  String? _teacherId;
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  int _durationMinutes = 30;
  String _reason = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = _dateOnly(
      widget.initialDate ?? DateTime.now().add(const Duration(days: 1)),
    );

    final requestedBranch = widget.profile.isManager
        ? widget.profile.branchId
        : widget.initialBranchId;
    if (requestedBranch != null &&
        widget.branches.any((branch) => branch.id == requestedBranch)) {
      _branchId = requestedBranch;
    } else if (widget.branches.isNotEmpty) {
      _branchId = widget.branches.first.id;
    }

    final requestedStudent = widget.initialStudentId;
    if (requestedStudent != null &&
        _availableStudents.any((student) => student.id == requestedStudent)) {
      _studentId = requestedStudent;
    }

    final teachers = _availableTeachers;
    if (teachers.length == 1) {
      _teacherId = teachers.first.id;
    }
  }

  List<VisibleStudent> get _availableStudents {
    final branchId = _branchId;
    return widget.students
        .where(
          (student) =>
              student.isActive &&
              branchId != null &&
              student.branchId == branchId,
        )
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  List<VisibleTeacher> get _availableTeachers {
    final branchId = _branchId;
    return widget.teachers
        .where(
          (teacher) => branchId != null && teacher.branchId == branchId,
        )
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  AcademyBranch? get _selectedBranch {
    final id = _branchId;
    if (id == null) return null;
    for (final branch in widget.branches) {
      if (branch.id == id) return branch;
    }
    return null;
  }

  void _changeBranch(String? value) {
    if (value == null || value == _branchId) return;
    setState(() {
      _branchId = value;
      _studentId = null;
      _teacherId = null;
      final teachers = _availableTeachers;
      if (teachers.length == 1) {
        _teacherId = teachers.first.id;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _dateOnly(DateTime.now()),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: '보강 수업 날짜',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (picked != null && mounted) {
      setState(() => _date = _dateOnly(picked));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: '보강 수업 시간',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (picked != null && mounted) {
      setState(() => _time = picked);
    }
  }

  Future<void> _submit() async {
    final branchId = _branchId;
    final studentId = _studentId;
    final teacherId = _teacherId;

    if (branchId == null) {
      _message('지점을 선택해주세요.');
      return;
    }
    if (studentId == null) {
      _message('학생을 선택해주세요.');
      return;
    }
    if (teacherId == null) {
      _message('선생님 또는 지점장을 선택해주세요.');
      return;
    }

    final startsAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    if (!startsAt.isAfter(DateTime.now())) {
      _message('현재보다 이후 시간을 선택해주세요.');
      return;
    }

    setState(() => _saving = true);
    try {
      var result = await _repository.createMakeupLesson(
        studentId: studentId,
        teacherId: teacherId,
        startsAt: startsAt,
        durationMinutes: _durationMinutes,
        reason: _reason,
      );

      if (!mounted) return;
      if (result.requiresConfirmation) {
        final confirmed = await _confirmWarnings(result.warningCodes);
        if (!confirmed || !mounted) return;

        result = await _repository.createMakeupLesson(
          studentId: studentId,
          teacherId: teacherId,
          startsAt: startsAt,
          durationMinutes: _durationMinutes,
          confirmWarnings: true,
          reason: _reason,
        );
      }

      if (!mounted) return;
      if (result.changed) {
        Navigator.of(context).pop(true);
      } else {
        _message('보강 수업을 등록하지 못했습니다.');
      }
    } on LessonFailure catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmWarnings(List<String> warningCodes) async {
    final messages = warningCodes.map((code) {
      return switch (code) {
        'FORESTRING_OUTSIDE_WORK_HOURS' => '근무시간 밖의 수업입니다.',
        'FORESTRING_NONSTANDARD_DURATION' =>
          '권장 수업 길이(15/30/60분)가 아닙니다.',
        _ => code,
      };
    }).join('\n');

    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('확인이 필요합니다'),
            content: Text('$messages\n\n그래도 보강 수업을 등록하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('돌아가기'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(backgroundColor: primaryColor),
                child: const Text('등록'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final students = _availableStudents;
    final teachers = _availableTeachers;
    final branch = _selectedBranch;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: const ForestringAppBar(title: '보강 수업 등록'),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                Text(
                  '수업 정보',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '독립 보강 수업을 직접 등록합니다. 휴원, 개인 일정, 기존 수업 충돌은 자동으로 확인됩니다.',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                if (widget.profile.isMaster)
                  DropdownButtonFormField<String>(
                    value: _branchId,
                    decoration: _decoration('지점'),
                    items: widget.branches
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: _saving ? null : _changeBranch,
                  )
                else
                  _FixedField(
                    label: '지점',
                    value: branch?.name ?? '지점 정보 없음',
                    icon: Icons.storefront_outlined,
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: students.any((item) => item.id == _studentId)
                      ? _studentId
                      : null,
                  decoration: _decoration('학생'),
                  items: students
                      .map(
                        (student) => DropdownMenuItem(
                          value: student.id,
                          child: Text(student.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _studentId = value),
                ),
                if (students.isEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    '선택한 지점에 재원 중인 학생이 없습니다.',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black45,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: teachers.any((item) => item.id == _teacherId)
                      ? _teacherId
                      : null,
                  decoration: _decoration('수업 담당자'),
                  items: teachers
                      .map(
                        (teacher) => DropdownMenuItem(
                          value: teacher.id,
                          child: Text(teacher.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _teacherId = value),
                ),
                if (teachers.isEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    '선택한 지점에 수업 가능한 선생님 또는 지점장이 없습니다.',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black45,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  '일정',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _pickDate,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(DateFormat('yyyy.MM.dd').format(_date)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _pickTime,
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(_time.format(context)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _durationMinutes,
                  decoration: _decoration('수업 길이'),
                  items: const [15, 30, 45, 60, 75, 90]
                      .map(
                        (minutes) => DropdownMenuItem(
                          value: minutes,
                          child: Text('$minutes분'),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _durationMinutes = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  enabled: !_saving,
                  maxLength: 100,
                  decoration: _decoration('메모 (선택)'),
                  onChanged: (value) => _reason = value,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add_task_outlined),
                    label: Text(
                      '보강 수업 등록',
                      style: forestringTextStyle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
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

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.22)),
      ),
    );
  }
}

class _FixedField extends StatelessWidget {
  const _FixedField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: forestringTextStyle.copyWith(
                  color: Colors.black45,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: forestringTextStyle),
            ],
          ),
        ],
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
