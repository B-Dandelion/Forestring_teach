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

  factory TeacherWorkHourDraft.fromManaged(
    ManagedTeacherWorkHour workHour,
  ) {
    return TeacherWorkHourDraft(
      weekday: workHour.weekday,
      startTime: parseTeacherWorkTime(workHour.startTime),
      endTime: parseTeacherWorkTime(workHour.endTime),
    );
  }

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

class TeacherWorkTimeRange {
  const TeacherWorkTimeRange({
    required this.startTime,
    required this.endTime,
  });

  final TimeOfDay startTime;
  final TimeOfDay endTime;
}

class TeacherWorkHoursEditor extends StatelessWidget {
  const TeacherWorkHoursEditor({
    super.key,
    required this.values,
    required this.onChanged,
    this.enabled = true,
    this.allowEmpty = false,
  });

  final List<TeacherWorkHourDraft> values;
  final ValueChanged<List<TeacherWorkHourDraft>> onChanged;
  final bool enabled;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (values.isEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              '등록된 근무시간이 없습니다.',
              style: forestringTextStyle.copyWith(color: Colors.black54),
            ),
          ),
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
                if (allowEmpty || values.length > 1) ...[
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
                    onPressed: () => _editTimeRange(
                      context,
                      index,
                      initialEditingStart: true,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Colors.black45,
                  ),
                ),
                Expanded(
                  child: _timeButton(
                    context: context,
                    label: '종료',
                    value: value.endTime,
                    onPressed: () => _editTimeRange(
                      context,
                      index,
                      initialEditingStart: false,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTimeRange(
    BuildContext context,
    int index, {
    required bool initialEditingStart,
  }) async {
    if (!enabled) return;

    final current = values[index];
    final picked = await showTeacherWorkTimeRangePicker(
      context: context,
      initialStartTime: current.startTime,
      initialEndTime: current.endTime,
      initialEditingStart: initialEditingStart,
    );

    if (picked == null) return;

    _replaceAt(
      index,
      current.copyWith(
        startTime: picked.startTime,
        endTime: picked.endTime,
      ),
    );
  }

  Widget _timeButton({
    required BuildContext context,
    required String label,
    required TimeOfDay value,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
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

Future<TeacherWorkTimeRange?> showTeacherWorkTimeRangePicker({
  required BuildContext context,
  required TimeOfDay initialStartTime,
  required TimeOfDay initialEndTime,
  bool initialEditingStart = true,
}) async {
  var startTime = _roundToQuarter(initialStartTime);
  var endTime = _roundToQuarter(initialEndTime);
  var editingStart = initialEditingStart;

  return showModalBottomSheet<TeacherWorkTimeRange>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedTime = editingStart ? startTime : endTime;
          final startMinutes = _minutes(startTime);
          final endMinutes = _minutes(endTime);
          final isValid = startMinutes < endMinutes;
          final durationMinutes = isValid ? endMinutes - startMinutes : 0;

          return SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              decoration: const BoxDecoration(
                color: neutralIvory,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '근무시간 설정',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _timeRangeTarget(
                          label: '시작',
                          value: startTime,
                          selected: editingStart,
                          onTap: () {
                            setSheetState(() => editingStart = true);
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.black45,
                        ),
                      ),
                      Expanded(
                        child: _timeRangeTarget(
                          label: '종료',
                          value: endTime,
                          selected: !editingStart,
                          onTap: () {
                            setSheetState(() => editingStart = false);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: isValid
                        ? Row(
                            key: const ValueKey('duration'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 16,
                                color: Colors.black45,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _durationLabel(durationMinutes),
                                style: forestringTextStyle.copyWith(
                                  color: Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            '종료시간은 시작시간보다 뒤여야 합니다.',
                            key: const ValueKey('error'),
                            style: forestringTextStyle.copyWith(
                              color: Colors.redAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 210,
                    child: CupertinoDatePicker(
                      key: ValueKey(editingStart),
                      mode: CupertinoDatePickerMode.time,
                      use24hFormat: true,
                      minuteInterval: 15,
                      backgroundColor: Colors.transparent,
                      initialDateTime: DateTime(
                        2000,
                        1,
                        1,
                        selectedTime.hour,
                        selectedTime.minute,
                      ),
                      onDateTimeChanged: (value) {
                        final next = TimeOfDay(
                          hour: value.hour,
                          minute: value.minute,
                        );
                        setSheetState(() {
                          if (editingStart) {
                            startTime = next;
                          } else {
                            endTime = next;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: !isValid
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop(
                                TeacherWorkTimeRange(
                                  startTime: startTime,
                                  endTime: endTime,
                                ),
                              );
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            primaryColor.withValues(alpha: 0.2),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('완료'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _timeRangeTarget({
  required String label,
  required TimeOfDay value,
  required bool selected,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? primaryColor.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? primaryColor
                : primaryColor.withValues(alpha: 0.16),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: forestringTextStyle.copyWith(
                color: selected ? primaryColor : Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatTeacherWorkTime(value),
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String? validateTeacherWorkHours(
  List<TeacherWorkHourDraft> values, {
  bool allowEmpty = false,
}) {
  if (values.isEmpty && !allowEmpty) {
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

TimeOfDay parseTeacherWorkTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) {
    return const TimeOfDay(hour: 9, minute: 0);
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return const TimeOfDay(hour: 9, minute: 0);
  }

  return TimeOfDay(hour: hour, minute: minute);
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

TimeOfDay _roundToQuarter(TimeOfDay value) {
  final roundedMinute = value.minute - (value.minute % 15);
  return TimeOfDay(hour: value.hour, minute: roundedMinute);
}

String _durationLabel(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '총 $remainder분';
  if (remainder == 0) return '총 $hours시간';
  return '총 $hours시간 $remainder분';
}

int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;