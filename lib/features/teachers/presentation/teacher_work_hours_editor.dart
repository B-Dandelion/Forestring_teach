import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../data/teacher_repository.dart';

class TeacherWorkHourDraft {
  const TeacherWorkHourDraft({
    this.weekday = 1,
    this.startTime = const TimeOfDay(hour: 9, minute: 0),
    this.endTime = const TimeOfDay(hour: 18, minute: 0),
  });

  final int weekday;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  TeacherWorkHourDraft copyWith({
    int? weekday,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) {
    return TeacherWorkHourDraft(
      weekday: weekday ?? this.weekday,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  TeacherWorkHourInput toInput() {
    return TeacherWorkHourInput(
      weekday: weekday,
      startTime: formatTeacherWorkTime(startTime),
      endTime: formatTeacherWorkTime(endTime),
    );
  }
}

class TeacherWorkHoursEditor extends StatelessWidget {
  const TeacherWorkHoursEditor({
    super.key,
    required this.values,
    required this.onChanged,
    this.enabled = true,
  });

  final List<TeacherWorkHourDraft> values;
  final ValueChanged<List<TeacherWorkHourDraft>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...List.generate(
          values.length,
          (index) => _workHourCard(context, index),
        ),
        OutlinedButton.icon(
          onPressed: enabled ? _addWorkHour : null,
          icon: const Icon(Icons.add),
          label: const Text('근무시간 추가'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            side: const BorderSide(color: primaryColor),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _workHourCard(BuildContext context, int index) {
    final value = values[index];

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
                    value: value.weekday,
                    decoration: _decoration('요일'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('월요일')),
                      DropdownMenuItem(value: 2, child: Text('화요일')),
                      DropdownMenuItem(value: 3, child: Text('수요일')),
                      DropdownMenuItem(value: 4, child: Text('목요일')),
                      DropdownMenuItem(value: 5, child: Text('금요일')),
                      DropdownMenuItem(value: 6, child: Text('토요일')),
                      DropdownMenuItem(value: 7, child: Text('일요일')),
                    ],
                    onChanged: !enabled
                        ? null
                        : (weekday) {
                            if (weekday != null) {
                              _replaceAt(
                                index,
                                value.copyWith(weekday: weekday),
                              );
                            }
                          },
                  ),
                ),
                if (values.length > 1) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '삭제',
                    onPressed: enabled ? () => _removeAt(index) : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _timeButton(
                    context: context,
                    label: '시작',
                    value: value.startTime,
                    onSelected: (time) {
                      _replaceAt(index, value.copyWith(startTime: time));
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('~'),
                ),
                Expanded(
                  child: _timeButton(
                    context: context,
                    label: '종료',
                    value: value.endTime,
                    onSelected: (time) {
                      _replaceAt(index, value.copyWith(endTime: time));
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

  Widget _timeButton({
    required BuildContext context,
    required String label,
    required TimeOfDay value,
    required ValueChanged<TimeOfDay> onSelected,
  }) {
    return OutlinedButton(
      onPressed: !enabled
          ? null
          : () async {
              final picked = await showTeacherWorkTimePicker(
                context: context,
                title: '$label 시간',
                initialTime: value,
              );
              if (picked != null) {
                onSelected(picked);
              }
            },
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatTeacherWorkTime(value),
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _addWorkHour() {
    final usedWeekdays = values.map((value) => value.weekday).toSet();
    var weekday = 1;
    for (var candidate = 1; candidate <= 7; candidate += 1) {
      if (!usedWeekdays.contains(candidate)) {
        weekday = candidate;
        break;
      }
    }

    onChanged([
      ...values,
      TeacherWorkHourDraft(weekday: weekday),
    ]);
  }

  void _replaceAt(int index, TeacherWorkHourDraft value) {
    final updated = List<TeacherWorkHourDraft>.of(values);
    updated[index] = value;
    onChanged(updated);
  }

  void _removeAt(int index) {
    final updated = List<TeacherWorkHourDraft>.of(values)..removeAt(index);
    onChanged(updated);
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );
  }
}

Future<TimeOfDay?> showTeacherWorkTimePicker({
  required BuildContext context,
  required String title,
  required TimeOfDay initialTime,
}) async {
  var selected = TimeOfDay(
    hour: initialTime.hour,
    minute: initialTime.minute - (initialTime.minute % 15),
  );

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: neutralIvory,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: SizedBox(
          height: 330,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: forestringTextStyle.copyWith(
                          color: primaryColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('취소'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(selected),
                      child: const Text('선택'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  minuteInterval: 15,
                  initialDateTime: DateTime(
                    2000,
                    1,
                    1,
                    selected.hour,
                    selected.minute,
                  ),
                  onDateTimeChanged: (value) {
                    selected = TimeOfDay(
                      hour: value.hour,
                      minute: value.minute,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String? validateTeacherWorkHours(List<TeacherWorkHourDraft> values) {
  if (values.isEmpty) {
    return '근무시간을 한 개 이상 등록해주세요.';
  }

  final byWeekday = <int, List<TeacherWorkHourDraft>>{};
  for (final value in values) {
    final start = _minutes(value.startTime);
    final end = _minutes(value.endTime);
    if (start >= end) {
      return '${teacherWeekdayLabel(value.weekday)}요일의 종료시간은 시작시간보다 뒤여야 합니다.';
    }
    byWeekday.putIfAbsent(value.weekday, () => []).add(value);
  }

  for (final entry in byWeekday.entries) {
    final ranges = List<TeacherWorkHourDraft>.of(entry.value)
      ..sort(
        (a, b) => _minutes(a.startTime).compareTo(_minutes(b.startTime)),
      );
    for (var index = 1; index < ranges.length; index += 1) {
      if (_minutes(ranges[index].startTime) <
          _minutes(ranges[index - 1].endTime)) {
        return '${teacherWeekdayLabel(entry.key)}요일에 서로 겹치는 근무시간이 있습니다.';
      }
    }
  }

  return null;
}

String formatTeacherWorkTime(TimeOfDay value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String teacherWeekdayLabel(int weekday) {
  return switch (weekday) {
    1 => '월',
    2 => '화',
    3 => '수',
    4 => '목',
    5 => '금',
    6 => '토',
    7 => '일',
    _ => '-',
  };
}

int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;
