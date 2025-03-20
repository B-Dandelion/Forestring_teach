import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Data/constant.dart';
import 'package:forestring_teacher_2/Data/schedule_model.dart';
import 'package:forestring_teacher_2/Data/student_model.dart';
import 'package:forestring_teacher_2/Manager_page/Student_Manage_page/Student_modify_page.dart';
import 'package:forestring_teacher_2/Manager_page/Student_Manage_page/Student_sycalendar_page.dart';
import 'package:intl/intl.dart';

class Modify_page extends StatefulWidget {
  const Modify_page({super.key});

  @override
  State<Modify_page> createState() => _Modify_page();
}

String Student_id = '';
String Student_name = '';
List<StudentModel> Student_others = [];
List<ScheduleModel> Student_schedule_list = [];
List<ScheduleModel> Student_rebook_list = [];
List<DateTime> Student_others_schedule = [];
Map<String, dynamic> Student_teacher_BanTime = {};
List<String> Student_teacher_bantime = [];
Map<String, dynamic> Student_teacher_WorkTime = {};
String Student_teacher_id = '';
String Student_teacher_name = '';

class _Modify_page extends State<Modify_page> {
  String Teacher = selectedTeacher;
  String TeacherName = TeacherNameMap[selectedTeacher]!;
  DateTime startTime = selectedTime;
  DateTime? outtime;

