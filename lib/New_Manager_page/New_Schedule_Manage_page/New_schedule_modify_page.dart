import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Manager_page/Sheets/manager_schedule_card.dart';
import 'package:forestring_teacher_2/New_Data/lessonClass.dart';
import 'package:forestring_teacher_2/New_Data/studentClass.dart';
import 'package:forestring_teacher_2/New_Manager_page/Manager_data/Schedule_modify_sheet.dart';
import 'package:intl/intl.dart';

import '../../New_Data/new_constant.dart';

class New_Schedule_modify_page extends StatefulWidget {
  const New_Schedule_modify_page({super.key});

  @override
  State<New_Schedule_modify_page> createState() => _New_Schedule_modify_page();
}

StudentClass selectedstudent = Allstudents[0];
Lesson selectedlesson = Alllessons[0];
String studentId = Alllessons[0].id.substring(0, 12); // 처음 12자리 추출

class _New_Schedule_modify_page extends State<New_Schedule_modify_page>
    with SingleTickerProviderStateMixin{

  final TextStyle textStyle = const TextStyle(
      fontWeight: FontWeight.w300,
      fontFamily: 'ELAND',
      color: PRIMARY_COLOR,
      fontSize: 20);

  final List<Tab> myTabs = <Tab>[
    Tab(text: '${previoussemester.month}월'),
    Tab(text: '${nowsemester.month}월'),
    Tab(text: '${nextsemester.month}월'),
    const Tab(text: '예약'),
    const Tab(text: '취소')
  ];

  TabController? _tabController;
  int semester = nowsemester.month;
  String semesterstart = DateFormat('MM.dd').format(SemesterTerm[nowsemester.month][0]);
  String semesterend = DateFormat('MM.dd').format(SemesterTerm[nowsemester.month][1]);
  DateTime tmp = DateTime.now();

  List<Lesson> TMP = [];
  List<Lesson> NowLesson = [];
  List<Lesson> NextLesson = [];
  List<Lesson> PreviousLesson = [];
  List<Lesson> ChangedLesson = [];
  List<Lesson> CanceledLesson = [];
  String titlestring = '';

  @override
  void initState() {
    _tabController = TabController(length: 5, vsync: this, initialIndex: 1);
    titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
    for(int i=0;i<Alllessons.length;i++){
      if(Alllessons[i].isValid == true && !Alllessons[i].id.startsWith('BAN')){
        // 취소되지 않은 수업들만 || BanTime 은 제외!
        if(Alllessons[i].time.isAfter(SemesterTerm[nowsemester.month][0]) &&
            Alllessons[i].time.isBefore(SemesterTerm[nowsemester.month][1]))
        { // 현재 학기다
          if (!["01", "02", "03", "04"].contains(Alllessons[i].id.substring(Alllessons[i].id.length - 2))){
            // 정규 수업이 아닌 경우
            ChangedLesson.add(Alllessons[i]);
          }
          NowLesson.add(Alllessons[i]);
          // 현재 학기 리스트에는 정규 수업 + 예약 수업 모두 저장됨
        } else if (Alllessons[i].time.isAfter(SemesterTerm[previousMonth.month][0]) &&
            Alllessons[i].time.isBefore(SemesterTerm[previousMonth.month][1])){
          //저번 학기다
          if (!["01", "02", "03", "04"].contains(Alllessons[i].id.substring(Alllessons[i].id.length - 2))){
            // 정규 수업이 아닌 경우
            ChangedLesson.add(Alllessons[i]);
          }
          PreviousLesson.add(Alllessons[i]);
        } else if (Alllessons[i].time.isAfter(SemesterTerm[nextsemester.month][0]) &&
            Alllessons[i].time.isBefore(SemesterTerm[nextsemester.month][1])) {
          // 다음 학기다
          NextLesson.add(Alllessons[i]);
        }
      } else if (Alllessons[i].isValid == false && !Alllessons[i].id.startsWith('BAN')) {
        //취소된 수업
        CanceledLesson.add(Alllessons[i]);
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
              title: "\u{1F49A} FORESTRING \u{1F49A}",
              center: true,
              appBar: AppBar()),
          drawer: const ManagerDrawer(),
          floatingActionButton: FloatingActionButton(
              backgroundColor: Colors.white,
              shape: const CircleBorder(),
              child: const Icon(Icons.refresh, color: PRIMARY_COLOR),
              onPressed: () async {
                await AllUsers();
                await Alllesson();
              }),
          body: Scaffold(
            appBar: AppBar(
              title: Text(titlestring, style: textStyle),
              bottom: TabBar(
                  controller: _tabController,
                  tabs: myTabs,
                  labelStyle: textStyle.copyWith(fontSize: 13),
                  onTap: (index) async {
                    setState(() {
                      if (index == 0) {
                        // 저번 학기
                        semester = previoussemester.month;
                        semesterstart = DateFormat('MM.dd')
                            .format(SemesterTerm[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(SemesterTerm[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        TMP = PreviousLesson;
                      } else if (index == 1) {
                        // 이번 학기
                        semester = nowsemester.month;
                        semesterstart = DateFormat('MM.dd')
                            .format(SemesterTerm[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(SemesterTerm[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        TMP = NowLesson;
                      } else if (index == 2) {
                        // 다음 학기
                        semester = nextsemester.month;
                        semesterstart = DateFormat('MM.dd')
                            .format(SemesterTerm[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(SemesterTerm[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        TMP = NextLesson;
                      } else if (index == 3) {
                        // 재예약된 수업
                        semester = nowsemester.month;
                        titlestring = '예약된 수업';
                        TMP = ChangedLesson;
                      } else if (index == 4) {
                        // 취소된 수업
                        semester = nowsemester.month;
                        titlestring = '취소된 수업';
                        TMP = CanceledLesson;
                      }
                    });
                  }
              ),
            ),
            body: Container(
                padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
                child: ListView.builder(
                    itemCount: TMP.length,
                    itemBuilder: (context, index) {
                      String studentid = TMP[index].id.substring(0,12);
                      int tmpindex = Allstudents.indexWhere((student) => student.id == studentid);
                      String studentname = Allstudents[tmpindex].name;
                      String studentteacher = Allstudents[tmpindex].teacherName;
                      String studentteacherid = Allstudents[tmpindex].teacherID;
                      return Column(
                        children: [
                          InkWell(
                            onTap: (){
                              setState(() {
                                selectedlesson = TMP[index];
                                selectedstudent = Allstudents.firstWhere((s) => s.id == selectedlesson.id.substring(0,12));
                              });
                              // if(TMP[index].time.isBefore(DateTime.now())){
                              // 과거 수업인 경우, 팝업을 띄운 후 수업을 변경할 수 없는 코드
                              //   showDialog(
                              //       context: context,
                              //       builder: (BuildContext context) {
                              //         return AlertDialog(
                              //           title: Container(
                              //               child: Text(
                              //                 '과거 수업은 변경할 수 없습니다',
                              //                 style: style.copyWith(
                              //                   color: PRIMARY_COLOR,
                              //                   fontSize: 15,
                              //                 ),
                              //                 textAlign: TextAlign.center,
                              //               )),
                              //         );
                              //       });
                              // }
                              if (TMP[index].time.isBefore(DateTime.now())) {
                                // 과거 수업인 경우, 안내 팝업을 띄운 후 수업을 수정할 수 있는 코드
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: Text(
                                        '과거 수강 내역입니다',
                                        style: style.copyWith(
                                          color: PRIMARY_COLOR,
                                          fontSize: 17,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      content: Text(
                                        '과거 수업 내용을 변경하시겠습니까?',
                                        style: style.copyWith(
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop(); // 팝업 닫기
                                          },
                                          child: Text(
                                            '아니오',
                                            style: style.copyWith(
                                              color: PRIMARY_COLOR,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop(); // 팝업 닫기
                                            // 기존 코드 실행
                                            showModalBottomSheet(
                                                context: context,
                                                isDismissible: true,
                                                builder: (_) => const Schedule_modify_sheet(),
                                                isScrollControlled: true);
                                          },
                                          child: Text(
                                            '예',
                                            style: style.copyWith(
                                              color: Colors.red,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              } else {
                                showModalBottomSheet(
                                    context: context,
                                    isDismissible: true,
                                    builder: (_) => const Schedule_modify_sheet(),
                                    isScrollControlled: true);
                              }
                            },
                            child: Manager_ScheduleCard(
                              startTime: TMP[index].time.hour * 100 + TMP[index].time.minute,
                              teacher: studentteacher,
                              endTime: TMP[index].time.add(const Duration(minutes: 30)).hour *100
                                  + TMP[index].time.add(const Duration(minutes: 30)).minute,
                              month: TMP[index].time.month,
                              date: TMP[index].time.day,
                              studentID: studentname,
                              teachercolor: Color_list[Allteachers.indexWhere((teacher) => teacher.id == studentteacherid)],
                            ),
                          ),
                          const SizedBox(height: 5)
                        ],
                      );
                    })),
          ),
        ));
  }
}


