import 'package:forestring_teacher_2/Data/constant.dart';
import 'package:flutter/material.dart';

class Semestercard extends StatelessWidget {
  final int year;
  final int month;
  final DateTime startTime;
  final DateTime endTime;

  const Semestercard({
    required this.year,
    required this.month,
    required this.startTime,
    required this.endTime,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          border: Border.all(
            width: 1.5,
            color: PRIMARY_COLOR,
          ),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _month(year: year, month: month),
                  const SizedBox(width: 16),
                  _Time(startTime: startTime, endTime: endTime),
                ],
              ),
            ))
    );
  }
}
class _month extends StatelessWidget {
  final int month;
  final int year;

  const _month({
    required this.month,
    required this.year
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontFamily: 'ELAND',
      fontWeight: FontWeight.w500,
      color: PRIMARY_COLOR,
      fontSize: 20.0,
    );

    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${year.toString()}년 ${month.toString()}월 학기',
            style: textStyle,
          ),
        ]);
  }
}
class _Time extends StatelessWidget {
  final DateTime startTime;
  final DateTime endTime;

  const _Time({
    required this.startTime,
    required this.endTime,
  });

  @override
  Widget build(BuildContext context) {

    const textStyle = TextStyle(
      fontFamily: 'ELAND',
      fontWeight: FontWeight.w300,
      color: Colors.black,
      fontSize: 18.0,
    );

    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${startTime.year}.${startTime.month}.${startTime.day} ~ '
                '${endTime.year}.${endTime.month}.${endTime.day}',
            style: textStyle,
      ),
    ]);
  }
}