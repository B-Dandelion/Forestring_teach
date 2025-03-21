import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Manager_Home_page.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/new_studnet_sheet.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Student_Manage_page/Student_list_page.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Student_Manage_page/Student_modify_page.dart';


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

class Student_Manage_page extends StatefulWidget {
  const Student_Manage_page({super.key});

  @override
  State<Student_Manage_page> createState() => _Student_Manage_page();
}

class _Student_Manage_page extends State<Student_Manage_page> {

  Duration duration = const Duration(hours: 10, minutes: 0);

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
                    '신규 학생 추가하기',
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
                        builder: (_) => const new_student_sheet(),
                        isScrollControlled: true);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: PRIMARY_COLOR,
                      child: Icon(Icons.format_list_bulleted_rounded,
                          color: Colors.white)),
                  title: const Text(
                    '모든 학생 보기',
                    style: TextStyle(
                        fontFamily: 'ELAND',
                        fontWeight: FontWeight.w300,
                        color: Colors.black),
                  ),
                  tileColor: Colors.white,
                  shape: const Border(
                    top: BorderSide(color: Colors.grey),
                  ),
                  trailing:
                  const Icon(Icons.navigate_next_rounded, color: Colors.grey),
                  onTap: () async {
                    Navigator.of(context).push(
                      _createRoute(const Student_list_page()),
                    );
                  },
                ),
                ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: PRIMARY_COLOR,
                        child: Icon(Icons.auto_fix_high_rounded,
                            color: Colors.white)),
                    title: const Text(
                      '학생 정보 수정하기',
                      style: TextStyle(
                          fontFamily: 'ELAND',
                          fontWeight: FontWeight.w300,
                          color: Colors.black),
                    ),
                    tileColor: Colors.white,
                    shape: const Border(
                      top: BorderSide(color: Colors.grey),
                    ),
                    trailing:
                    const Icon(Icons.navigate_next_rounded, color: Colors.grey),
                    onTap: () {
                      Navigator.of(context)
                          .push(_createRoute(const Student_modify_page()));
                    }),
              ],
            )));
  }
}
