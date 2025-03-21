import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/New_Data/new_constant.dart';
import 'package:forestring_teacher_2/ver1/New_Data/studentClass.dart';
import 'package:forestring_teacher_2/ver1/New_Data/teacherClass.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/New_Student_Manage_page/New_student_modify_page.dart';

import 'package:intl/intl.dart';

class New_Modify_page extends StatefulWidget {
  const New_Modify_page({super.key});

  @override
  State<New_Modify_page> createState() => _New_Modify_page();
}

class _New_Modify_page extends State<New_Modify_page> {
  DateTime? outtime;
  DateTime tmp = DateTime(2024, 10, 10, 10, 00);
  TimeOfDay TMP = TimeOfDay.fromDateTime(DateTime(2024, 10, 10, 10, 00));
  DateTime StartTime = selectedstudent.classDay;

  StudentClass Student_class = selectedstudent;
  String Teacher_ID = selectedstudent.teacherID;
  TeacherClass? Teacher_class;


  final GlobalKey<FormState> formKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: BaseAppBar(
            title: "\u{1F49A} FORESTRING \u{1F49A}",
            center: true,
            appBar: AppBar()),
        drawer: const ManagerDrawer(),
        floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.white,
            shape: const CircleBorder(),
            child: const Icon(Icons.arrow_back_rounded, color: PRIMARY_COLOR),
            onPressed: () {
              Navigator.of(context).push(
                _createRoute(const New_Student_modify_page()),
              );
            }),
        body: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Container(
              height:  MediaQuery.of(context).size.height ,
              width: MediaQuery.of(context).size.width ,

              padding: const EdgeInsets.only(bottom: 10, left: 15, right: 15, top: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      height: MediaQuery.of(context).size.height * 0.8,
                      color: Colors.white,
                      child: Padding(
                          padding: const EdgeInsets.only(
                              left: 8, right: 8, top: 8, bottom: 8),
                          child: Column(
                            children: [
                              const SizedBox(
                                height: 5,
                              ),
                              const Text('수강생 이름',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontFamily: 'ELAND',
                                      fontWeight: FontWeight.w300,
                                      fontSize: 17)),
                              const SizedBox(
                                height: 10,
                              ),
                              TextButton(
                                  onPressed: () async {
                                    setState(() {
                                      Student_class = selectedstudent;
                                      // 이전 페이지에서 선택한 학생 객체
                                    });
                                    // Navigator.of(context).push(
                                    //   _createRoute(sy_calendar_page()),
                                    // );
                                  },
                                  child: Text('${Student_class.name} 학생',
                                      style: const TextStyle(
                                        color: PRIMARY_COLOR,
                                        fontFamily: 'ELAND',
                                        fontWeight: FontWeight.w300,
                                        fontSize: 25,
                                      ))),
                              const SizedBox(
                                height: 10,
                              ),
                              const Text('담당 선생님',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontFamily: 'ELAND',
                                    fontWeight: FontWeight.w300,
                                    fontSize: 17,
                                  )),
                              TextButton(
                                  onPressed: () =>
                                      _showDialog(CupertinoPicker.builder(
                                        itemExtent: 30,
                                        childCount: Allteachers.length,
                                        onSelectedItemChanged: (i) {
                                          setState(() {
                                            Teacher_class = Allteachers[i];
                                          });
                                        },
                                        itemBuilder: (context, index) {
                                          return Text(
                                              '${Allteachers[index].name} 선생님',
                                              style: const TextStyle(
                                                color: PRIMARY_COLOR,
                                                fontFamily: 'ELAND',
                                                fontWeight: FontWeight.w300,
                                                fontSize: 20,
                                              ));
                                        },
                                      )),
                                  child: Text('${Student_class.teacherName} 선생님',
                                      style: const TextStyle(
                                        color: PRIMARY_COLOR,
                                        fontFamily: 'ELAND',
                                        fontWeight: FontWeight.w300,
                                        fontSize: 25,
                                      ))),
                              const SizedBox(height: 8),
                              const Text('수업 날짜 선택',
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
                                      StartTime = DateTime(
                                          tmp.year,
                                          tmp.month,
                                          tmp.day,
                                          StartTime.hour,
                                          StartTime.minute);
                                    });
                                  },
                                  child: Text(
                                      DateFormat('yyyy년 MM월 dd일').format(StartTime),
                                      style: const TextStyle(
                                        color: PRIMARY_COLOR,
                                        fontFamily: 'ELAND',
                                        fontWeight: FontWeight.w300,
                                        fontSize: 25,
                                      ))),
                              const SizedBox(
                                height: 10,
                              ),
                              const Text('수업 시간 선택',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontFamily: 'ELAND',
                                    fontWeight: FontWeight.w300,
                                    fontSize: 17,
                                  )),
                              TextButton(
                                  onPressed: () async {
                                    TMP = (await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay(
                                            hour: StartTime.hour,
                                            minute: StartTime.minute)))!;
                                    setState(() {
                                      StartTime = DateTime(
                                          StartTime.year,
                                          StartTime.month,
                                          StartTime.day,
                                          TMP.hour,
                                          TMP.minute);
                                    });
                                  },
                                  child: Text(
                                      '${(StartTime.hour).toString().padLeft(2, '0')} : ${(StartTime.minute).toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        color: PRIMARY_COLOR,
                                        fontFamily: 'ELAND',
                                        fontWeight: FontWeight.w300,
                                        fontSize: 25,
                                      ))),
                              const SizedBox(
                                height: 10,
                              ),
                              SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                      onPressed: () => onSavePressed(context),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: PRIMARY_COLOR),
                                      child: const Text('저장하기',
                                          style: TextStyle(
                                              fontFamily: 'ELAND',
                                              fontWeight: FontWeight.w300,
                                              color: Colors.white)))),
                              const SizedBox(
                                height: 20,
                              ),
                              const Text('[OUT 기능]',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontFamily: 'ELAND',
                                    fontWeight: FontWeight.w300,
                                    fontSize: 30,
                                  )),
                              const SizedBox(
                                height: 10,
                              ),
                              const Text('OUT 날짜 선택하기',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontFamily: 'ELAND',
                                    fontWeight: FontWeight.w300,
                                    fontSize: 17,
                                  )),
                              TextButton(
                                  onPressed: () async {
                                    var OUTTIME = (await showDatePicker(
                                        context: context,
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime(2050, 12, 31)))!;
                                    setState(() {
                                      outtime = OUTTIME;
                                    });
                                  },
                                  child: Text(
                                      '$outtime',
                                      style: const TextStyle(
                                        color: PRIMARY_COLOR,
                                        fontFamily: 'ELAND',
                                        fontWeight: FontWeight.w300,
                                        fontSize: 20,
                                      ))),
                              const SizedBox(
                                height: 10,
                              ),
                              SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                      onPressed: () async {
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return AlertDialog(
                                              title: Text(
                                                '탈퇴 활성화',
                                                style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.red),
                                              ),
                                              content: Text(
                                                '정말 탈퇴를 활성화하시겠습니까?',
                                                style: style.copyWith(fontSize: 16),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () async {
                                                    await OUT(context); // out 함수 실행
                                                  },
                                                  child: Text(
                                                    '예',
                                                    style: style.copyWith(color: Colors.red),
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.of(context).pop(),
                                                  child: Text(
                                                    '아니오',
                                                    style: style.copyWith(color: PRIMARY_COLOR),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      child: const Text('OUT 기능 활성화',
                                          style: TextStyle(
                                              fontFamily: 'ELAND',
                                              fontWeight: FontWeight.w300,
                                              color: Colors.white)))),

                            ],
                          ))),
                ],
              ),
            ),
          ),
        ));
  }

  void _showDialog(Widget child) {
    showCupertinoModalPopup(
        context: context,
        builder: (BuildContext context) => Container(
            color: CupertinoColors.systemBackground.resolveFrom(context),
            height: MediaQuery.of(context).size.height / 3,
            padding: const EdgeInsets.only(top: 4),
            margin: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SafeArea(
              top: false,
              child: child,
            )));
  }
  Future<void> OUT(BuildContext context) async {

    if(outtime != null){
      //outtime을 건드리지 않았을 경우 이 함수는 아무것도 실행하지 않고 종료됨
      for (String lessonId in selectedstudent.classList) {
        // 학생 classList에 저장된 lessonID 반복문
        // 모든 레슨 리스트에서 ID가 일치하는 것들을 찾음
        final lesson = Alllessons.firstWhere((lesson) => lesson.id == lessonId);
        if (lesson != null && lesson.time.isAfter(outtime!)) {
          // 만약 찾은 값의 시간이 outtime이후인 경우
          // 수업 취소
          lesson.isValid = false;

          // 취소한 결과를 class, student, teacher에 각각 반영
          // 리스트 새로고침은 함수 끝나고 실행
          await FirebaseFirestore.instance.collection('Class').doc(lesson.id).update({'valid': false});
          await FirebaseFirestore.instance.collection('User').doc(selectedstudent.id).update({
            'classList': FieldValue.arrayRemove([lesson.id])});
          await FirebaseFirestore.instance.collection('User').doc(selectedstudent.teacherID).update({
            'classList': FieldValue.arrayRemove([lessonId]),
          });
        }
      }
      await AllUsers();
      await Alllesson();

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('탈퇴 완료', style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.red)),
            content: Text('학생 정보가 성공적으로 탈퇴 처리되었습니다.', style: style.copyWith(fontSize: 16)),
          );
        },
      );

      // String outname = '$selectedName (탈퇴)';
      // 로그인 못하게 막기.
      Navigator.of(context).pop();
      Navigator.of(context).pop(); // 팝업 두개 다 닫기
    }
  }

  void onSavePressed(BuildContext context) async{
    // 학생 정보 변경 내용 저장하기
    final DateTime tmp = DateTime.now();
    if(formKey.currentState!.validate()){
      try{
        if(StartTime != selectedstudent.classDay){
          print('수업 날짜 변경됨');
          // 수업 날짜가 변경된 경우
          //파이어 베이스에 수정된 정보 등록하기
          await FirebaseFirestore.instance.collection('User').doc(selectedstudent.id).update({'classDay' : StartTime});
          // StartTime 전 주 일요일을 계산
          DateTime previousSunday = StartTime.subtract(Duration(days: StartTime.weekday % 7));
          print('$previousSunday : 직전 일요일');

          // StartTime과 같은 요일로 변경할 수업 리스트
          List<DateTime> updatedClassDates = [];

          // selectedstudent.classList에서 수업 ID 가져오기

          // Alllessons에서 해당 수업 ID를 가진 수업 찾아서 .time을 기준으로 날짜 변경
          for (var classID in selectedstudent.classList) {
            var lessonDoc = await FirebaseFirestore.instance.collection('Class').doc(classID).get();
            if (lessonDoc.exists) {
              DateTime classTime = (lessonDoc.data()?['time'] as Timestamp).toDate();
              DateTime newClassTime = classTime;
              // StartTime 이후 수업 날짜 수정
              if (classTime.isAfter(previousSunday)) {
                print('변경 전 수업 날짜 : $classTime');
                // 요일을 StartTime의 요일로 변경
                int daysDifference = StartTime.weekday - classTime.weekday;
                newClassTime = classTime.add(Duration(days: daysDifference));
                print('새롭게 저장하는 날짜 : $newClassTime');

                await FirebaseFirestore.instance
                    .collection('Class')
                    .doc(classID)
                    .update({'time': newClassTime}); // newTime은 업데이트하려는 새로운 값
              }
            }
          }
        }

        if(Teacher_class!= null && Teacher_class!.id != selectedstudent.teacherID){
          // 담당 선생님이 변경된 경우
          // 기존 선생님 리스트에서 학생 ID 삭제하기
          await FirebaseFirestore.instance.collection('User').doc(selectedstudent.id).update({
            'studentList': FieldValue.arrayRemove([selectedstudent.id]),
          });

          // 새로운 선생님 리스트에 학생 ID 추가하기
          await FirebaseFirestore.instance.collection('User').doc(Teacher_class!.id).update({
            'studentList': FieldValue.arrayUnion([selectedstudent.id]),
          });

          // 학생 정보에 기록된 선생님 ID 변경
          await FirebaseFirestore.instance.collection('User').doc(selectedstudent.id).update({
            'teacherID': Teacher_class!.id,
            'teacherName': Teacher_class!.name,
          });

        }

        await AllUsers();
        await Alllesson();
      } catch(e) {
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
                content: Text('학생 정보를 수정하는 과정에서 오류가 발생했습니다',
                    style: style.copyWith(fontSize: 15)),
              );
            });
      }
    }
    Navigator.of(context).pop();
  }
}

Route _createRoute(Page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => Page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(0.0, 1.0);
      const end = Offset.zero;
      final tween = Tween(begin: begin, end: end);
      final offsetAnimation = animation.drive(tween);
      return child;
    },
  );
}
