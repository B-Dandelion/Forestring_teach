import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';

Future<void> showBlockedPeriodInfoDialog({
  required BuildContext context,
  required TeacherBlockedPeriod period,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          period.displayLabel,
          style: forestringTextStyle.copyWith(
            color: personalScheduleColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              period.teacherName == null
                  ? '선생님'
                  : '${period.teacherName} 선생님',
              style: forestringTextStyle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _rangeText(period),
              style: forestringTextStyle,
            ),
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

String _rangeText(TeacherBlockedPeriod period) {
  final sameDate = period.startsAt.year == period.endsAt.year &&
      period.startsAt.month == period.endsAt.month &&
      period.startsAt.day == period.endsAt.day;

  if (sameDate) {
    return '일시  ${DateFormat('yyyy년 M월 d일 HH:mm').format(period.startsAt)}'
        ' ~ ${DateFormat('HH:mm').format(period.endsAt)}';
  }

  return '시작  ${DateFormat('yyyy년 M월 d일 HH:mm').format(period.startsAt)}\n'
      '종료  ${DateFormat('yyyy년 M월 d일 HH:mm').format(period.endsAt)}';
}
