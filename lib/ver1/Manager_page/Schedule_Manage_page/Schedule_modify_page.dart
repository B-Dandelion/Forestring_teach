import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/manager_schedule_card.dart';
import 'package:forestring_teacher_2/ver1/Data/schedule_model.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/rebook_modify_sheet.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/schedule_modify_sheet.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';

String selectedID = '';
String selectedName = '';
String selectedTeacher = '';
DateTime selectedTime = DateTime.now();

class Schedule_modify_page extends StatefulWidget {
  const Schedule_modify_page({super.key});

  @override
  State<Schedule_modify_page> createState() => _Schedule_modify_page();
}

class _Schedule_modify_page extends State<Schedule_modify_page>
    with SingleTickerProviderStateMixin{

  final TextStyle textStyle = const TextStyle(
      fontWeight: FontWeight.w300,
      fontFamily: 'ELAND',
      color: PRIMARY_COLOR,
      fontSize: 20);

  final List<Tab> myTabs = <Tab>[
    Tab(text: '${thissemester[0]}월'),
    Tab(text: '${thissemester[1]}월'),
    Tab(text: '${thissemester[2]}월'),
    const Tab(text: '예약'),
    const Tab(text: '취소')
  ];

  TabController? _tabController;
  int semester = thissemester[1];
  String semesterstart = '';
  String semesterend = '';
  DateTime tmp = DateTime.now();
  List<ScheduleModel> TMP = [];
  List<ScheduleModel> TMP1 = [];
  List<ScheduleModel> TMP2 = [];
  List<ScheduleModel> TMP3 = [];
  String titlestring = '';
  bool isrebooked = false;

  @override
  void initState() {
    _tabController = TabController(length: 5, vsync: this, initialIndex: 0);
    semester = thissemester[1];
    semesterstart = DateFormat('MM.dd').format(semesterduration[semester][0]);
    semesterend = DateFormat('MM.dd').format(semesterduration[semester][1]);
    titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
    for(int i=0;i<AllScheduleList.length;i++){
      if(AllScheduleList[i].date.isAfter(semesterduration[thissemester[1]][0]) &&
          AllScheduleList[i].date.isBefore(semesterduration[thissemester[1]][1])
      ){ // 현재 학기다
        TMP2.add(AllScheduleList[i]);
      } else if (AllScheduleList[i].date.isAfter(semesterduration[thissemester[0]][0]) &&
          AllScheduleList[i].date.isBefore(semesterduration[thissemester[0]][1])){
        //이전 학기다
        TMP1.add(AllScheduleList[i]);
      } else if (AllScheduleList[i].date.isAfter(semesterduration[thissemester[2]][0]) &&
          AllScheduleList[i].date.isBefore(semesterduration[thissemester[2]][1])){
        //다음 학기다
        TMP3.add(AllScheduleList[i]);
      }
    }
    TMP = TMP1;
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
                await getallschedules();
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
                        semester = thissemester[index];
                        semesterstart = DateFormat('MM.dd')
                            .format(semesterduration[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(semesterduration[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        TMP = TMP1;
                      } else if (index == 1) {
                        // 이번 학기
                        semester = thissemester[index];
                        semesterstart = DateFormat('MM.dd')
                            .format(semesterduration[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(semesterduration[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        TMP = TMP2;
                      } else if (index == 2) {
                        // 다음 학기
                        semester = thissemester[index];
                        semesterstart = DateFormat('MM.dd')
                            .format(semesterduration[semester][0]);
                        semesterend = DateFormat('MM.dd')
                            .format(semesterduration[semester][1]);
                        titlestring = '$semester월 수업 ($semesterstart - $semesterend)';
                        TMP = TMP3;
                      } else if (index == 3) {
                        // 재예약된 수업
                        semester = thissemester[1];
                        titlestring = '예약된 수업';
                        TMP = AllRebookedList;
                      } else if (index == 4) {
                        // 취소된 수업
                        semester = thissemester[1];
                        titlestring = '취소된 수업';
                        TMP = AllCanceledList;
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
                      return Column(
                        children: [
                          InkWell(
                            onTap: (){
                              setState(() {
                                selectedID = TMP[index].id;
                                selectedName = TMP[index].name;
                                selectedTeacher = TeacherNameMap[TMP[index].teacher]!;
                                selectedTime = TMP[index].date;
                              });
                              // if(TMP[index].date.isBefore(DateTime.now())){
                              //   // 과거 수업인 경우, 안내 팝업을 띄우고 '아니오'를 누를 경우 팝업을 팝하기. '예'의 경우 코드를 개별적으로 추가.
                              //   showDialog(
                              //       context: context,
                              //       builder: (BuildContext context) {
                              //         return AlertDialog(
                              //           title: Container(
                              //               child: Text(
                              //                 '과거 수강 내역입니다.',
                              //                 style: style.copyWith(
                              //                   color: PRIMARY_COLOR,
                              //                   fontSize: 15,
                              //                 ),
                              //                 textAlign: TextAlign.center,
                              //               )),
                              //         );
                              //       });
                              // }

                              if (TMP[index].date.isBefore(DateTime.now())) {
                                // 과거 수업인 경우, 안내 팝업을 띄우고 수업 내용을 변경하는 코드
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: Text(
                                        '과거 수강 내역입니다',
                                        style: style.copyWith(
                                          color: PRIMARY_COLOR,
                                          fontSize: 15,
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
                                            if (AllRebookedList.any((rebookedClass) => rebookedClass == TMP[index])) {
                                              showModalBottomSheet(
                                                context: context,
                                                isDismissible: true,
                                                builder: (_) => const rebook_modify_sheet(),
                                                isScrollControlled: true,
                                              );
                                            } else {
                                              showModalBottomSheet(
                                                context: context,
                                                isDismissible: true,
                                                builder: (_) => const schedule_modify_sheet(),
                                                isScrollControlled: true,
                                              );
                                            }
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
                              }
                              else if (AllCanceledList.any((canceledClass) => canceledClass == TMP[index])) {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: Container(
                                        child: Text(
                                          '취소된 수업은 변경할 수 없습니다!',
                                          style: style.copyWith(
                                            color: PRIMARY_COLOR,
                                            fontSize: 15,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              } else if (AllRebookedList.any((rebookedClass) => rebookedClass == TMP[index])) {
                                showModalBottomSheet(
                                    context: context,
                                    isDismissible: true,
                                    builder: (_) => const rebook_modify_sheet(),
                                    isScrollControlled: true);
                              } else {
                                showModalBottomSheet(
                                    context: context,
                                    isDismissible: true,
                                    builder: (_) => const schedule_modify_sheet(),
                                    isScrollControlled: true);
                              }
                            },
                            child: Manager_ScheduleCard(
                              startTime: TMP[index].date.hour *100 + TMP[index].date.minute,
                              teacher: TeacherNameMap[TMP[index].teacher]!,
                              endTime: TMP[index].date.add(const Duration(minutes: 30)).hour *100
                                  + TMP[index].date.add(const Duration(minutes: 30)).minute,
                              month: TMP[index].date.month,
                              date: TMP[index].date.day,
                              studentID: TMP[index].name,
                              teachercolor: Color_list[AllTeacherList.indexWhere((teacher) => teacher.id == TMP[index].teacher)],
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


