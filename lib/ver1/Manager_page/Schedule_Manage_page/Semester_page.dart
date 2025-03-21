import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/Semester_card.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/semester_sheet.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';

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

class Semester_page extends StatefulWidget {
  const Semester_page({super.key});

  @override
  State<Semester_page> createState() => _Semester_page();
}

DateTime tapday = DateTime.now();
DateTime tapday2 = DateTime.now();
int tapyear = DateTime.now().year;
int tapmonth = DateTime.now().month;

class _Semester_page extends State<Semester_page>
    with SingleTickerProviderStateMixin{
  final TextStyle textStyle = const TextStyle(
      fontWeight: FontWeight.w300,
      fontFamily: 'ELAND',
      color: PRIMARY_COLOR,
      fontSize: 20);

  final List<Tab> myTabs = <Tab>[
    const Tab(text: '이번 년도 학기'),
    const Tab(text: '다음 년도 학기'),
  ];

  TabController? _tabController;
  int year = semesterduration[thissemester[1]][0].year;
  String titlestring = '';
  var TMP = Semester1;

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    titlestring = '$year년 학기 일정';
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
                        setState(() {
                          titlestring = '${year + 1}년 학기 일정';
                          TMP = Semester2;
                        });
                      } else{
                        titlestring = '$year년 학기 일정';
                        TMP = Semester1;
                      }
                    });
                  }),
            ),
            body: Container(
                padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
                child: ListView.builder(
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      return Column(
                        children: [
                          InkWell(
                            onTap: (){
                              setState(() {
                                tapday = TMP[(index+1).toString()]![0].toDate();
                                tapday2 = TMP[(index+1).toString()]![1].toDate();
                                tapyear = TMP['2']![0].toDate().year;
                                tapmonth = index+1;
                              });
                              showModalBottomSheet(
                                  context: context,
                                  isDismissible: true,
                                  builder: (_) => const semester_sheet(),
                                  isScrollControlled: true);},
                            child: Semestercard(
                              startTime: TMP[(index+1).toString()]![0].toDate(),
                              endTime: TMP[(index+1).toString()]![1].toDate(),
                              year: TMP['2']![0].toDate().year,
                              month: index + 1,),
                          ),
                          const SizedBox(height: 5)
                        ],
                      );
                    }))
          ),
        ));
  }
}
