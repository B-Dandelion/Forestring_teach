import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Data/constant.dart';
import 'package:forestring_teacher_2/Manager_page/Manager_Home_page.dart';
import 'package:forestring_teacher_2/Manager_page/Schedule_Manage_page/Schedule_modify_page.dart';
import 'package:forestring_teacher_2/Manager_page/Schedule_Manage_page/Semester_page.dart';
import 'package:forestring_teacher_2/Manager_page/Sheets/new_schedule_sheet.dart';


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

class Schedule_Manage_page extends StatefulWidget {
  const Schedule_Manage_page({super.key});

  @override
  State<Schedule_Manage_page> createState() => _Schedule_Manage_page();
}

class _Schedule_Manage_page extends State<Schedule_Manage_page> {

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
                        child: Icon(Icons.post_add,
                            color: Colors.white)),
                    title: const Text(
                      '보강 등록하기',
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
                          builder: (_) => const new_schedule_sheet(),
                          isScrollControlled: true);
                    }),
                ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: PRIMARY_COLOR,
                        child: Icon(Icons.inventory_rounded,
                            color: Colors.white)),
                    title: const Text(
                      '모든 수업 보기',
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
                      Navigator.of(context)
                          .push(_createRoute(const Schedule_modify_page()));
                    }),
                // ListTile(
                //   leading: CircleAvatar(
                //       child: Icon(Icons.inventory_rounded, color: Colors.white),
                //       backgroundColor: PRIMARY_COLOR),
                //   title: Text(
                //     '모든 수업 보기',
                //     style: TextStyle(
                //         fontFamily: 'ELAND',
                //         fontWeight: FontWeight.w300,
                //         color: Colors.black),
                //   ),
                //   tileColor: Colors.white,
                //   shape: Border(
                //     top: BorderSide(color: Colors.grey),
                //   ),
                //   trailing:
                //   Icon(Icons.navigate_next_rounded, color: Colors.grey),
                //   onTap: (){
                //     Navigator.of(context)
                //         .push(_createRoute(const Schedule_modify_page()));
                //   },
                // ),
                // 이 기능을 모든 수업 보기에서 한꺼번에 할 수 있게 합시다.

                // ListTile(
                //     leading: CircleAvatar(
                //         child: Icon(Icons.edit,
                //             color: Colors.white),
                //         backgroundColor: PRIMARY_COLOR),
                //     title: Text(
                //       '예약된 수업 수정하기',
                //       style: TextStyle(
                //           fontFamily: 'ELAND',
                //           fontWeight: FontWeight.w300,
                //           color: Colors.black),
                //     ),
                //     tileColor: Colors.white,
                //     shape: Border(
                //       top: BorderSide(color: Colors.grey),
                //     ),
                //     trailing:
                //     Icon(Icons.navigate_next_rounded, color: Colors.grey),
                //     onTap: () async {
                //       Navigator.of(context)
                //           .push(_createRoute(const Schedule_modify_page()));
                //     }),
                ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: PRIMARY_COLOR,
                        child: Icon(Icons.calendar_today_rounded,
                            color: Colors.white)),
                    title: const Text(
                      '학기 정보 확인하기',
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
                      Navigator.of(context)
                          .push(_createRoute(const Semester_page()));
                    }),
              ],
            )));

  }

  void _showDialog(Widget child) {
    showCupertinoModalPopup(
        context: context,
        builder: (BuildContext context) => Container(
            height: 200,
            padding: const EdgeInsets.only(top: 4),
            margin: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SafeArea(
              top: false,
              child: child,
            )));
  }
}