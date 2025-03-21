import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Data/schedule_model.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Student_Manage_page/Student_calendar_page.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Student_Manage_page/Student_modify_page.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';

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

String Student_id = '';
String Student_name = '';
List<ScheduleModel> Student_schedule_list = [];
String Student_teacher_id = '';
String Student_teacher_name = '';

class student_modify_sheet extends StatefulWidget {
  const student_modify_sheet({super.key});

  @override
  State<student_modify_sheet> createState() => _student_modify_sheet();
}

class _student_modify_sheet extends State<student_modify_sheet>{
  String Teacher = selectedTeacher;
  String TeacherName = TeacherNameMap[selectedTeacher]!;
  DateTime startTime = selectedTime;

  DateTime tmp = DateTime(2024,10,10,10,00);
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
                child: Padding( padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomInset),
                    child: Column(
                      children: [
                        const SizedBox(height: 5,),
                        const Text('수강생 이름',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17)),
                        const SizedBox(height: 10,),
                        TextButton(
                            onPressed: () async {
                              setState(() {
                                Student_id = selectedID;
                                Student_name = selectedName;
                                Student_teacher_id = selectedTeacher;
                                Student_teacher_name = TeacherNameMap[selectedTeacher]!;
                              });
                              await myschedule(context);
                              Navigator.of(context).push(
                                _createRoute(const Student_calendar_page()),
                              );
                            },
                            child: Text('$selectedName 학생',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,))),
                        const SizedBox(height: 10,),
                        const Text('담당 선생님',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () => _showDialog(
                                CupertinoPicker.builder(
                                  itemExtent: 30,
                                  childCount: AllTeacherList.length,
                                  onSelectedItemChanged: (i){
                                    setState(() {
                                      Teacher = AllTeacherList[i].id;
                                      TeacherName = AllTeacherList[i].name;
                                    });
                                  },
                                  itemBuilder: (context, index){
                                    return Text('${AllTeacherList[index].name} 선생님', style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20,));
                                  },
                                )
                            ),
                            child: Text('$TeacherName 선생님',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,))),
                        const SizedBox(height: 8),
                        const Text('수업 날짜 선택',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () async {
                              tmp = (await showDatePicker(context: context,
                                  firstDate: DateTime(2024, 1, 1),
                                  lastDate: DateTime(2050, 12, 31)))!;
                              setState(() {
                                startTime = DateTime(tmp.year, tmp.month, tmp.day, startTime.hour, startTime.minute);
                              });
                            },
                            child: Text( DateFormat('yyyy년 MM월 dd일').format(startTime),
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,))),
                        const SizedBox(height: 10,),
                        const Text('수업 시간 선택',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () async {
                              TMP = (await showTimePicker(context: context, initialTime: TimeOfDay(hour: startTime.hour, minute: startTime.minute)))!;
                              setState(() {
                                startTime = DateTime(startTime.year, startTime.month, startTime.day, TMP.hour, TMP.minute);
                              });
                            },
                            child: Text('${(startTime.hour).toString().padLeft(2,'0')} : ${(startTime.minute).toString().padLeft(2,'0')}',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,))),
                        const Expanded(child: SizedBox()),
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
        //파이어 베이스에 수정된 정보 등록하기
        await FirebaseFirestore.instance.collection('student').doc(selectedID).update({'startTime' : startTime});
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