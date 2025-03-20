import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/New_Data/lessonClass.dart';
import 'package:forestring_teacher_2/New_Data/studentClass.dart';
import 'package:forestring_teacher_2/New_Manager_page/New_Schedule_Manage_page/New_schedule_modify_page.dart';
import 'package:intl/intl.dart';

import '../../New_Data/new_constant.dart';


class Schedule_modify_sheet extends StatefulWidget {
  const Schedule_modify_sheet({super.key});

  @override
  State<Schedule_modify_sheet> createState() => _Schedule_modify_sheet();
}

class _Schedule_modify_sheet extends State<Schedule_modify_sheet>{
  StudentClass studentclass = selectedstudent;
  Lesson lessonclass = selectedlesson;
  DateTime changed = selectedlesson.time;

  DateTime tmp = DateTime.now();
  TimeOfDay TMP = TimeOfDay.fromDateTime(DateTime(2024,10,10,10,00));

  final GlobalKey<FormState> formKey = GlobalKey();

  @override
  Widget build(BuildContext context){
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Form(
        key: formKey,
        child : SafeArea(
            child: Container(
                height: MediaQuery.of(context).size.height / 2 + bottomInset,
                color: Colors.white,
                child: Padding( padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomInset + 8),
                    child: Column(
                      children: [
                        const SizedBox(height: 5,),
                        const Text('수강생 이름',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17)),
                        const SizedBox(height: 10,),
                        Text(selectedstudent.name,
                            style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30)),
                        const SizedBox(height: 10,),
                        const Text('담당 수업 선생님',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17)),
                        const SizedBox(height: 10,),
                        Text('${selectedstudent.teacherName} 선생님',
                            style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30)),
                        const SizedBox(height: 10,),
                        const Text('변경할 수업 날짜 선택',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () async {
                              tmp = (await showDatePicker(context: context,
                                  firstDate: DateTime(2024, 1, 1),
                                  lastDate: DateTime(2050, 12, 31)))!;
                              setState(() {
                                changed = DateTime(tmp.year, tmp.month, tmp.day, changed.hour, changed.minute);
                              });
                            },
                            child: Text( DateFormat('yyyy년 MM월 dd일').format(changed),
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,))),
                        const SizedBox(height: 10,),
                        const Text('수업 시간 선택',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () async {
                              TMP = (await showTimePicker(context: context, initialTime: TimeOfDay(hour: changed.hour, minute: changed.minute)))!;
                              setState(() {
                                changed = DateTime(changed.year, changed.month, changed.day, TMP.hour, TMP.minute);
                              });
                            },
                            child: Text('${(changed.hour).toString().padLeft(2,'0')} : ${(changed.minute).toString().padLeft(2,'0')}',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,))),
                        const Expanded(child: SizedBox()),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton(onPressed: () => onDeletePressed(context),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                child: const Text('수업 취소하기', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, color: Colors.white))),
                            ElevatedButton(onPressed: () => onSavePressed(context),
                                style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_COLOR),
                                child: const Text('저장하기', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, color: Colors.white))),
                          ],
                        ),
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
  void onSavePressed(BuildContext context) async{
    final DateTime tmp = DateTime.now();
    if(formKey.currentState!.validate()){
      try{
        // 수업 시간 변경이므로 time 값을 변경
        await FirebaseFirestore.instance.collection('Class').doc(lessonclass.id).update({'time': changed});
      }catch(e) {
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
    await Alllesson();
    Navigator.of(context).pop();
  }
  void onDeletePressed(BuildContext context) async {
    if(formKey.currentState!.validate()){
      try{
        // 아예 삭제한 것이므로 valid false로 변경
        await FirebaseFirestore.instance.collection('Class').doc(lessonclass.id).update({'valid': false});
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
    await Alllesson();
    Navigator.of(context).pop();
  }

}