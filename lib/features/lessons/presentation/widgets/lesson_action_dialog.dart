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

          Future<void> editDate() async {
            if (isSaving) return;
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
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
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
                    style: forestringTextStyle.copyWith(
                      color: Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _ScheduleValueCard(
                          label: '날짜',
                          value: DateFormat('yyyy.MM.dd').format(selectedDate),
                          icon: Icons.calendar_today_outlined,
                          onTap: isSaving ? null : editDate,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ScheduleValueCard(
                          label: '시간',
                          value: _formatLessonTime(selectedTime),
                          icon: Icons.access_time_rounded,
                          onTap: isSaving ? null : editTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: selectedDuration,
                    decoration: InputDecoration(
                      labelText: '수업 길이',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: durations
                        .map(
                          (minutes) => DropdownMenuItem<int>(
                            value: minutes,
                            child: Text(
                              '$minutes분',
                              style: forestringTextStyle.copyWith(fontSize: 15),
                            ),
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
              const Spacer(),
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('닫기'),
              ),
              FilledButton(
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
                style: FilledButton.styleFrom(backgroundColor: primaryColor),
                child: Text(isSaving ? '변경 중...' : '일정 변경'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _ScheduleValueCard extends StatelessWidget {
  const _ScheduleValueCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primaryColor.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: forestringTextStyle.copyWith(
                          color: Colors.black,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 20, color: primaryColor),
            ],
          ),
        ),
      ),
    );
  }
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
