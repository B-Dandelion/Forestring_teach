import 'package:flutter/material.dart';
import 'new_constant.dart';
class LessonCard_main extends StatelessWidget {
  final DateTime startTime;
  final String lessonID;
  final int month;
  final int date;
  final String student;
  final String teacher;

  const LessonCard_main({
    required this.startTime,
    required this.lessonID,
    required this.month,
    required this.date,
    required this.student,
    required this.teacher,
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
            padding: const EdgeInsets.all(13.0),
            child: IntrinsicHeight(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Date(month: month, date: date),
                  const SizedBox(width: 16.0),
                  _Time(startTime: startTime),
                  const SizedBox(width: 15.0),
                  // Expanded(child: _Content(studentID: student, teacher: teacher)),
                  _Content(studentID: student, teacher: teacher),
                ],
              ),
            )));
  }
}

class _Date extends StatelessWidget {
  final int month;
  final int date;

  const _Date({
    required this.month,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontFamily: 'OpenSans',
      fontWeight: FontWeight.w500,
      color: PRIMARY_COLOR,
      fontSize: 20.0,
    );

    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            month.toString(),
            style: textStyle,
          ),
          const Text(
            '/',
            style: textStyle,
          ),
          Text(
            date.toString(),
            style: textStyle,
          ),
        ]);
  }
}
class _Time extends StatelessWidget {
  final DateTime startTime;

  const _Time({
    required this.startTime,
  });

  @override
  Widget build(BuildContext context) {

    const textStyle = TextStyle(
      fontFamily: 'ELAND',
      fontWeight: FontWeight.w300,
      color: Colors.black,
      fontSize: 13.0,
    );

    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(
        '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
        style: textStyle,
      ),
      Text(
          '~ ${startTime.add(const Duration(minutes: 30)).hour.toString().padLeft(2, '0')}:${startTime.add(const Duration(minutes: 30)).minute.toString().padLeft(2, '0')}',
          style: textStyle.copyWith(fontSize: 10.0))
    ]);
  }
}
class _Content extends StatelessWidget {
  final String studentID;
  final String teacher;

  const _Content({
    required this.studentID,
    required this.teacher,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontFamily: 'ELAND',
      fontWeight: FontWeight.w300,
      color: Colors.black,
      fontSize: 16.0,
    );

    return Expanded(
      child: Text(
        '$studentID / $teacher 선생님',
        style: textStyle,
      ),
    );
  }
}
