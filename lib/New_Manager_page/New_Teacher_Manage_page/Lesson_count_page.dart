import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/New_Data/teacherClass.dart';
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

class Lesson_count_page extends StatefulWidget {
  const Lesson_count_page({super.key});

  @override
  State<Lesson_count_page> createState() => _Lesson_count_page();
}

class _Lesson_count_page extends State<Lesson_count_page>
    with SingleTickerProviderStateMixin{
  final TextStyle textStyle = const TextStyle(
      fontWeight: FontWeight.w300,
      fontFamily: 'ELAND',
      color: PRIMARY_COLOR,
      fontSize: 20);

  final List<Tab> myTabs = <Tab>[
    const Tab(text: '지난 학기'),
    const Tab(text: '이번 학기'),
    const Tab(text: '다음 학기')
  ];

  int count = 0;

  TabController? _tabController;
  int semester = nowsemester.month;
  String semesterstart = '';
  String semesterend = '';
  DateTime tmp = DateTime.now();
  Map<String,int> countlist = Allcount2;
  String titlestring = '';

  @override
  void initState() {
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
        length: myTabs.length,
        child: Scaffold(
          appBar: BaseAppBar(
              title: "\u{1F49A} FORESTRING \u{1F49A}",
              center: true,
              appBar: AppBar()),
          drawer: const ManagerDrawer(),
          body: Scaffold(
            appBar: AppBar(
              title: Text(titlestring, style: textStyle),
              bottom: TabBar(
                  controller: _tabController,
                  tabs: myTabs,
                  labelStyle: textStyle.copyWith(fontSize: 13),
                  onTap: (index) async {
                    setState(() {
                      if (index == 1) {
                        semester = nowsemester.month;
                        semesterstart = DateFormat('MM.dd')
                            .format(SemesterTerm[nowsemester.month][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(SemesterTerm[nowsemester.month][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        countlist = Allcount2;
                      } else if (index == 0) {
                        semester = previoussemester.month;
                        semesterstart = DateFormat('MM.dd')
                            .format(SemesterTerm[previoussemester.month][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(SemesterTerm[previoussemester.month][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        countlist = Allcount1;
                      } else if (index == 2) {
                        semester = nextsemester.month;
                        semesterstart = DateFormat('MM.dd')
                            .format(SemesterTerm[nextsemester.month][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(SemesterTerm[nextsemester.month][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        countlist = Allcount3;
                      }
                    });
                  }),
            ),
            body: Container(
                padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
                child: ListView.builder(
                    itemCount: Allteachers.length,
                    itemBuilder: (context, index) {
                      return OutlinedButton(
                        onPressed: (){},
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
                        child: Text('${Allteachers[index].name} 선생님 : ${countlist[Allteachers[index].id]}',
                            style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20)
                        ),
                      );
                    })
            ),
          ),
        ));
  }
}
