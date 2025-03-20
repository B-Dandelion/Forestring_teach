import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/New_Data/lessonCard.dart';
import 'package:forestring_teacher_2/New_Data/lessonClass.dart';
import 'package:forestring_teacher_2/New_Data/new_constant.dart';
import 'package:intl/intl.dart';

int selectedmonth = 0;
int selectedyear = 0;

class New_Class_page extends StatefulWidget {
  const New_Class_page({super.key});

  @override
  State<New_Class_page> createState() => _New_Class_page();
}

class _New_Class_page extends State<New_Class_page>
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
  DateTime tmp = DateTime.now();
  int semester = nowsemester.month;
  String semesterstart = '';
  String semesterend = '';
  List<Lesson> TMP = [];
  List<Lesson> NowLesson = [];
  List<Lesson> ChangedLesson = [];
  List<Lesson> PreviousLesson = [];
  List<Lesson> CanceledLesson = [];
  String titlestring = '';

  @override
  void initState() {
    _tabController = TabController(length: 4, vsync: this, initialIndex: 1);
    semesterstart = DateFormat('MM.dd').format(SemesterTerm[semester][0]);
    semesterend = DateFormat('MM.dd').format(SemesterTerm[semester][1]);
    titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
    for(int i=0;i<LessonList.length;i++){
      if(LessonList[i].isValid == true){
        // 취소되지 않은 수업들만
        if(LessonList[i].time.isAfter(SemesterTerm[nowsemester.month][0]) &&
            LessonList[i].time.isBefore(SemesterTerm[nowsemester.month][1])
        ){ // 현재 학기다
          if (!["01", "02", "03", "04"].contains(LessonList[i].id.substring(LessonList[i].id.length - 2))){
            // 정규 수업이 아닌 경우
            ChangedLesson.add(LessonList[i]);
          }
          NowLesson.add(LessonList[i]);
          // 현재 학기 리스트에는 정규 수업 + 예약 수업 모두 저장됨
        }else if (LessonList[i].time.isAfter(SemesterTerm[previousMonth.month][0]) &&
            LessonList[i].time.isBefore(SemesterTerm[previousMonth.month][1])){
          //저번 학기다
          PreviousLesson.add(LessonList[i]);
        }
      } else {
        //취소된 수업
        CanceledLesson.add(LessonList[i]);
      }
    }
    TMP = NowLesson;
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
                        semester = nowsemester.month;
                        semesterstart = DateFormat('MM.dd')
                            .format(SemesterTerm[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(SemesterTerm[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        TMP = NowLesson;
                      } else if (index == 0) {
                        semester = previoussemester.month;
                        semesterstart = DateFormat('MM.dd')
                            .format(SemesterTerm[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(SemesterTerm[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        TMP = PreviousLesson;
                      } else if (index == 2) {
                        semester = nowsemester.month;
                        titlestring = '$semester월 예약한 수업';
                        TMP = ChangedLesson;
                      } else {
                        semester = nowsemester.month;
                        titlestring = '$semester월 취소된 수업';
                        TMP = CanceledLesson;
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
                          LessonCard_main(startTime: TMP[index].time, lessonID: TMP[index].id, month: TMP[index].time.month,
                              date: TMP[index].time.day, student: StudentName[TMP[index].id.substring(0,12)]!, teacher: User.name),
                          const SizedBox(height: 5)
                        ],
                      );
                    })
            ),
          ),
        ));
  }
}
