import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Data/student_model.dart';
import 'package:forestring_teacher_2/Manager_page/Schedule_Manage_page/Schedule_Manage_page.dart';
import 'package:forestring_teacher_2/Manager_page/Sheets/new_schedule_sheet.dart';
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

class New_Schedule_page extends StatefulWidget {
  const New_Schedule_page({super.key});

  @override
  State<New_Schedule_page> createState() => _New_Schedule_page();
}
StudentModel tap = StudentModel(id: '', name: '', teacherID: '', startTime: DateTime.now());
DateTime tmptap = DateTime.now();

class _New_Schedule_page extends State<New_Schedule_page> {
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
                _createRoute(const Schedule_Manage_page()),
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
                          tap = AllStudentList[index];
                          tmptap = tap.startTime;
                          showModalBottomSheet(
                              context: context,
                              isDismissible: true,
                              builder: (_) => const new_schedule_sheet(),
                              isScrollControlled: true);
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
