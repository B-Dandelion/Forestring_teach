import 'package:forestring_teacher_2/Data/constant.dart';
import 'package:flutter/material.dart';

class ScheduleCard extends StatelessWidget {
  final int startTime;
  final int endTime;
  final int month;
  final int date;
  final String studentID;
  final String teacher;

  const ScheduleCard({
    required this.startTime,
    required this.endTime,
    required this.month,
    required this.date,
    required this.studentID,
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
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Date(month: month, date: date),
                  const SizedBox(width: 16.0),
                  _Time(startTime: startTime, endTime: endTime ),
                  const SizedBox(width: 15.0),
                  _Content(studentID: studentID, teacher: teacher),
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
          )
        ]);
  }
}

class _Time extends StatelessWidget {
  final int startTime;
  final int endTime;


  const _Time({
    required this.startTime,
    required this.endTime,
  });

  @override
  Widget build(BuildContext context) {
    int sT1 = startTime~/100;
    int sT2 = startTime%100;
    int eT1 = endTime~/100;
    int eT2 = endTime%100%60;

    const textStyle = TextStyle(
      fontFamily: 'ELAND',
      fontWeight: FontWeight.w300,
      color: Colors.black,
      fontSize: 13.0,
    );

    return Column(children: [
      Text(
        '${sT1.toString().padLeft(2,'0')}:${sT2.toString().padLeft(2,'0')}',
        style: textStyle,
      ),
      Text('~ ${eT1.toString().padLeft(2,'0')}:${eT2.toString().padLeft(2,'0')}',
          style: textStyle.copyWith(fontSize: 11.0))
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
      fontSize: 18.0,
    );

    return Expanded(
      child:
      Text(
        '$studentID / $teacher 선생님',
        style: textStyle,
      ),
    );
  }
}
