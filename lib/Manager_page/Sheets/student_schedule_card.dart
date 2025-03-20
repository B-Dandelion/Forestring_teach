import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forestring_teacher_2/Data/constant.dart';
import 'package:forestring_teacher_2/Data/schedule_model.dart';
import 'package:forestring_teacher_2/Manager_page/Sheets/student_modify_sheet.dart';
import 'package:intl/intl.dart';

class student_ScheduleCard extends StatelessWidget {
  final int startTime;
  final int endTime;
  final bool rebook;
  final String studentID;
  final String teacher;
  final DateTime time;

  const student_ScheduleCard({
    required this.startTime,
    required this.endTime,
    required this.rebook,
    required this.studentID,
    required this.teacher,
    required this.time,
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
            padding: const EdgeInsets.all(10.0),
            child: IntrinsicHeight(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Date(month: time.month, date: time.day),
                  const SizedBox(width: 16.0),
                  _Time(startTime: startTime, endTime: endTime),
                  const SizedBox(width: 15.0),
                  _Content(studentID: studentID, teacher: teacher),
                  TextButton(
                      onPressed: () {
                        DateTime currentTime = DateTime.now()
                            .toUtc()
                            .add(const Duration(hours: 9));
                        if (time.isBefore(currentTime)) {
                          showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Container(
                                      child: const Text('지난 수업은 취소할 수 없습니다.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: PRIMARY_COLOR,
                                              fontSize: 15,
                                              fontFamily: 'ELAND',
                                              fontWeight: FontWeight.w300))),
                                );
                              });
                        } else {
                          TextStyle style = const TextStyle(
                              color: Colors.black,
                              fontFamily: 'ELAND',
                              fontWeight: FontWeight.w300);
                          showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Container(
                                      child: Text('취소하기',
                                          style: style.copyWith(
                                              color: PRIMARY_COLOR))),
                                  content: SizedBox(
                                    height: 90,
                                    child: Column(
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            Text(
                                                DateFormat('yyyy년 M월 dd일')
                                                    .format(time)
                                                    .toString(),
                                                style: style.copyWith(
                                                    fontSize: 20)),
                                          ],
                                        ),
                                        Row(
                                          children: <Widget>[
                                            Text(
                                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} '
                                                    '- ${time.add(const Duration(minutes: 30)).hour.toString().padLeft(2, '0')}:${time.add(const Duration(minutes: 30)).minute.toString().padLeft(2, '0')}',
                                                style: style.copyWith(
                                                    fontSize: 15)),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text('정말 취소 하시겠습니까?',
                                            style: style.copyWith(fontSize: 17))
                                      ],
                                    ),
                                  ),
                                  actions: <Widget>[
                                    Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                      children: [
                                        TextButton(
                                            onPressed: () async {
                                              DeletePressed(context);
                                              Navigator.of(context).pop();
                                            },
                                            child: Text('예',
                                                style: style.copyWith(
                                                    color: PRIMARY_COLOR))),
                                        TextButton(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                            },
                                            child: Text('아니요',
                                                style: style.copyWith(
                                                    color: Colors.red)))
                                      ],
                                    ),
                                  ],
                                );
                              });
                        }
                      },
                      child: const Text(
                        '취소하기',
                        style: TextStyle(
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w500,
                            color: Colors.red,
                            fontSize: 10.0),
                      ))
                ],
              ),
            )));
  }

  void DeletePressed(BuildContext context) async {
    try{
      if(rebook == false) {
        var doc = await FirebaseFirestore.instance.collection('Class').doc(Student_id).get();
        var tmp = doc.data()!['class'];
        var TMP = [];
        for(var sche in tmp){
          TMP.add(DateTime(sche.toDate().year, sche.toDate().month,
              sche.toDate().day, sche.toDate().hour, sche.toDate().minute, 0));
        }
        TMP.remove(DateTime(time.year, time.month, time.day,
            time.hour, time.minute, 0));
        await FirebaseFirestore.instance.collection('Class').doc(Student_id).update({'class': TMP});
        // 기존 수업 배열에 있던 것을 삭제함.

        //canceled에 취소된 수업 추가
        doc = await FirebaseFirestore.instance.collection('Class').doc(Student_id).get();
        tmp = doc.data()!['canceled'];
        tmp.add(time);
        await FirebaseFirestore.instance.collection('Class').doc(Student_id).update({'canceled': tmp});
      } else {
        var doc = await FirebaseFirestore.instance.collection('Class').doc(Student_id).get();
        var tmp = doc.data()!['rebooked'];
        var TMP = [];
        for(var sche in tmp){
          TMP.add(DateTime(sche.toDate().year, sche.toDate().month,
              sche.toDate().day, sche.toDate().hour, sche.toDate().minute, 0));
        }
        TMP.remove(DateTime(time.year, time.month, time.day,
            time.hour, time.minute, 0));
        await FirebaseFirestore.instance.collection('Class').doc(Student_id).update({'rebooked': TMP});
        // 기존 수업 배열에 있던 것을 삭제함.
        doc = await FirebaseFirestore.instance.collection('Class').doc(Student_id).get();
        tmp = doc.data()!['canceled'];
        tmp.add(time);
        await FirebaseFirestore.instance.collection('Class').doc(Student_id).update({'canceled': tmp});
      }
    } catch (e) {
      showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Container(
                  child: Text(
                    '오류',
                    style: style.copyWith(
                      color: PRIMARY_COLOR,
                      fontSize: 17,
                    ),
                    textAlign: TextAlign.center,
                  )),
              content: Text('스케줄 정보를 수정하는 과정에서 오류가 발생했습니다',
                  style: style.copyWith(fontSize: 15)),
            );
          });
    }
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
  final int startTime;
  final int endTime;

  const _Time({
    required this.startTime,
    required this.endTime,
  });

  @override
  Widget build(BuildContext context) {
    int sT1 = startTime ~/ 100;
    int sT2 = startTime % 100;
    int eT1 = endTime ~/ 100;
    int eT2 = endTime % 100 % 60;

    const textStyle = TextStyle(
      fontFamily: 'ELAND',
      fontWeight: FontWeight.w300,
      color: Colors.black,
      fontSize: 13.0,
    );

    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(
        '${sT1.toString().padLeft(2, '0')}:${sT2.toString().padLeft(2, '0')}',
        style: textStyle,
      ),
      Text(
          '~ ${eT1.toString().padLeft(2, '0')}:${eT2.toString().padLeft(2, '0')}',
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
Future<void> myschedule(BuildContext context) async {
  List<ScheduleModel> myclass = [];
  TextStyle style = const TextStyle(
      color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);
  try {
    DocumentReference<Map<String, dynamic>> DocRef =
    FirebaseFirestore.instance.collection('Class').doc(Student_id);
    DocumentSnapshot<Map<String, dynamic>> tmp = await DocRef.get();
    for (var sche in tmp.data()!['class']) {
      ScheduleModel schedule = ScheduleModel(
          id: Student_id,
          date: sche.toDate(),
          teacher: Student_teacher_id,
          rebook: false,
          name: Student_name);
      myclass.add(schedule);
    }

    for (var sche in tmp.data()!['rebooked']) {
      if(sche.toDate().isBefore(semesterduration[thissemester[0]][0])){
        print(sche.toDate());
      } else {
        ScheduleModel schedule = ScheduleModel(
            id: Student_id,
            date: sche.toDate(),
            teacher: Student_teacher_id,
            rebook: true,
            name: Student_name);
        myclass.add(schedule);
      }
    }
    Student_schedule_list = myclass;
  } catch (e) {
    print(e);
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Container(
                child: Text(
                  '오류',
                  style: style.copyWith(
                    color: PRIMARY_COLOR,
                    fontSize: 17,
                  ),
                  textAlign: TextAlign.center,
                )),
            content: Text('스케쥴을 불러오는데 오류가 발생했습니다',
                style: style.copyWith(fontSize: 15)),
          );
        });
  }
}