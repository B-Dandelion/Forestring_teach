import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/Semester_card.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/New_Schedule_Manage_page/New_shcedule_manage_page.dart';
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

// Future<Map<int, List<DateTime>>> getSemesterDates() async {
//   int currentYear = nowsemester.year; // 올해 연도
//   int nextYear = currentYear + 1; // 내년 연도
//
//   // Firebase Firestore에서 Class 컬렉션에 접근하여 학기 데이터를 가져옴
//   var currentYearDoc = await FirebaseFirestore.instance
//       .collection('Class')
//       .doc('$currentYear')
//       .get();
//
//   var nextYearDoc = await FirebaseFirestore.instance
//       .collection('Class')
//       .doc('$nextYear')
//       .get();
//
//   // 학기 시작과 끝 날짜를 배열로 추출
//   List<DateTime> currentYearSemesters = _getSemestersFromDoc(currentYearDoc);
//   List<DateTime> nextYearSemesters = _getSemestersFromDoc(nextYearDoc);
//
//   // 연도별 학기 정보를 Map 형태로 반환
//   return {
//     currentYear: currentYearSemesters,
//     nextYear: nextYearSemesters,
//   };
// }
// List<DateTime> _getSemestersFromDoc(DocumentSnapshot doc) {
//   List<DateTime> semesters = [];
//
//   if (doc.exists) {
//     // 각 월(1, 2, 3, ...)에 해당하는 필드를 가져옴
//     for (int month = 1; month <= 12; month++) {
//       String fieldName = '$month'; // 필드명 (1, 2, 3, ...)
//       if (doc.data() != null) {
//         List<dynamic> semesterDates = doc[fieldName]; // 필드에 저장된 학기 날짜 배열
//         if (semesterDates != null && semesterDates.length >= 2) {
//           DateTime start = (semesterDates[0] as Timestamp).toDate();
//           DateTime end = (semesterDates[1] as Timestamp).toDate();
//           semesters.add(start);
//           semesters.add(end);
//         }
//       }
//     }
//   }
//   return semesters;
// }

class New_Semester_page extends StatefulWidget {
  const New_Semester_page({super.key});
  @override
  State<New_Semester_page> createState() => _New_Semester_page();
}

DateTime tapday = DateTime.now();
DateTime tapday2 = DateTime.now();
int tapyear = DateTime.now().year;
int tapmonth = DateTime.now().month;

class _New_Semester_page extends State<New_Semester_page>
    with SingleTickerProviderStateMixin{
  final TextStyle textStyle = const TextStyle(
      fontWeight: FontWeight.w300,
      fontFamily: 'ELAND',
      color: PRIMARY_COLOR,
      fontSize: 20);

  final List<Tab> myTabs = <Tab>[
    const Tab(text: '올해 학기'),
    const Tab(text: '내년 학기'),
  ];

  TabController? _tabController;
  int year = nowsemester.year;
  String titlestring = '';
  // Map<String,List> Semesterarray = Semester1;

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
                                  tapmonth = index+1;
                                });},
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
