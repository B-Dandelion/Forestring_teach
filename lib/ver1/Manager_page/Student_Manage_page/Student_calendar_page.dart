import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';
import 'package:forestring_teacher_2/ver1/Data/schedule_model.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/manager_today_banner.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/student_modify_sheet.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/student_schedule_card.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Student_Manage_page/Student_modify_page.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

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

class Student_calendar_page extends StatefulWidget {
  const Student_calendar_page({super.key});

  @override
  State<Student_calendar_page> createState() => _Student_calendar_page();
}

class _Student_calendar_page extends State<Student_calendar_page> {
  DateTime selectedDate = DateTime.now();
  DateTime focusedDate = DateTime.now();
  late final ValueNotifier<List<ScheduleModel>> selectedEvents;

  DateTime tmp1 = DateTime(DateTime.now().year, DateTime.now().month, 1)
      .subtract(const Duration(days: 10));
  DateTime tmp2 = DateTime(DateTime.now().year, DateTime.now().month, 20)
      .add(const Duration(days: 55));

  @override
  void initState() {
    super.initState();
    selectedDate = focusedDate;
    selectedEvents = ValueNotifier(_getEvents(selectedDate));
  }

  List<ScheduleModel> _getEvents(DateTime day) {
    List<Map<DateTime, dynamic>> EVENTS = [{}];
    Map<DateTime, dynamic>? events;
    String Dayformat = DateFormat('yyyyMMdd').format(day);
    for (int i = 0; i<Student_schedule_list.length; i++){
      if (DateFormat('yyyyMMdd').format(DateTime.parse(Student_schedule_list[i].date.toString())) == Dayformat) {
        if (events != null && events.containsKey(DateTime.utc(day.year, day.month, day.day))) {
          events[DateTime.utc(day.year, day.month, day.day)]
              .add(Student_schedule_list[i]);
          EVENTS.add(events);
        } else {
          events = {
            DateTime.utc(day.year, day.month, day.day): [Student_schedule_list[i]]
          };
          EVENTS.add(events);
        }
      }
    }
    EVENTS = List.from(EVENTS.reversed);
    return EVENTS[0][day] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BaseAppBar(title: "FORESTRING", center: true, appBar: AppBar()),
      drawer: const ManagerDrawer(),
      floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.white,
          shape: const CircleBorder(),
          child: const Icon(Icons.arrow_back_rounded, color: PRIMARY_COLOR),
          onPressed: () {
            Student_id = '';
            Student_name = '';
            Student_schedule_list = [];
            Student_teacher_id = '';
            Student_teacher_name = '';
            Navigator.of(context).push(
              _createRoute(const Student_modify_page()),
            );
          }),
      body: SafeArea(
        child: Column(
          children: [
            TableCalendar(
              firstDay: DateTime(tmp1.year, tmp1.month, 1),
              lastDay: DateTime(tmp2.year, tmp2.month, 0),
              focusedDay: focusedDate,
              onDaySelected: (DateTime selectedDate, DateTime focusedDate) {
                setState(() {
                  this.selectedDate = selectedDate;
                  this.focusedDate = focusedDate;
                });
              },
              selectedDayPredicate: (day) {
                return isSameDay(selectedDate, day);
              },
              calendarBuilders: CalendarBuilders(dowBuilder: (context, day) {
                final text = DateFormat.E().format(day);
                if (day.weekday == DateTime.sunday) {
                  return Center(
                      child: Text(
                        text,
                        style: const TextStyle(
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w500,
                            color: Colors.red),
                      ));
                } else if (day.weekday == DateTime.saturday) {
                  return Center(
                      child: Text(text,
                          style: const TextStyle(
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w500,
                              color: Colors.blue)));
                } else {
                  return Center(
                      child: Text(text,
                          style: const TextStyle(
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w500,
                          )));
                }
              },
                  // 달력 속 날짜 숫자 색상 변경(요일에 맞게)
                  defaultBuilder: (context, day, _) {
                    return Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                            color: day.weekday == 7
                                ? Colors.red
                                : day.weekday == 6
                                ? Colors.blue
                                : Colors.black),
                      ),
                    );
                  }, markerBuilder: (context, date, events) {
                    if (events.isNotEmpty) {
                      return Column(
                        children: [
                          const SizedBox(height: 45),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                                color: Color(0xff2E8B57), shape: BoxShape.circle),
                          ),
                        ],
                      );
                    }
                    return null;
                  }),
              headerStyle: const HeaderStyle(
                titleCentered: true,
                formatButtonVisible: false,
                titleTextStyle: TextStyle(
                  fontFamily: 'OpenSans',
                  fontWeight: FontWeight.w500,
                  fontSize: 20.0,
                ),
              ),

              calendarStyle: const CalendarStyle(
                isTodayHighlighted: true,
                todayDecoration: BoxDecoration(
                  color: Color(0xff124736),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(
                  color: Colors.white,
                  fontFamily: 'openSans',
                  fontWeight: FontWeight.w500,
                ),
                weekendDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                ),
                weekendTextStyle: TextStyle(
                  color: Colors.red,
                  fontFamily: 'openSans',
                  fontWeight: FontWeight.w300,
                ),
                selectedDecoration: BoxDecoration(
                  color: Color(0xff708C7A),
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: TextStyle(
                  color: Colors.black,
                  fontFamily: 'openSans',
                  fontWeight: FontWeight.w500,
                ),
                defaultTextStyle: TextStyle(
                  fontFamily: 'openSans',
                  fontWeight: FontWeight.w300,
                ),
              ),
              eventLoader: _getEvents,
              onPageChanged: (focusedDate) {
                // No need to call `setState()` here
                focusedDate = focusedDate;
              },
            ),
            const SizedBox(height: 8),
            ManagerTodayBanner(selectedDate: selectedDate),
            const SizedBox(height: 8),
            SingleChildScrollView(
                child: SizedBox(
                    height: 200,
                    // steambuilder로 구현하기
                    child: ListView.builder(
                        itemCount: _getEvents(selectedDate).length,
                        itemBuilder: (context, index) {
                          final schedule = _getEvents(selectedDate);
                          final EVENTS = schedule[index];
                          DateTime tmp = EVENTS.date;
                          return Padding(
                              padding: const EdgeInsets.only(
                                  bottom: 8, left: 8, right: 8),
                              child: student_ScheduleCard(
                                  startTime: tmp.hour*100 + tmp.minute,
                                  endTime: tmp.add(const Duration(minutes: 30)).hour*100 + tmp.add(const Duration(minutes: 30)).minute,
                                  studentID: Student_name,
                                  rebook: EVENTS.rebook,
                                  teacher: Student_teacher_name,
                                  time: tmp)
                          );
                        }))),
            const Expanded(child: SizedBox()),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(50, 35),
                    side: const BorderSide(color: PRIMARY_COLOR, width: 1.5)),
                onPressed: () async {
                  await myschedule(context);
                  _getEvents(selectedDate);
                },
                child: const Text('새로고침',
                    style:
                    TextStyle(fontFamily: 'ELAND', color: PRIMARY_COLOR))),
          ],
        ),
      ),
    );
  }
}
Future<void> myschedule(BuildContext context) async {
  List<ScheduleModel> myclass = [];
  List<DateTime> TmpClass = [];
  TextStyle style = const TextStyle(
      color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);
  try {
    DocumentReference<Map<String, dynamic>> DocRef =
    FirebaseFirestore.instance.collection('Class').doc(Student_id);
    DocumentSnapshot<Map<String, dynamic>> tmp = await DocRef.get();
    for (var sche in tmp.data()!['class']) {
        ScheduleModel schedule = ScheduleModel(
            id: Student_id,
            date: sche.toDate(),
            teacher: Student_teacher_id,
            rebook: false,
            name: Student_name);
        myclass.add(schedule);
    }

    for (var sche in tmp.data()!['rebooked']) {
      if(sche.toDate().isBefore(semesterduration[thissemester[0]][0])){
        print(sche.toDate());
      } else {
        ScheduleModel schedule = ScheduleModel(
            id: Student_id,
            date: sche.toDate(),
            teacher: Student_teacher_id,
            rebook: true,
            name: Student_name);
        myclass.add(schedule);
      }
    }
    Student_schedule_list = myclass;
  } catch (e) {
    print(e);
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Container(
                child: Text(
                  '오류',
                  style: style.copyWith(
                    color: PRIMARY_COLOR,
                    fontSize: 17,
                  ),
                  textAlign: TextAlign.center,
                )),
            content: Text('스케쥴을 불러오는데 오류가 발생했습니다',
                style: style.copyWith(fontSize: 15)),
          );
        });
  }
}