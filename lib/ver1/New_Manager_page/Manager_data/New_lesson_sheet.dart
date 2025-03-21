import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/ver1/New_Data/lessonClass.dart';
import 'package:forestring_teacher_2/ver1/New_Data/new_constant.dart';
import 'package:forestring_teacher_2/ver1/New_Data/studentClass.dart';

class New_lesson_sheet extends StatefulWidget {
  const New_lesson_sheet({super.key});

  @override
  State<New_lesson_sheet> createState() => _New_lesson_sheet();
}

class _New_lesson_sheet extends State<New_lesson_sheet>{
  final GlobalKey<FormState> formKey = GlobalKey();
  DateTime tmp = DateTime.now();
  DateTime savetmp = DateTime.now();
  TimeOfDay TMP = const TimeOfDay(hour: 10, minute: 00);
  TimeOfDay saveTMP = const TimeOfDay(hour: 10, minute: 00);
  StudentClass selectedstudnet = Allstudents[0];

  @override
  Widget build(BuildContext context){
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Form(
        key: formKey,
        child : SafeArea(
            child: Container(
                height: MediaQuery.of(context).size.height / 2.5 + bottomInset,
                color: Colors.white,
                child: Padding( padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomInset+8),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        const Text('수강생 선택하기', style: TextStyle(
                            color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17)),
                        TextButton(
                            onPressed: () => _showDialog(
                                CupertinoPicker.builder(
                                  itemExtent: 30,
                                  childCount: Allstudents.length,
                                  onSelectedItemChanged: (i){
                                    setState(() {
                                      selectedstudnet = Allstudents[i];
                                    });
                                  },
                                  itemBuilder: (context, index){
                                    return Text('${Allstudents[index].name} 학생', style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20,));
                                  },
                                )
                            ),
                            child: Text('${selectedstudnet.name} 학생',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,))),
                        const SizedBox(height: 10),
                        const Text('보강 날짜 선택하기', style: TextStyle(
                            color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17)),
                        TextButton(onPressed: () async {
                          tmp = (await showDatePicker(context: context, firstDate: DateTime(2024,1,1), lastDate: DateTime(2050,12,31)))!;
                          setState(() {
                            savetmp = tmp;
                          });
                        },
                            child: Text('${savetmp.year}.${savetmp.month}.${savetmp.day}',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25))),
                        const Text('보강 시간 선택',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () async {
                              TMP = (await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 00)))!;
                              setState(() {
                                saveTMP = TMP;
                              });
                            },
                            child: Text('${(saveTMP.hour).toString().padLeft(2,'0')} : ${(saveTMP.minute).toString().padLeft(2,'0')}',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,))),
                        const Expanded(child: SizedBox()),
                        SizedBox(width: double.infinity,
                            child: ElevatedButton(onPressed: () => onSavePressed(context),
                                style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_COLOR),
                                child: const Text('추가하기', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, color: Colors.white)))),
                      ],
                    ))
            )
        )
    );
  }
  String? contentValidater(String? val) {
    if(val == null || val.isEmpty){
      return '내용을 입력해주세요!';
    }
    return null;
  }
  void _showDialog(Widget child){
    showCupertinoModalPopup(context: context, builder: (BuildContext context) =>
        Container(
            color: CupertinoColors.systemBackground.resolveFrom(context),
            height: MediaQuery.of(context).size.height / 3,
            padding: const EdgeInsets.only(top: 4),
            margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SafeArea(top: false,child: child,)
        )
    );
  }
  void onSavePressed(BuildContext context) async{
    if(formKey.currentState!.validate()){
      formKey.currentState!.save();
      final NEWSchedule = DateTime(savetmp.year, savetmp.month, savetmp.day, saveTMP.hour, saveTMP.minute,);
      // 학기 정보를 가져오기 위해 Firebase에 접근
      String year = NEWSchedule.year.toString();
      String month = NEWSchedule.month.toString();
      DocumentSnapshot<Map<String, dynamic>> semesterDoc = await FirebaseFirestore.instance
          .collection('Class')
          .doc(year)
          .get();

      // 학기 정보 가져오기
      List<dynamic> semesterList = semesterDoc.data()?[month] ?? [];
      if (semesterList.length < 2) {
        throw Exception('Invalid semester data for $year-$month');
      }
      DateTime semesterStart = (semesterList[0] as Timestamp).toDate();
      DateTime semesterEnd = (semesterList[1] as Timestamp).toDate();

      String semesterCode;
      if (NEWSchedule.isBefore(semesterStart)) {
        // 이전 학기 코드
        DateTime prevMonth = DateTime(NEWSchedule.year, NEWSchedule.month - 1, 1);
        semesterCode = DateFormat('yyMM').format(prevMonth);
      } else if (NEWSchedule.isAfter(semesterEnd)) {
        // 다음 학기 코드
        DateTime nextMonth = DateTime(NEWSchedule.year, NEWSchedule.month + 1, 1);
        semesterCode = DateFormat('yyMM').format(nextMonth);
      } else {
        // 현재 학기 코드
        semesterCode = DateFormat('yyMM').format(NEWSchedule);
      }
      final random = Random();
      int randomNum;
      do {
        randomNum = random.nextInt(100); // 0부터 99까지 숫자 생성
      } while (randomNum >= 1 && randomNum <= 6); // 1~6 제외

      final String lessonID = '${selectedstudnet.id}_$semesterCode${(randomNum).toString().padLeft(2, '0')}';
      final NewLesson = Lesson(id: lessonID, time: NEWSchedule, isValid: true);

      //파이어 베이스에 새로운 스케줄 등록

      // Class 컬렉션에 정보 추가
      await FirebaseFirestore.instance.collection('Class').doc(lessonID).set(NewLesson.toJson());

      // teacher 문서에 학생 정보 추가
      DocumentReference<Map<String, dynamic>> documentRef =
      FirebaseFirestore.instance.collection('User').doc(selectedstudnet.teacherID);
      await documentRef.update({'classList': FieldValue.arrayUnion([lessonID])});

      // student 문서에도 추가해줌
      var docu =  FirebaseFirestore.instance.collection('User').doc(selectedstudnet.id);
      await docu.update({'classList': FieldValue.arrayUnion([lessonID])});
    }
    Navigator.of(context).pop();
  }
}
