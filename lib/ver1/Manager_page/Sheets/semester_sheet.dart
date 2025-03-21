import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Schedule_Manage_page/Semester_page.dart';

class semester_sheet extends StatefulWidget {
  const semester_sheet({super.key});

  @override
  State<semester_sheet> createState() => _semester_sheet();
}

class _semester_sheet extends State<semester_sheet> {
  @override
  final GlobalKey<FormState> formKey = GlobalKey();

  DateTime tmp = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Form(
        key: formKey,
        child: SafeArea(
            child: Container(
                height: MediaQuery.of(context).size.height / 3 + bottomInset,
                color: Colors.white,
                child: Padding(
                  padding: EdgeInsets.only(
                      left: 8, right: 8, top: 8, bottom: 8 + bottomInset),
                  child: Column(
                    children: [
                      const SizedBox(height: 15),
                      const Text('학기 시작 날짜 선택',
                          style: TextStyle(
                            color: Colors.black,
                            fontFamily: 'ELAND',
                            fontWeight: FontWeight.w300,
                            fontSize: 17,
                          )),
                      TextButton(
                          onPressed: () async {
                            tmp = (await showDatePicker(
                                context: context,
                                firstDate: DateTime(2024, 1, 1),
                                lastDate: DateTime(2050, 12, 31)))!;
                            setState(() {
                              tapday = tmp;
                            });
                          },
                          child: Text(
                              '${tapday.year}.${tapday.month}.${tapday.day} ~',
                              style: const TextStyle(
                                color: PRIMARY_COLOR,
                                fontFamily: 'ELAND',
                                fontWeight: FontWeight.w300,
                                fontSize: 30,
                              ))),
                      const Text('학기 마지막 날짜 선택',
                          style: TextStyle(
                            color: Colors.black,
                            fontFamily: 'ELAND',
                            fontWeight: FontWeight.w300,
                            fontSize: 17,
                          )),
                      TextButton(
                          onPressed: () async {
                            tmp = (await showDatePicker(
                                context: context,
                                firstDate: DateTime(2024, 1, 1),
                                lastDate: DateTime(2050, 12, 31)))!;
                            setState(() {
                              tapday2 = tmp;
                            });
                          },
                          child: Text('${tapday2.year}.${tapday2.month}.${tapday2.day}',
                              style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,))),
                      const SizedBox(height: 10,),
                      const Expanded(child: SizedBox(),),
                      SizedBox(width: double.infinity,
                          child: ElevatedButton(onPressed: () => onSavePressed(context),
                              style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_COLOR),
                              child: const Text('저장하기', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, color: Colors.white)))),
                    ],
                  ),
                ))));
  }

  void onSavePressed(BuildContext context) async {
    if (formKey.currentState!.validate()) {
      //학기 기간 등록하기
      formKey.currentState!.save();
      await FirebaseFirestore.instance
          .collection('Class')
          .doc(tapyear.toString())
          .update({
        '$tapmonth': [
          DateTime(tapday.year, tapday.month, tapday.day, 0, 0),
          DateTime(tapday2.year, tapday2.month, tapday2.day, 0, 0)
        ]
      });
    }
    await getallsemester();
    Navigator.of(context).pop();
  }
}
