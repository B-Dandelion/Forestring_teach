import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Manager_page/Student_Manage_page/Modify_page.dart';
import 'package:forestring_teacher_2/Manager_page/Student_Manage_page/Student_Manage_page.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/Data/constant.dart';
import 'package:forestring_teacher_2/Manager_page/Sheets/Student_card.dart';

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
String selectedID = '';
String selectedName = '';
String selectedTeacher = '';
DateTime selectedTime = DateTime.now();

class Student_modify_page extends StatefulWidget {
  const Student_modify_page({super.key});

  @override
  State<Student_modify_page> createState() => _Student_modify_page();
}

class _Student_modify_page extends State<Student_modify_page> {
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
                _createRoute(const Student_Manage_page()),
              );
            }),
        body: Container(
            padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
            child: ListView.builder(
                itemCount: AllStudentList.length,
                itemBuilder: (context, index) {
                  return Column(
                    children: [
                      InkWell(
                        onTap: (){
                          setState(() {
                            selectedID = AllStudentList[index].id;
                            selectedName = AllStudentList[index].name;
                            selectedTeacher = AllStudentList[index].teacherID;
                            selectedTime = AllStudentList[index].startTime;
                          });
                          Navigator.of(context)
                              .push(_createRoute(const Modify_page()));
                          // showModalBottomSheet(
                          //     context: context,
                          //     isDismissible: true,
                          //     builder: (_) => student_modify_sheet(),
                          //     isScrollControlled: true);
                        },
                        child: StudentCard(
                          Day: DateFormat('EEE').format(AllStudentList[index].startTime),
                          startTime: AllStudentList[index].startTime,
                          id: AllStudentList[index].name,
                          teacher: TeacherNameMap[AllStudentList[index].teacherID]!, endTime: AllStudentList[index].startTime.add(const Duration(minutes: 30)),),
                      ),
                      const SizedBox(height: 5)
                    ],
                  );
                })));
  }
}