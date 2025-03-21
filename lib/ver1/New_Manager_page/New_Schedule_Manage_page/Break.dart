import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/Semester_card.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/New_Schedule_Manage_page/New_shcedule_manage_page.dart';
import '../../New_Data/new_constant.dart';

class Break extends StatefulWidget {
  const Break({super.key});
  @override
  State<Break> createState() => _Break();
}

class _Break extends State<Break>
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

  var TMP = BreakDays[DateTime.now().year];

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    titlestring = '$year년 휴원 일정';
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
                            titlestring = '${year + 1}년 휴원 일정';
                            TMP = BreakDays[year+1];
                          });
                        } else{
                          titlestring = '$year년 휴원 일정';
                          TMP = BreakDays[year];
                        }
                      });
                    }),
              ),
              body: Container(
                  padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
                  child: ListView.builder(
                      itemCount: TMP!.length,
                      itemBuilder: (context, index) {
                        return Column(
                          children: [
                            InkWell(
                              onTap: (){},
                              child: Semestercard(
                                startTime: TMP![index]!,
                                endTime: TMP![index]!.add(Duration(days: 6)),
                                year: TMP![index]!.year,
                                month: TMP![index]!.month,),
                            ),
                            const SizedBox(height: 5)
                          ],
                        );
                      }))
          ),
        ));
  }
}
