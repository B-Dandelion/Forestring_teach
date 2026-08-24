import 'package:flutter/material.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';

class BlockedPeriodCalendarAppointment extends StatelessWidget {
  const BlockedPeriodCalendarAppointment({
    super.key,
    required this.period,
  });

  final TeacherBlockedPeriod period;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: personalScheduleColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          '개인 일정',
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'ELAND',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
      ),
    );
  }
}
