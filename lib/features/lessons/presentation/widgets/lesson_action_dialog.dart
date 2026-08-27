import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';
import '../lesson_controller.dart';
import 'lesson_activity_detail_sheet.dart';
import 'lesson_time_slot_picker.dart';

Future<void> showLessonActionDialog({
  required BuildContext context,
  required Lesson lesson,
  required LessonController controller,
}) async {
  if (lesson.isCanceled) {
    await showLessonActivityDetailSheet(
      context: context,
      lesson: lesson,
    );
    return;
  }

  if (lesson.isRescheduled ||
      lesson.type == LessonType.makeup ||
      lesson.type == LessonType.flex) {
    final editRequested = await showLessonActivityDetailSheet(
      context: context,
      lesson: lesson,
      allowEdit: true,
    );
    if (!editRequested || !context.mounted) {
      return;
    }
  }

  final hostContext = context;
  var selectedDate = DateTime(
    lesson.startsAt.year,
    lesson.startsAt.month,
    lesson.startsAt.day,
  );
  var selectedTime = TimeOfDay.fromDateTime(lesson.startsAt);
  var selectedDuration = lesson.durationMinutes;
  var isSaving = false;

  final durations = <int>{15, 30, 45, 60, 75, 90, selectedDuration}
      .where((value) => value > 0 && value <= 720)
      .toList()
    ..sort();

  await showDialog<void>(
    context: hostContext,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogBodyContext, setState) {
          const canEdit = true;

          Future<void> editTime() async {
            if (!canEdit || isSaving) return;
            final picked = await showLessonTimeSlotPicker(
              context: dialogBodyContext,
              lesson: lesson,
              controller: controller,
              selectedDate: selectedDate,
              initialTime: selectedTime,
              durationMinutes: selectedDuration,
            );
            if (picked != null) {
              setState(() => selectedTime = picked);
            }
          }

          return AlertDialog(
            title: Text(
              '일정 변경',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${lesson.studentName ?? '학생'} · ${lesson.displayTypeLabel}',
                    style: forestringTextStyle.copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '날짜  ${DateFormat('yy.MM.dd').format(selectedDate)}',
                          style: forestringTextStyle,
                        ),
                      ),
                      IconButton(
                        onPressed: !isSaving
                            ? () async {
                                final picked = await showDatePicker(
                                  context: dialogBodyContext,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2024, 1, 1),
                                  lastDate: DateTime(2035, 12, 31),
                                );
                                if (picked != null) {
                                  setState(() => selectedDate = picked);
                                }
                              }
                            : null,
                        icon: const Icon(Icons.calendar_today),
                      ),
                    ],
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: !isSaving ? editTime : null,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '시간  ${_formatLessonTime(selectedTime)}',
                                style: forestringTextStyle,
                              ),
                            ),
                            IconButton(
                              onPressed: !isSaving ? editTime : null,
                              icon: const Icon(Icons.access_time_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedDuration,
                    decoration: const InputDecoration(
                      labelText: '수업 길이',
                      border: OutlineInputBorder(),
                    ),
                    items: durations
                        .map(
                          (minutes) => DropdownMenuItem<int>(
                            value: minutes,
                            child: Text('$minutes분'),
                          ),
                        )
                        .toList(),
                    onChanged: !isSaving
                        ? (value) {
                            if (value != null) {
                              setState(() => selectedDuration = value);
                            }
                          }
                        : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final confirmed = await _confirmCancel(
                          dialogBodyContext,
                        );
                        if (!confirmed || !dialogBodyContext.mounted) {
                          return;
                        }

                        setState(() => isSaving = true);
                        final ok = await controller.cancelLesson(
                          lesson,
                          reason: '앱에서 수업 취소',
                        );

                        if (!dialogBodyContext.mounted) {
                          return;
                        }

                        if (ok) {
                          Navigator.of(dialogContext).pop();
                          if (hostContext.mounted) {
                            _showMessage(hostContext, '수업이 취소되었습니다.');
                          }
                        } else {
                          setState(() => isSaving = false);
                          if (hostContext.mounted) {
                            _showMessage(
                              hostContext,
                              controller.errorMessage ?? '수업을 취소하지 못했습니다.',
                            );
                          }
                        }
                      },
                child: const Text(
                  '수업 취소',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('닫기'),
              ),
              TextButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final startsAt = DateTime(
                          selectedDate.year,
                          selectedDate.month,
                          selectedDate.day,
                          selectedTime.hour,
                          selectedTime.minute,
                        );

                        setState(() => isSaving = true);

                        var result = await controller.updateLessonOnce(
                          lesson: lesson,
                          startsAt: startsAt,
                          durationMinutes: selectedDuration,
                          reason: '앱에서 수업 1회 수정',
                        );

                        if (!dialogBodyContext.mounted) {
                          return;
                        }

                        if (result == null) {
                          setState(() => isSaving = false);
                          if (hostContext.mounted) {
                            _showMessage(
                              hostContext,
                              controller.errorMessage ?? '일정을 변경하지 못했습니다.',
                            );
                          }
                          return;
                        }

                        if (result.requiresConfirmation) {
                          final confirmWarnings = await _confirmWarnings(
                            dialogBodyContext,
                            result.warningCodes,
                          );

                          if (!confirmWarnings ||
                              !dialogBodyContext.mounted) {
                            setState(() => isSaving = false);
                            return;
                          }

                          result = await controller.updateLessonOnce(
                            lesson: lesson,
                            startsAt: startsAt,
                            durationMinutes: selectedDuration,
                            confirmWarnings: true,
                            reason: '앱에서 수업 1회 수정',
                          );
                        }

                        if (!dialogBodyContext.mounted) {
                          return;
                        }

                        if (result == null || result.requiresConfirmation) {
                          setState(() => isSaving = false);
                          if (hostContext.mounted) {
                            _showMessage(
                              hostContext,
                              controller.errorMessage ?? '일정을 변경하지 못했습니다.',
                            );
                          }
                          return;
                        }

                        Navigator.of(dialogContext).pop();
                        if (hostContext.mounted) {
                          _showMessage(
                            hostContext,
                            result.changed
                                ? '일정이 변경되었습니다.'
                                : '변경된 내용이 없습니다.',
                          );
                        }
                      },
                child: Text(
                  isSaving ? '변경 중...' : '일정 변경',
                  style: const TextStyle(color: primaryColor),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

String _formatLessonTime(TimeOfDay value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

Future<bool> _confirmCancel(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('수업 취소'),
          content: const Text('이 수업을 취소하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('아니요'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                '취소하기',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> _confirmWarnings(
  BuildContext context,
  List<String> warningCodes,
) async {
  final messages = warningCodes.map((code) {
    return switch (code) {
      'FORESTRING_OUTSIDE_WORK_HOURS' => '선생님 근무시간 밖입니다.',
      'FORESTRING_OVERLAPS_BLOCKED_PERIOD' => '예약 불가 시간과 겹칩니다.',
      'FORESTRING_NONSTANDARD_DURATION' => '권장 수업 길이(15/30/60분)가 아닙니다.',
      _ => code,
    };
  }).join('\n');

  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('확인이 필요합니다'),
          content: Text('$messages\n\n그래도 변경하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('돌아가기'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('변경하기'),
            ),
          ],
        ),
      ) ??
      false;
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
