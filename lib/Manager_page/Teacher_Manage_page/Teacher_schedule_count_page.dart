
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/Data/constant.dart';


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

class Teacher_schedule_count_page extends StatefulWidget {
  const Teacher_schedule_count_page({super.key});

  @override
  State<Teacher_schedule_count_page> createState() => _Teacher_schedule_count_page();
}

class _Teacher_schedule_count_page extends State<Teacher_schedule_count_page>
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
  int semester = thissemester[1];
  String semesterstart = '';
  String semesterend = '';
  DateTime tmp = DateTime.now();
  int indexcheck = 1;
  String titlestring = '';
  @override
  void initState() {
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    super.initState();
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
                        semester = thissemester[index];
                        semesterstart = DateFormat('MM.dd')
                            .format(semesterduration[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(semesterduration[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        indexcheck = 1;
                      } else if (index == 0) {
                        semester = thissemester[index];
                        semesterstart = DateFormat('MM.dd')
                            .format(semesterduration[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(semesterduration[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        indexcheck = 0;
                      } else if (index == 2) {
                        semester = thissemester[index];
                        semesterstart = DateFormat('MM.dd')
                            .format(semesterduration[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(semesterduration[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        indexcheck = 2;
                      }
                    });
                  }),
            ),
            body: Container(
                padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
                child: ListView.builder(
                    itemCount: AllTeacherList.length,
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
                        child: Text('${TeacherNameMap[AllTeacherList[index].id]} 선생님 : ${AllTeacherCount[AllTeacherList[index].id]![indexcheck]}',
                            style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20)
                        ),
                      );
                    })
            ),
          ),
        ));
  }
}
