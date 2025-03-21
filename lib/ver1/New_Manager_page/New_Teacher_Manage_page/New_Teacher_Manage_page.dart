import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/New_Data/new_constant.dart';
import 'package:forestring_teacher_2/ver1/New_Data/teacherClass.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/Manager_data/New_bantime_sheet.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/Manager_data/New_teacher_page.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/New_Manager_Home_page.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/New_Teacher_Manage_page/Lesson_count_page.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/New_Teacher_Manage_page/New_Teacher_list_page.dart';

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

class New_Teacher_Manage_page extends StatefulWidget {
  const New_Teacher_Manage_page({super.key});

  @override
  State<New_Teacher_Manage_page> createState() => _New_Teacher_Manage_page();
}

class _New_Teacher_Manage_page extends State<New_Teacher_Manage_page> {

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
                _createRoute(const New_Manager_Home_page()),
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
                        _createRoute(const New_teacher_page()));
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
                        _createRoute(const New_Teacher_list_page()));
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
                        builder: (_) => const New_banTime_sheet(),
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
                    for (int i = 0; i < Allteachers.length; i++) {
                      // 학기별로 수업을 계산
                      Allcount1[Allteachers[i].id] = await countValidClassesForSemester(Allteachers[i], previoussemester);
                      Allcount2[Allteachers[i].id] = await countValidClassesForSemester(Allteachers[i], nowsemester);
                      Allcount3[Allteachers[i].id] = await countValidClassesForSemester(Allteachers[i], nextsemester);
                    }
                    Navigator.of(context).push(
                        _createRoute(const Lesson_count_page()));
                  },
                ),
              ],
            )
        )
    );
  }
  Future<int> countValidClassesForSemester(TeacherClass teacher, DateTime semester) async {
    final String semesterCode = '${semester.year % 100}${semester.month.toString().padLeft(2, '0')}';
    // 1. 선생님의 classList에 접근
    List<String> classList = teacher.classList;
    // 2. 학기의 년도월과 일치하는 class 이름만 필터링
    List<String> semesterClassList = classList.where((className) {
      String classSemesterCode = className.substring(className.length - 6, className.length - 2);
      return classSemesterCode == semesterCode;
    }).toList();
    int validCount = 0;
    // 3. Firebase에 접근하여 4. valid 값 확인
    for (String classID in semesterClassList) {
      var classDoc = await FirebaseFirestore.instance.collection('Class').doc(classID).get();
      if (classDoc.exists) {
        bool isValid = classDoc.data()?['valid'] ?? false;
        if (isValid) {
          validCount++;
        }
      }
    }
    // 5. 유효한 수업 수 반환
    return validCount;
  }
}

