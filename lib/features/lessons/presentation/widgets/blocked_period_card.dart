import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';

class BlockedPeriodCard extends StatelessWidget {
  const BlockedPeriodCard({
    super.key,
    required this.period,
    this.onTap,
  });

  final TeacherBlockedPeriod period;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final start = DateFormat('HH:mm').format(period.startsAt);
    final end = DateFormat('HH:mm').format(period.endsAt);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: personalScheduleColor.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: personalScheduleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${period.startsAt.month}월',
                      style: forestringTextStyle.copyWith(fontSize: 12),
                    ),
                    Text(
                      '${period.startsAt.day}',
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
                      '개인 일정',
                      style: forestringTextStyle.copyWith(
                        color: personalScheduleColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$start ~ $end',
                      style: forestringTextStyle.copyWith(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
