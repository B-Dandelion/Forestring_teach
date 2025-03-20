import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Data/constant.dart';
import 'package:forestring_teacher_2/Data/schedule_model.dart';
import 'package:forestring_teacher_2/Manager_page/Manager_Home_page.dart';
import 'package:forestring_teacher_2/Manager_page/Sheets/bantime_sheet.dart';
import 'package:forestring_teacher_2/Manager_page/Sheets/new_teacher_page.dart';
import 'package:forestring_teacher_2/Manager_page/Teacher_Manage_page/Teacher_list_page.dart';
import 'package:forestring_teacher_2/Manager_page/Teacher_Manage_page/Teacher_schedule_count_page.dart';


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

void sortSchedules(List<ScheduleModel> allschedules){
  nowS = [];
  lastS = [];
  nextS = [];
  DateTime tmp1 = semesterduration[thissemester[1]][0];
  DateTime tmp2 = semesterduration[thissemester[1]][1];
  for(int i=0;i<allschedules.length;i++){
    if(tmp1.isBefore(allschedules[i].date) && tmp2.isAfter(allschedules[i].date)){
      //현재 학기
      nowS.add(allschedules[i]);
    }else if(tmp1.isAfter(allschedules[i].date)){
      lastS.add(allschedules[i]);
    }else{
      nextS.add(allschedules[i]);
    }
  }
  print(lastS);
}

List<ScheduleModel> nowS = [];
List<ScheduleModel> lastS = [];
List<ScheduleModel> nextS = [];

class Teacher_Manage_page extends StatefulWidget {
  const Teacher_Manage_page({super.key});

  @override
  State<Teacher_Manage_page> createState() => _Teacher_Manage_page();
}

//선생님 성함/ 수업으로 나눠서 저장 할 예정.
Map<String,List<ScheduleModel>> n = {};
String TeacherID = AllTeacherList[0].id;

class _Teacher_Manage_page extends State<Teacher_Manage_page> {

  int num = 0;
  int count = 0;


  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: BaseAppBar(title: "\u{1F49A} FORESTRING \u{1F49A}", center: true, appBar: AppBar()),
        drawer: const ManagerDrawer(),
        floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.white,
            shape: const CircleBorder(),
            child: const Icon(Icons.arrow_back_rounded, color: PRIMARY_COLOR),
            onPressed: () {
              Navigator.of(context).push(
                _createRoute(const Manager_Home_page()),
              );
            }),
        body: Container(
            padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
            child: ListView(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: PRIMARY_COLOR,
                      child: Icon(Icons.person_add_alt_rounded,
                          color: Colors.white)),
                  title: const Text(
                    '신규 선생님 추가하기',
                    style: TextStyle(
                        fontFamily: 'ELAND',
                        fontWeight: FontWeight.w300,
                        color: Colors.black),
                  ),
                  tileColor: Colors.white,
                  trailing:
                  const Icon(Icons.navigate_next_rounded, color: Colors.grey),
                  onTap: () {
                    Navigator.of(context).push(
                        _createRoute(const new_teacher_page()));
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: PRIMARY_COLOR,
                      child: Icon(Icons.edit,
                          color: Colors.white)),
                  title: const Text(
                    '선생님 정보 수정하기',
                    style: TextStyle(
                        fontFamily: 'ELAND',
                        fontWeight: FontWeight.w300,
                        color: Colors.black),
                  ),
                  tileColor: Colors.white,
                  trailing:
                  const Icon(Icons.navigate_next_rounded, color: Colors.grey),
                  onTap: () {
                    Navigator.of(context).push(
                        _createRoute(const Teacher_list_page()));
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: PRIMARY_COLOR,
                      child: Icon(Icons.block_rounded,
                          color: Colors.white)),
                  title: const Text(
                    '예약 불가 시간 설정',
                    style: TextStyle(
                        fontFamily: 'ELAND',
                        fontWeight: FontWeight.w300,
                        color: Colors.black),
                  ),
                  tileColor: Colors.white,
                  trailing:
                  const Icon(Icons.navigate_next_rounded, color: Colors.grey),
                  onTap: () {
                    showModalBottomSheet(
                        context: context,
                        isDismissible: true,
                        builder: (_) => const banTime_sheet(),
                        isScrollControlled: true);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: PRIMARY_COLOR,
                      child: Icon(Icons.check_circle_outline_rounded,
                          color: Colors.white)),
                  title: const Text(
                    '학기 수업 횟수 확인하기',
                    style: TextStyle(
                        fontFamily: 'ELAND',
                        fontWeight: FontWeight.w300,
                        color: Colors.black),
                  ),
                  tileColor: Colors.white,
                  trailing:
                  const Icon(Icons.navigate_next_rounded, color: Colors.grey),
                  onTap: () async {
                    n = {};
                    sortSchedules(AllScheduleList);
                    Navigator.of(context).push(
                        _createRoute(const Teacher_schedule_count_page()));
                  },
                ),
              ],
            )
        )
    );
  }
}