  DateTime tmp = DateTime(2024, 10, 10, 10, 00);
  TimeOfDay TMP = TimeOfDay.fromDateTime(DateTime(2024, 10, 10, 10, 00));

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
                _createRoute(const Student_modify_page()),
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
                                      Student_id = selectedID;
                                      Student_name = selectedName;
                                      Student_teacher_id = selectedTeacher;
                                      Student_teacher_name = TeacherNameMap[selectedTeacher]!;
                                    });
                                    await myschedule(context);
                                    await getworkhour(Student_teacher_id);
                                    Navigator.of(context).push(
                                      _createRoute(const sy_calendar_page()),
                                    );
                                  },
                                  child: Text('$selectedName 학생',
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
                                        childCount: AllTeacherList.length,
                                        onSelectedItemChanged: (i) {
                                          setState(() {
                                            Teacher = AllTeacherList[i].id;
                                            TeacherName =
                                                AllTeacherList[i].name;
                                          });
                                        },
                                        itemBuilder: (context, index) {
                                          return Text(
                                              '${AllTeacherList[index].name} 선생님',
                                              style: const TextStyle(
                                                color: PRIMARY_COLOR,
                                                fontFamily: 'ELAND',
                                                fontWeight: FontWeight.w300,
                                                fontSize: 20,
                                              ));
                                        },
                                      )),
                                  child: Text('$TeacherName 선생님',
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
                                      startTime = DateTime(
                                          tmp.year,
                                          tmp.month,
                                          tmp.day,
                                          startTime.hour,
                                          startTime.minute);
                                    });
                                  },
                                  child: Text(
                                      DateFormat('yyyy년 MM월 dd일').format(startTime),
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
                                            hour: startTime.hour,
                                            minute: startTime.minute)))!;
                                    setState(() {
                                      startTime = DateTime(
                                          startTime.year,
                                          startTime.month,
                                          startTime.day,
                                          TMP.hour,
                                          TMP.minute);
                                    });
                                  },
                                  child: Text(
                                      '${(startTime.hour).toString().padLeft(2, '0')} : ${(startTime.minute).toString().padLeft(2, '0')}',
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
                                        firstDate: DateTime(2024, 1, 1),
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
                                        OUT(context);
                                      },
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      child: const Text('OUT 기능 활성화',
                                          style: TextStyle(
                                              fontFamily: 'ELAND',
                                              fontWeight: FontWeight.w300,
                                              color: Colors.white)))),
                              // TextButton(
                              //     onPressed: () async {
                              //       await OUT(context);
                              //       //수업 삭제, 로그인 정보 삭제,
                              //     },
                              //     child: Text(
                              //         'OUT 기능 활성화기',
                              //         style: TextStyle(
                              //           color: PRIMARY_COLOR,
                              //           fontFamily: 'ELAND',
                              //           fontWeight: FontWeight.w300,
                              //           fontSize: 20,
                              //         ))),

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
  void OUT(BuildContext context) async {
    if(outtime != null){
      // 아웃 날짜 이후로 수업을 삭제합니다.
      var doc = await FirebaseFirestore.instance.collection('Class').doc(selectedID).get();
      var tmp = doc.data()!['class'];
      var TMP = [];
      for (var classDate in tmp) {
        if (classDate.toDate().isAfter(outtime)) {
          // 이후 수업은 전부 삭제됨.
        } else {
          TMP.add(classDate);
        }
      }
      // Firestore에 업데이트
      await FirebaseFirestore.instance.collection('Class').doc(selectedID).update({'class': TMP});
      String outname = '$selectedName (탈퇴)';
      // 로그인 못하게 막기.
      await FirebaseFirestore.instance.collection('student').doc(selectedID).update({'name': outname});
    }
    Navigator.of(context).pop();
  }
  void onSavePressed(BuildContext context) async{
    final DateTime tmp = DateTime.now();
    if(formKey.currentState!.validate()){
      try{
        //파이어 베이스에 수정된 정보 등록하기
        await FirebaseFirestore.instance.collection('student').doc(selectedID).update({'startTime' : startTime});
        //수정된 수업 정보를 이후 수업 일정에 반영합니다.
        var doc = await FirebaseFirestore.instance.collection('Class').doc(Student_id).get();
        var tmp = doc.data()!['class'];
        var TMP = [];

        // startTime 전 주 일요일을 계산
        DateTime sundayBeforeStartTime = startTime.subtract(Duration(days: startTime.weekday));

        // 새로운 리스트 생성하여 수정된 날짜를 저장
        for (var classDate in tmp) {
          if (classDate.isAfter(sundayBeforeStartTime)) {
            // startTime과 같은 요일과 시간으로 조정
            num daysDifference = (startTime.weekday - classDate.weekday) % 7;
            TMP.add(DateTime(
              classDate.year,
              classDate.month,
              classDate.day + daysDifference,
              startTime.hour,
              startTime.minute,
            ));
          } else {
            TMP.add(classDate);
          }
        }
        // Firestore에 업데이트
        await FirebaseFirestore.instance.collection('Class').doc(Student_id).update({'class': TMP});

        //학생 정보에 저장된 선생님 정보 수정하기
        await FirebaseFirestore.instance.collection('student').doc(selectedID).update({'teacher' : Teacher});

        if(Teacher != selectedTeacher){
          //담당 선생님이 변경된 경우
          DocumentReference<Map<String, dynamic>> DocumentRef =
          FirebaseFirestore.instance.collection('teacher').doc(selectedTeacher);
          DocumentSnapshot<Map<String, dynamic>> docSnap = await DocumentRef.get();
          var tmp = docSnap.data()!['students'];
          tmp.remove(selectedID);
          await FirebaseFirestore.instance.collection('teacher').doc(selectedTeacher).update({'students' : tmp});
          //기존 선생님 리스트에서 학생 ID 삭제하기

          DocumentRef = FirebaseFirestore.instance.collection('teacher').doc(Teacher);
          docSnap = await DocumentRef.get();
          tmp = docSnap.data()!['students'];
          tmp.add(selectedID);
          await FirebaseFirestore.instance.collection('teacher').doc(Teacher).update({'students' : tmp});
          //새로운 선생님 리스트에 학생 ID 추가하기

        }
        await getallstudents();
        await getallteachers();
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
                content: Text('학생 정보를 수정하는 과정에서 오류가 발생했습니다',
                    style: style.copyWith(fontSize: 15)),
              );
            });
      }
    }
    Navigator.of(context).pop();
  }
}

