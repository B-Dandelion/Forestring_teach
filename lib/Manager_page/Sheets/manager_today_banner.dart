import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Data/constant.dart';

class ManagerTodayBanner extends StatelessWidget {
  final DateTime selectedDate;

  const ManagerTodayBanner({
    required this.selectedDate,
    super.key
  });



  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
        fontFamily: 'ELAND',
        fontWeight: FontWeight.w300,
        color: Colors.white
    );

    return Container(
        color: PRIMARY_COLOR,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${selectedDate.year}년 ${selectedDate.month}월 ${selectedDate.day}일',
                  style: textStyle,
                ),
              ],
            )
        )
    );
  }
}
