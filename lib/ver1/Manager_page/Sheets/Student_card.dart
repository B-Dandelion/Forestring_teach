import 'package:forestring_teacher_2/ver1/Data/constant.dart';
import 'package:flutter/material.dart';

class StudentCard extends StatelessWidget {
  final String Day;
  final DateTime startTime;
  final DateTime endTime;
  final String id;
  final String teacher;

  const StudentCard({
    required this.Day,
    required this.startTime,
    required this.endTime,
    required this.id,
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
            padding: const EdgeInsets.all(16.0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Day(Day: Day),
                  const SizedBox(width: 16),
                  _Time(startTime: startTime, endTime: endTime),
                  const SizedBox(width: 15.0),
                  _id(studentname: id, teacher: teacher),
                ],
              ),
            ))
    );
  }
}
class _Day extends StatelessWidget {
  final String Day;

  const _Day({
    required this.Day,
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
            Day,
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
      fontSize: 13.0,
    );

    return Column(children: [
      Text(
        '${startTime.hour.toString().padLeft(2,'0')}:${startTime.minute.toString().padLeft(2,'0')}',
        style: textStyle,
      ),
      Text('~ ${endTime.hour.toString().padLeft(2,'0')}:${endTime.minute.toString().padLeft(2,'0')}',
          style: textStyle.copyWith(fontSize: 10.0))
    ]);
  }
}
class _id extends StatelessWidget {
  final String studentname;
  final String teacher;

  const _id({
    required this.teacher,
    required this.studentname,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontFamily: 'ELAND',
      fontWeight: FontWeight.w300,
      color: Colors.black,
      fontSize: 18.0,
    );

    return Expanded(
      child:
      Text(
        '$studentname / $teacher 선생님',
        style: textStyle,
      ),
    );
  }
}
