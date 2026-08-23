import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';
import '../lesson_controller.dart';

Future<void> showLessonActionDialog({
  required BuildContext context,
  required Lesson lesson,
  required LessonController controller,
}) async {
  DateTime selectedDate = DateTime(
    lesson.startsAt.year,
    lesson.startsAt.month,
    lesson.startsAt.day,
  );
  TimeOfDay selectedTime = TimeOfDay.fromDateTime(
    lesson.startsAt,
  );
  int selectedDuration = lesson.durationMinutes;
  bool isSaving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final canEdit = !lesson.isCanceled;

          return AlertDialog(
            title: Text(
              lesson.isCanceled ? '취소된 수업' : '수업 수정',
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
                    '${lesson.studentName ?? '학생'} · ${lesson.type.label}',
                    style: forestringTextStyle.copyWith(
                      fontSize: 17,
                    ),
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
                        onPressed: canEdit && !isSaving
                            ? () async {
                                final picked = await showDatePicker(
                                  context: context,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '시간  ${selectedTime.format(context)}',
                          style: forestringTextStyle,
                        ),
                      ),
                      IconButton(
                        onPressed: canEdit && !isSaving
                            ? () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: selectedTime,
                                );
                                if (picked != null) {
                                  setState(() => selectedTime = picked);
                                }
                              }
                            : null,
                        icon: const Icon(Icons.access_time_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedDuration,
                    decoration: const InputDecoration(
                      labelText: '수업 길이',
                      border: OutlineInputBorder(),
                    ),
                    items: const [15, 30, 45, 60, 75, 90]
                        .map(
                          (minutes) => DropdownMenuItem<int>(
                            value: minutes,
                            child: Text('$minutes분'),
                          ),
                        )
                        .toList(),
                    onChanged: canEdit && !isSaving
                        ? (value) {
                            if (value != null) {
                              setState(() => selectedDuration = value);
                            }
                          }
                        : null,
                  ),
                  if (lesson.isCanceled) ...[
                    const SizedBox(height: 14),
                    Text(
                      lesson.lessonRightId == null
                          ? '이 수업에는 다시 예약할 수 있는 수업권이 없습니다.'
                          : '취소로 반환된 수업권을 사용해 보강 시간을 예약할 수 있습니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (!lesson.isCanceled)
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final confirmed = await _confirmCancel(
                            context,
                          );
                          if (!confirmed || !context.mounted) {
                            return;
                          }

                          setState(() => isSaving = true);
                          final ok = await controller.cancelLesson(
                            lesson,
                            reason: '앱에서 수업 취소',
                          );

                          if (!context.mounted) {
                            return;
                          }

                          if (ok) {
                            Navigator.of(dialogContext).pop();
                            _showMessage(
                              context,
                              '수업이 취소되었습니다.',
                            );
                          } else {
                            setState(() => isSaving = false);
                            _showMessage(
                              context,
                              controller.errorMessage ??
                                  '수업을 취소하지 못했습니다.',
                            );
                          }
                        },
                  child: const Text(
                    '수업 취소',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              if (lesson.isCanceled && lesson.lessonRightId != null)
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          Navigator.of(dialogContext).pop();
                          await showMakeupBookingDialog(
                            context: context,
                            lesson: lesson,
                            controller: controller,
                          );
                        },
                  child: const Text('보강 예약'),
                ),
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('닫기'),
              ),
              if (!lesson.isCanceled)
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

                          if (!context.mounted) {
                            return;
                          }

                          if (result == null) {
                            setState(() => isSaving = false);
                            _showMessage(
                              context,
                              controller.errorMessage ??
                                  '수업을 수정하지 못했습니다.',
                            );
                            return;
                          }

                          if (result.requiresConfirmation) {
                            final confirmWarnings =
                                await _confirmWarnings(
                              context,
                              result.warningCodes,
                            );

                            if (!confirmWarnings || !context.mounted) {
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

                          if (!context.mounted) {
                            return;
                          }

                          if (result == null ||
                              result.requiresConfirmation) {
                            setState(() => isSaving = false);
                            _showMessage(
                              context,
                              controller.errorMessage ??
                                  '수업을 수정하지 못했습니다.',
                            );
                            return;
                          }

                          Navigator.of(dialogContext).pop();
                          _showMessage(
                            context,
                            result.changed
                                ? '수업이 수정되었습니다.'
                                : '변경된 내용이 없습니다.',
                          );
                        },
                  child: Text(
                    isSaving ? '저장 중...' : '저장',
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

Future<void> showMakeupBookingDialog({
  required BuildContext context,
  required Lesson lesson,
  required LessonController controller,
}) async {
  DateTime selectedDate = DateTime.now();
  List<LessonBookingOption> options = const [];
  bool isLoading = true;
  String? errorMessage;

  Future<void> loadOptions(
    void Function(void Function()) setState,
  ) async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loaded = await controller.getBookingOptions(
        lesson: lesson,
        selectedDate: selectedDate,
      );
      setState(() {
        options = loaded;
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        errorMessage = error.toString();
        isLoading = false;
      });
    }
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      var firstBuild = true;

      return StatefulBuilder(
        builder: (context, setState) {
          if (firstBuild) {
            firstBuild = false;
            Future.microtask(() => loadOptions(setState));
          }

          return AlertDialog(
            title: Text(
              '보강 예약',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('yyyy년 M월 d일').format(selectedDate),
                          style: forestringTextStyle,
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 1),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 180),
                            ),
                          );
                          if (picked != null) {
                            selectedDate = picked;
                            await loadOptions(setState);
                          }
                        },
                        icon: const Icon(Icons.calendar_today),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (errorMessage != null)
                    Text(
                      errorMessage!,
                      style: forestringTextStyle.copyWith(
                        color: Colors.redAccent,
                      ),
                    )
                  else if (options.isEmpty)
                    Text(
                      '예약 가능한 시간이 없습니다.',
                      style: forestringTextStyle,
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 330),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final option = options[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${DateFormat('HH:mm').format(option.startsAt)} '
                              '~ ${DateFormat('HH:mm').format(option.endsAt)}',
                              style: forestringTextStyle.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              final ok = await controller.bookLessonRight(
                                lesson: lesson,
                                option: option,
                              );

                              if (!context.mounted) {
                                return;
                              }

                              if (ok) {
                                Navigator.of(dialogContext).pop();
                                _showMessage(
                                  context,
                                  '보강 수업이 예약되었습니다.',
                                );
                              } else {
                                _showMessage(
                                  context,
                                  controller.errorMessage ??
                                      '보강 수업을 예약하지 못했습니다.',
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('닫기'),
              ),
            ],
          );
        },
      );
    },
  );
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
          content: Text(
            '$messages\n\n그래도 변경하시겠습니까?',
          ),
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
