import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';

Future<void> showLessonInfoDialog({
  required BuildContext context,
  required Lesson lesson,
}) async {
  final start = lesson.startsAt;
  final end = lesson.endsAt;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          '수업 정보',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lesson.studentName ?? '학생',
              style: forestringTextStyle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '날짜  ${DateFormat('yyyy년 M월 d일').format(start)}',
              style: forestringTextStyle,
            ),
            const SizedBox(height: 8),
            Text(
              '시간  ${DateFormat('HH:mm').format(start)} ~ ${DateFormat('HH:mm').format(end)}',
              style: forestringTextStyle,
            ),
            const SizedBox(height: 8),
            Text(
              '수업 길이  ${lesson.durationMinutes}분',
              style: forestringTextStyle,
            ),
            const SizedBox(height: 8),
            Text(
              '수업 종류  ${lesson.displayTypeLabel}',
              style: forestringTextStyle,
            ),
            if (lesson.changeBadgeLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                lesson.changeBadgeLabel!,
                style: forestringTextStyle.copyWith(
                  color: secondaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
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
}
