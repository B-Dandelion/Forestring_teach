import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/Student_card.dart';
import 'package:forestring_teacher_2/ver1/New_Data/studentClass.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/New_Student_Manage_page/New_modify_page.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/New_Student_Manage_page/New_student_manage_page.dart';
import 'package:intl/intl.dart';

import '../../New_Data/new_constant.dart';

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
StudentClass selectedstudent = Allstudents[0];

class New_Student_modify_page extends StatefulWidget {
  const New_Student_modify_page({super.key});

  @override
  State<New_Student_modify_page> createState() => _New_Student_modify_page();
}

class _New_Student_modify_page extends State<New_Student_modify_page> {
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
                _createRoute(const New_Student_Manage_page()),
              );
            }),
        body: Container(
            padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
            child: ListView.builder(
                itemCount: Allstudents.length,
                itemBuilder: (context, index) {
                  return Column(
                    children: [
                      InkWell(
                        onTap: (){
                          setState(() {
                            selectedstudent = Allstudents[index];
                          });
                          Navigator.of(context)
                              .push(_createRoute(const New_Modify_page()));
                        },
                        child: StudentCard(
                          Day: DateFormat('EEE').format(Allstudents[index].classDay),
                          startTime: Allstudents[index].classDay,
                          id: Allstudents[index].name,
                          teacher: Allstudents[index].teacherName,
                          endTime: Allstudents[index].classDay.add(const Duration(minutes: 30)),),
                      ),
                      const SizedBox(height: 5)
                    ],
                  );
                })));
  }
}