import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Data/schedule_model.dart';
import 'package:forestring_teacher_2/ver1/Data/schedule_card.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';

import 'package:intl/intl.dart';

int selectedmonth = 0;
int selectedyear = 0;

class Class_page extends StatefulWidget {
  const Class_page({super.key});

  @override
  State<Class_page> createState() => _Class_page();
}

class _Class_page extends State<Class_page>
    with SingleTickerProviderStateMixin {
  final TextStyle textStyle = const TextStyle(
      fontWeight: FontWeight.w300,
      fontFamily: 'ELAND',
      color: PRIMARY_COLOR,
      fontSize: 20);

  final List<Tab> myTabs = <Tab>[
    const Tab(text: '지난 학기'),
    const Tab(text: '이번 학기'),
    const Tab(text: '예약된 수업'),
    const Tab(text: '취소된 수업')
  ];

  TabController? _tabController;
  int semester = thissemester[1];
  String semesterstart = '';
  String semesterend = '';
  DateTime tmp = DateTime.now();
  List<ScheduleModel> TMP = [];
  List<ScheduleModel> TMP1 = [];
  List<ScheduleModel> TMP2 = [];
  String titlestring = '';
  @override
  void initState() {
    _tabController = TabController(length: 4, vsync: this, initialIndex: 1);
    semester = thissemester[1];
    semesterstart = DateFormat('MM.dd').format(semesterduration[semester][0]);
    semesterend = DateFormat('MM.dd').format(semesterduration[semester][1]);
    titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
    for(int i=0;i<Schedules.length;i++){
      if(Schedules[i].date.isAfter(semesterduration[thissemester[1]][0]) &&
          Schedules[i].date.isBefore(semesterduration[thissemester[1]][1])
      ){ // 현재 학기다
        TMP2.add(Schedules[i]);
      }else if (Schedules[i].date.isAfter(semesterduration[thissemester[0]][0]) &&
          Schedules[i].date.isBefore(semesterduration[thissemester[0]][1])){
        //저번 학기다
        TMP1.add(Schedules[i]);
      }
    }
    TMP = TMP2;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
        length: myTabs.length,
        child: Scaffold(
          appBar: BaseAppBar(
              title: "FORESTRING",
              center: true,
              appBar: AppBar()),
          drawer: const BaseDrawer(),
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
                        TMP = TMP2;
                      } else if (index == 0) {
                        semester = thissemester[index];
                        semesterstart = DateFormat('MM.dd')
                            .format(semesterduration[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(semesterduration[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        TMP = TMP1;
                      } else if (index == 2) {
                        semester = thissemester[1];
                        titlestring = '학생이 예약한 수업';
                        TMP = Rebooked;
                      } else {
                        semester = thissemester[1];
                        titlestring = '학생이 취소한 수업';
                        TMP = Canceled;
                      }
                    });
                  }),
            ),
            body: Container(
                padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
                child: ListView.builder(
                    itemCount: TMP.length,
                    itemBuilder: (context, index) {
                      return Column(
                        children: [
                          ScheduleCard(startTime: TMP[index].date.hour*100 + TMP[index].date.minute,
                              endTime: TMP[index].date.add(const Duration(minutes: 30)).hour * 100 + TMP[index].date.add(const Duration(minutes: 30)).minute,
                              month: TMP[index].date.month,
                              date: TMP[index].date.day,
                              studentID: TMP[index].name,
                              teacher: UserName),
                          const SizedBox(height: 5)
                        ],
                      );
                    })
            ),
          ),
        ));
  }
}