Future<void> myschedule(BuildContext context) async {
  Student_schedule_list = [];
  Student_rebook_list = [];
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
      Student_schedule_list.add(schedule);
    }
    for (var sche in tmp.data()!['rebooked']) {
      if (sche.toDate().isBefore(semesterduration[thissemester[0]][0])) {
        print(sche.toDate());
      } else {
        ScheduleModel schedule = ScheduleModel(
            id: Student_id,
            date: sche.toDate(),
            teacher: Student_teacher_id,
            rebook: true,
            name: Student_name);
        Student_rebook_list.add(schedule);
      }
    }
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
Future<void> getworkhour(String teacherID) async {
  //선생님의 근무 시간을 불러와 저장해 주는 함수.
  DocumentReference<Map<String, dynamic>> DocumentRef =
  FirebaseFirestore.instance.collection('teacher').doc(teacherID);
  DocumentSnapshot<Map<String, dynamic>> DocumentSnap = await DocumentRef.get();

  var tmp = await FirebaseFirestore.instance
      .collection('teacher')
      .doc(teacherID)
      .collection('BanTime')
      .get();
  for (var doc in tmp.docs) {
    //벤타임 업데이트
    Student_teacher_bantime.add(doc.id);
    Student_teacher_BanTime.addAll({
      doc.id: [
        doc.data()['0'].toDate(),
        doc.data()['1'].toDate()
      ]
    });
  }
  Map<String, dynamic>? doc = DocumentSnap.data();
  if (doc != null) {
    Student_teacher_WorkTime = {
      'Mon': [
        doc['Mon'][0].toDate(),
        doc['Mon'][1].toDate()
      ],
      'Tue': [
        doc['Tue'][0].toDate(),
        doc['Tue'][1].toDate()
      ],
      'Wed': [
        doc['Wed'][0].toDate(),
        doc['Wed'][1].toDate()
      ],
      'Thu': [
        doc['Thu'][0].toDate(),
        doc['Thu'][1].toDate()
      ],
      'Fri': [
        doc['Fri'][0].toDate(),
        doc['Fri'][1].toDate()
      ],
      'Sat': [
        doc['Sat'][0].toDate(),
        doc['Sat'][1].toDate()
      ],
    };
    print(WorkTime);
  }
}
Future<void> otherstudent(BuildContext context) async {
  // 선생님의 다른 학생들을 불러옵니다.
  TextStyle style = const TextStyle(
      color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);
  try {
    Student_others = [];
    DocumentReference<Map<String, dynamic>> DocumentRef = FirebaseFirestore
        .instance
        .collection('teacher')
        .doc(Student_teacher_id);
    DocumentSnapshot<Map<String, dynamic>> tmp = await DocumentRef.get();
    Student_others = tmp.data()!['students'];
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
            content: Text('학생 정보를 불러오는 과정에서 오류가 발생했습니다',
                style: style.copyWith(fontSize: 15)),
          );
        });
  }
}
Future<void> othersshcedule(BuildContext context) async {
  //선생님의 다른 학생들의 스케줄을 불러옵니다
  Student_others_schedule = [];
  List<DateTime> TmpClass = [];

  TextStyle style = const TextStyle(
      color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);

  try {
    for (int i =0; i < Student_others.length; i ++ ){
      if(Student_others[i].id != Student_id) {
        DocumentReference<Map<String, dynamic>> DocRef =
        FirebaseFirestore.instance.collection('Class').doc(Student_others[i].id);
        DocumentSnapshot<Map<String, dynamic>> tmp = await DocRef.get();
        for (var sche in tmp.data()!['class']){
          TmpClass.add(sche.toDate());
        }
        for (var shce in tmp.data()!['rebooked']) {
          TmpClass.add(shce.toDate());
        }
      }
    }
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
  Student_others_schedule = TmpClass;
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
