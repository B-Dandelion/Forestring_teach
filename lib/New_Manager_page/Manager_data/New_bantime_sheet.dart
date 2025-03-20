import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/New_Data/lessonClass.dart';
import 'package:forestring_teacher_2/New_Data/new_constant.dart';
import 'package:forestring_teacher_2/New_Data/teacherClass.dart';
import 'package:intl/intl.dart';

class New_banTime_sheet extends StatefulWidget {
  const New_banTime_sheet({super.key});

  @override
  State<New_banTime_sheet> createState() => _New_banTime_sheet();
}

class _New_banTime_sheet extends State<New_banTime_sheet>{
  @override

  final GlobalKey<FormState> formKey = GlobalKey();

  DateTime tmp = DateTime.now();
  DateTime tapday = DateTime.now();

  TimeOfDay TMP = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay taptime1 = const TimeOfDay(hour: 1, minute: 0);
  TimeOfDay taptime2 = const TimeOfDay(hour: 2, minute: 0);

  TeacherClass tmpTeacher = Allteachers[0];

  @override
  Widget build(BuildContext context){
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Form(
        key: formKey,
        child : SafeArea(
            child: Container(
                height: MediaQuery.of(context).size.height / 2.5 + bottomInset,
                color: Colors.white,
                child: Padding( padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomInset + 8),
                    child: Column(
                      children: [
                        const SizedBox(height: 15),
                        TextButton(onPressed: () => _showDialog(
                          CupertinoPicker.builder(
                            itemExtent: 30,
                            childCount: Allteachers.length,
                            onSelectedItemChanged: (i) async {
                              setState(() {
                                tmpTeacher = Allteachers[i];
                              });
                            },
                            itemBuilder: (context, index){
                              return Text('${Allteachers[index].name} 선생님',
                                  style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20,));
                            },
                          ),
                        ),
                          child: Text('${tmpTeacher.name} 선생님',
                              style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,)),
                        ),
                        const SizedBox(height: 10,),
                        const Text('예약 불가능 날짜 선택하기',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () async {
                              tmp = (await showDatePicker(context: context, firstDate: DateTime(2024,1,1), lastDate: DateTime(2050,12,31)))!;
                              setState(() {
                                tapday = tmp;
                              });
                            },
                            child: Text('${tapday.year}.${tapday.month}.${tapday.day}',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,))),
                        const SizedBox(height: 8),
                        const Text('예약 불가능 시간 선택하기',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            TextButton(
                                onPressed: () async {
                                  TMP = (await showTimePicker(context: context, initialTime: TMP))!;
                                  setState(() {
                                    taptime1 = TMP;
                                  });
                                },
                                child: Text('${(taptime1.hour).toString().padLeft(2,'0')} : ${(taptime1.minute).toString().padLeft(2,'0')}',
                                    style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,))),
                            const Text(' ~ ', style: TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,)),
                            TextButton(
                                onPressed: () async {
                                  TMP = (await showTimePicker(context: context, initialTime: TMP))!;
                                  setState(() {
                                    taptime2 = TMP;
                                  });
                                },
                                child: Text('${(taptime2.hour).toString().padLeft(2,'0')} : ${(taptime2.minute).toString().padLeft(2,'0')}',
                                    style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,))),
                          ],
                        ),
                        const Expanded(child:SizedBox()),
                        SizedBox(width: double.infinity,
                            child: ElevatedButton(onPressed: () => onSavePressed(context),
                                style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_COLOR),
                                child: const Text('저장하기', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, color: Colors.white)))),
                      ],
                    ))
            )
        )
    );
  }
  void onSavePressed(BuildContext context) async{
    if(formKey.currentState!.validate()){
      //벤타임 등록하기
      formKey.currentState!.save();
      // BanTime 토큰 생성
      DateTime start = DateTime(tapday.year,tapday.month,tapday.day,taptime1.hour,taptime1.minute,0);
      DateTime endtime = DateTime(tapday.year,tapday.month,tapday.day,taptime2.hour,taptime2.minute,0);

      List<DateTime> BanTimeList = [];
      DateTime current = start;

      while (current.isBefore(endtime)) {
        BanTimeList.add(current);
        current = current.add(const Duration(minutes: 30)); // 30분 단위로 추가
      }
      List<String> BanTimeID = [];
      String NewBanTimeID = '';
      for (var tapday in BanTimeList) {
        String NewBanTimeID = 'BAN_' '${DateFormat('yyMMddHH').format(tapday)}_${generateRandomSixDigitCode()}';
        Lesson newbantime = Lesson(id: NewBanTimeID, time: tapday, isValid: true);
        // Class에 새로운 BanTime 등록하기
        await FirebaseFirestore.instance.collection('Class').doc(NewBanTimeID).set(newbantime.toJson());
        BanTimeID.add(NewBanTimeID);
      }
      //teacher 필드에도 banTime 반영
      DocumentReference<Map<String, dynamic>> documentRef =
      FirebaseFirestore.instance.collection('User').doc(tmpTeacher.id);
      await documentRef.update({'classList': FieldValue.arrayUnion(BanTimeID)});
    }
    await AllUsers();
    await Alllesson();
    Navigator.of(context).pop();
  }
  String generateRandomSixDigitCode() {
    final random = Random();
    final randomNumber = random.nextInt(900000) + 100000; // 100000 ~ 999999 사이의 숫자 생성
    return randomNumber.toString();
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
}