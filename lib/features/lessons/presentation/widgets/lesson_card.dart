import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';

class LessonCard extends StatelessWidget {
  const LessonCard({
    super.key,
    required this.lesson,
    required this.personName,
    this.onTap,
  });

  final Lesson lesson;
  final String personName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final start = DateFormat('HH:mm').format(lesson.startsAt);
    final end = DateFormat('HH:mm').format(lesson.endsAt);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: lesson.isCanceled
                  ? Colors.black12
                  : primaryColor.withOpacity(0.25),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: lesson.isCanceled
                      ? Colors.black12
                      : primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${lesson.startsAt.month}월',
                      style: forestringTextStyle.copyWith(
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${lesson.startsAt.day}',
                      style: forestringTextStyle.copyWith(
                        fontSize: 21,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      personName,
                      style: forestringTextStyle.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        decoration: lesson.isCanceled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$start ~ $end · ${lesson.type.label}',
                      style: forestringTextStyle.copyWith(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (lesson.isCanceled)
                Text(
                  '취소',
                  style: forestringTextStyle.copyWith(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (lesson.isRescheduled)
                Text(
                  '변경',
                  style: forestringTextStyle.copyWith(
                    color: secondaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.black38,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
