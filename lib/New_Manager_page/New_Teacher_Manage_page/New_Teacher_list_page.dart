import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/New_Data/new_constant.dart';
import 'package:forestring_teacher_2/New_Data/teacherClass.dart';
import 'package:forestring_teacher_2/New_Manager_page/Manager_data/New_teacher_modify_page.dart';
import 'package:forestring_teacher_2/New_Manager_page/New_Teacher_Manage_page/New_Teacher_Manage_page.dart';

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

class New_Teacher_list_page extends StatefulWidget {
  const New_Teacher_list_page({super.key});

  @override
  State<New_Teacher_list_page> createState() => _New_Teacher_list_page();
}

TeacherClass teacher = Allteachers[0];

class _New_Teacher_list_page extends State<New_Teacher_list_page> {
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
                _createRoute(const New_Teacher_Manage_page()),
              );
            }),
        body: Container(
            padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
            child: ListView.builder(
                itemCount: Allteachers.length,
                itemBuilder: (context, index) {
                  return OutlinedButton(
                    onPressed: (){
                      teacher = Allteachers[index];
                      Navigator.of(context).push(
                        _createRoute(const New_teacher_modify_page()),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                        foregroundColor: PRIMARY_COLOR,
                        backgroundColor: Colors.white,
                        side: const BorderSide(
                            color: PRIMARY_COLOR,
                            width: 2
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)
                        ),
                        elevation: 0
                    ),
                    child: Text('${Allteachers[index].name} 선생님',
                        style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20)
                    ),
                  );
                })));
  }
}
